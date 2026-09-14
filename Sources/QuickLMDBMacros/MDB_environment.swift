import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// @MDB_environment(file:flags:maxReaders:maxDBs:mode:)
//
// attached to a struct that owns an `Environment` and a set of `Database.X` tables as
// stored properties. the expansion generates a single static factory:
//
//     static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self
//
// which sizes the memory map as current file size + headroom, opens the environment with
// the macro-declared flags/readers/dbs/mode, and opens every table in one setup
// write-transaction, deriving each table's name from its property name. runtime
// parameterized environment file names are out of scope for the macro factory — the
// migration-stage consumers hand-roll their own `open(at:)` over a raw
// `MDB_environment` conformance when they need per-tenant file names, and the
// versioned `version:` attribute covers the fresh-file schema-migration story.
//
// the generated factory forces `.noTLS` onto the environment REGARDLESS of the declared
// flags. this is intentional and load-bearing: `.noTLS` binds each read transaction's
// reader slot to the transaction object instead of the thread, which is what makes
// Swift's task-based concurrency — where a task may migrate between threads — safe, and
// what permits multiple live read transactions on a thread (sibling reads) at all.
//
// this macro is purely schema assembly — it contains no transaction logic.
// transaction boundaries are owned by `@MDB_transact` (attached body + peer)
// on the methods of a container holding one or more of these environments. the C
// wrapper layer is untouched; the generated code uses the existing public
// `Environment`, `Transaction`, and `Database.*` API (plus the underscored
// file-size probe in `QuickLMDB._MDBEnvironmentSupport`).
//
// contract: the struct's stored properties must be exactly `env` plus `Database.X` tables.
// plain `Database` (raw MDB_val) tables are supported.
//
// per-table configuration: a `@MDB_table(name:flags:)` attribute on a table
// property is consumed here — an explicit table-name override and extra
// creation flags the declared type cannot express (the typed subtype and its
// comparators stay type-derived). everything is validated up front, with
// friendly diagnostics for name validity/uniqueness and flags-vs-type
// conflicts, per the "no missed opportunities" mandate.

internal struct MDB_environment_macro:MemberMacro, ExtensionMacro {

	// marks every @MDB_environment struct as an environment — the type
	// `@MDB_transact(_:environments:)` accepts in its environments variadic
	static func expansion(of node: SwiftSyntax.AttributeSyntax, attachedTo declaration: some SwiftSyntax.DeclGroupSyntax, providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol, conformingTo protocols: [SwiftSyntax.TypeSyntax], in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.ExtensionDeclSyntax] {
		return [try ExtensionDeclSyntax("""
			extension \(type):MDB_environment {}
			""")]
	}

	enum MacroError:Swift.Error, CustomStringConvertible {
		case notAStruct
		case missingEnv
		case missingFileArg
		case invalidTableName(String)
		case duplicateTableName(String)
		case flagTypeConflict(String, String)

		var description:String {
			switch self {
				case .notAStruct:
					return "@MDB_environment can only be applied to a struct"
				case .missingEnv:
					return "@MDB_environment requires the struct to have a stored property named `env` of type `Environment`"
				case .missingFileArg:
					return "@MDB_environment requires a `file:` argument naming the environment file (e.g. @MDB_environment(file: \"store.mdb\"))"
				case .invalidTableName(let name):
					return "@MDB_table(name: \"\(name)\") is not a valid LMDB table name — the name must be a non-empty string without NUL characters"
				case .duplicateTableName(let name):
					return "two tables resolve to the same LMDB table name \"\(name)\" — table names must be unique within an environment"
				case .flagTypeConflict(let prop, let flag):
					return "@MDB_table(flags: [.\(flag)]) on '\(prop)' contradicts its declared type — the dup-sort flags are expressed by the typed subtype (Strict/DupSort/DupFixed), not by this attribute"
			}
		}
	}

	// a resolved `Database.X` table on an environment: property name, effective LMDB
	// table name (property name unless @MDB_table overrides), the declared
	// type, and any extra creation flags/payload cases for validation.
	internal struct ResolvedTable {
		let property:String              // the stored property name (local + Self init label)
		var name:String                  // the resolved LMDB table name (property name unless overridden)
		var nameIsExpression:Bool        // true when `name:` was a referenced expression (evaluated at runtime, not spliced as a literal)
		let type:String
		var extraFlags:String?    // the `flags:` array expression as written, or nil
		var flagCases:Set<String> // member-case names for conflict validation
	}

	// scans an environment's stored properties for the `env` handle + `Database.X`
	// tables (consuming `@MDB_table`), with the shared table resolution.
	internal static func scanEnvironment(_ decl: StructDeclSyntax) throws -> (hasEnv: Bool, tables: [ResolvedTable]) {
		var hasEnv = false
		var tables:[ResolvedTable] = []
		for member in decl.memberBlock.members {
			guard let prop = member.decl.as(VariableDeclSyntax.self) else {
				continue
			}
			guard let binding = prop.bindings.first, let propName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
				continue
			}
			guard let typeAnnot = binding.typeAnnotation else {
				continue
			}
			if propName == "env" {
				if typeAnnot.type.trimmedDescription.contains("Environment") {
					hasEnv = true
				}
				continue
			}
			let typeText = typeAnnot.type.trimmedDescription
			let isTable: Bool
			if typeText == "Database" {
				isTable = true
			} else if typeText.hasPrefix("Database.") && (typeText.contains("<") && typeText.hasSuffix(">")) {
				isTable = true
			} else {
				isTable = false
			}
			if isTable {
				tables.append(try resolveTable(propertyName:propName, typeText:typeText, attributes:prop.attributes))
			}
		}
		return (hasEnv, tables)
	}

	static func expansion(of node:AttributeSyntax, providingMembersOf declaration:some DeclGroupSyntax, conformingTo protocols:[TypeSyntax], in context:some MacroExpansionContext) throws -> [DeclSyntax] {
		guard let structDecl = declaration.as(StructDeclSyntax.self) else {
			throw MacroError.notAStruct
		}

		// -- attribute arguments
		var fileArg:String? = nil
		var flagsArg = "[.noSubDir]"
		var maxReadersArg = "32"
		var maxDBsArg = "8"
		var modeArg = "[.ownerReadWriteExecute, .groupRead, .otherRead]"
		var versionArg:String? = nil   // nil = the version attribute was NOT written (legacy exact file name)
		if let argList = node.arguments?.as(LabeledExprListSyntax.self) {
			for arg in argList {
				guard let label = arg.label?.text else {
					continue
				}
				let value = arg.expression.trimmedDescription
				switch label {
					case "file": fileArg = value
					case "version": versionArg = value
					case "flags": flagsArg = value
					case "maxReaders": maxReadersArg = value
					case "maxDBs": maxDBsArg = value
					case "mode": modeArg = value
					default: break
				}
			}
		}

		// -- scan stored properties: env + tables (consuming @MDB_table)
		let (hasEnv, tables) = try scanEnvironment(structDecl)
		guard hasEnv else {
			throw MacroError.missingEnv
		}

		guard let fileArg, fileArg.isEmpty == false else {
			throw MacroError.missingFileArg
		}
		try validateTableNames(tables)

		// -- the write-at-depth lint (compile-time, same-type write callees)
		lintWriteBoundaryCalls(in: structDecl, context: context)

		// -- build the open(at:) factory
		var lines:[String] = []
		lines.append("/// opens the environment and all of its tables with a single setup write-transaction.")
		lines.append("/// - parameter basePath: the directory that will contain the environment file (created if")
		lines.append("///   it does not already exist).")
		lines.append("/// - parameter mapHeadroom: added to the current file size when sizing the memory map.")
		lines.append("@available(*, noasync)")
		lines.append("public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {")
		lines.append("    _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)")
		lines.append("    let slash = basePath.hasSuffix(\"/\") ? \"\" : \"/\"")
		if let versionArg {
			// versioned environment files: the schema version rides in the
			// FILE NAME (`<stem>-v<N>.mdb`) — engaged by writing the version
			// attribute. bump the version to ship a fresh file + stream the
			// old one; the old file stays untouched and readable by older
			// binaries (no sentinel, no in-place migration).
			lines.append("    let targetPath = basePath + slash + (\(fileArg).hasSuffix(\".mdb\") ? String(\(fileArg).dropLast(4)) + \"-v\(versionArg)\" + \".mdb\" : \(fileArg) + \"-v\(versionArg)\")")
		} else {
			lines.append("    let targetPath = basePath + slash + \(fileArg)")
		}
		lines.append("    let fileSize = QuickLMDB._MDBEnvironmentSupport.__fileSize(at: targetPath)")
		lines.append("    let env = try Environment(path: targetPath, flags: QuickLMDB.Environment.Flags([.noTLS]).union(\(flagsArg)), mapSize: Int(fileSize + mapHeadroom), maxReaders: \(maxReadersArg), maxDBs: \(maxDBsArg), mode: \(modeArg))")
		lines.append("    let setupTX = try Transaction<Write>(env: env)")
		for table in tables {
			let flagsText = table.extraFlags.map { "QuickLMDB.MDB_db_flags([.create]).union(\($0))" } ?? "[.create]"
			let nameLiteral = table.nameIsExpression ? table.name : "\"\(table.name)\""
			lines.append("    let \(table.property) = try \(table.type)(env: env, name: \(nameLiteral), flags: \(flagsText), tx: setupTX)")
		}
		lines.append("    try setupTX.commit()")
		var initArgs:[String] = ["env: env"]
		for table in tables {
			initArgs.append("\(table.property): \(table.property)")
		}
		lines.append("    return Self(\(initArgs.joined(separator:", ")))")
		lines.append("}")

		return lines.map { DeclSyntax(stringLiteral: $0) }
	}

	// shared validation of the resolved table set: unique names (within this
	// scan) + dup-sort flags on a non-dup typed handle contradict the
	// declared type.
	internal static func validateTableNames(_ tables: [ResolvedTable]) throws {
		var resolvedNames:Set<String> = []
		for table in tables {
			if resolvedNames.contains(table.name) {
				throw MacroError.duplicateTableName(table.name)
			}
			resolvedNames.insert(table.name)
			// dup-sort flags on a non-dup typed handle contradict the declared type
			if table.type.contains("Strict") && !table.flagCases.isDisjoint(with:["dupSort", "dupFixed"]) {
				let badFlag = table.flagCases.contains("dupSort") ? "dupSort" : "dupFixed"
				throw MacroError.flagTypeConflict(table.property, badFlag)
			}
		}
	}

	// - MARK: the write-composition lint (compile-time write-at-depth guard)

	/// an error from the write-composition lint: a boundary body bare-calls a
	/// same-type WRITE boundary.
	private struct WriteCalleeDiagnostic: DiagnosticMessage {
		let text: String
		init(text: String) { self.text = text }
		var message: String { text }
		var diagnosticID: MessageID { MessageID(domain: "QuickLMDB", id: "writeCalleeInsideBoundary") }
		var severity: DiagnosticSeverity { .error }
	}

	/// the compile-time write-at-depth lint. the boundary body/peer roles get
	/// a lexicalContext SHELL (empty member list — verified under the real
	/// compiler), so they cannot classify same-type callees; the MEMBER role is
	/// the only one that sees every member and body, so this validation lives
	/// here. every boundary body is scanned for BARE/`self.` calls to a
	/// same-type `.readWrite` boundary — the spell that opens a SECOND root
	/// write on a live writer (an LMDB writer-mutex deadlock):
	/// - from a `.readWrite` boundary → an error directing the developer to
	///   compose with `try #MDB_transacted(...)` (the sanctioned join);
	/// - from a `.readOnly` boundary → an error (a read transaction cannot
	///   host a write);
	/// - `#MDB_transacted(w(...))`-wrapped calls, bare calls to READ boundaries
	///   (the sibling-read pattern), cross-type receivers (`param.w(...)` — a
	///   DIFFERENT environment, the legitimate cross-env transform), and plain
	///   methods are each left alone.
	/// extension-declared boundaries are a separate declaration the member
	/// macro cannot see — documented residual, the same extension-wall the
	/// whole codebase lives with.
	private static func lintWriteBoundaryCalls(
		in core: StructDeclSyntax,
		context: some MacroExpansionContext
	) {
		var boundaryModes: [String: Bool] = [:]
		for member in core.memberBlock.members {
			guard let fn = member.decl.as(FunctionDeclSyntax.self) else { continue }
			for attr in fn.attributes.compactMap({ $0.as(AttributeSyntax.self) }) {
				guard attr.attributeName.trimmedDescription == "MDB_transact" else { continue }
				guard let argList = attr.arguments?.as(LabeledExprListSyntax.self),
					let modeText = argList.first?.expression.trimmedDescription else { continue }
				boundaryModes[fn.name.text] =
					modeText.hasPrefix(".readWrite") || modeText.hasPrefix("MDB_transact_mode.readWrite")
			}
		}
		let writeSet = Set(boundaryModes.filter { $0.value }.keys)
		guard !writeSet.isEmpty else { return }

		for member in core.memberBlock.members {
			guard let fn = member.decl.as(FunctionDeclSyntax.self),
				let boundaryIsWrite = boundaryModes[fn.name.text],
				let body = fn.body else { continue }
			let visitor = WriteCalleeVisitor(writeSet: writeSet, callerIsReadOnly: !boundaryIsWrite)
			visitor.walk(body)
			for (node, message) in visitor.findings {
				context.diagnose(Diagnostic(node: Syntax(node), message: WriteCalleeDiagnostic(text: message)))
			}
		}
	}

	/// body walker for the write-composition lint: collects bare/`self.` calls
	/// to same-type write boundaries that are not inside `#MDB_transacted(...)`.
	private final class WriteCalleeVisitor: SyntaxVisitor {
		private let writeSet: Set<String>
		private let callerIsReadOnly: Bool
		private(set) var findings: [(node: FunctionCallExprSyntax, message: String)] = []

		init(writeSet: Set<String>, callerIsReadOnly: Bool) {
			self.writeSet = writeSet
			self.callerIsReadOnly = callerIsReadOnly
			super.init(viewMode: .sourceAccurate)
		}

		// the sanctioned join — its argument is a joined call, never linted
		override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
			node.macroName.text == "MDB_transacted" ? .skipChildren : .visitChildren
		}

		override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
			// bare `w(args)` or `self.w(args)` only — a cross-type receiver
			// (`param.w(...)` = a DIFFERENT environment) is exempt
			let calleeName: String?
			if let bare = node.calledExpression.as(DeclReferenceExprSyntax.self) {
				calleeName = bare.baseName.text
			} else if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
				let base = member.base?.as(DeclReferenceExprSyntax.self),
				base.baseName.text == "self" {
				calleeName = member.declName.baseName.text
			} else {
				calleeName = nil
			}
			guard let name = calleeName, writeSet.contains(name) else { return .visitChildren }
			if callerIsReadOnly {
				findings.append((node, "calling write boundary '\(name)' from a read-only boundary cannot compose — a read transaction cannot host a write. make this boundary read-write, or call '\(name)' outside the boundary"))
			} else {
				findings.append((node, "calling write boundary '\(name)' from inside a write boundary opens a SECOND root write on this environment and deadlocks LMDB's writer mutex — compose with try #MDB_transacted(\(name)(...)) so the callee joins this boundary's transaction"))
			}
			return .visitChildren
		}
	}

	// -- @MDB_table consumption

	/// the table's effective schema: derived defaults when no attribute present
	/// (name = property name, no extra flags); the explicit `name:`/`flags:`
	/// overrides plus their validation otherwise.
	internal static func resolveTable(propertyName:String, typeText:String, attributes:AttributeListSyntax) throws -> ResolvedTable {
		guard let attrList = attributes.first(where: { attr in
			(attr.as(AttributeSyntax.self)?.attributeName.trimmedDescription) == "MDB_table"
		}), let attr = attrList.as(AttributeSyntax.self) else {
			return ResolvedTable(property:propertyName, name:propertyName, nameIsExpression:false, type:typeText, extraFlags:nil, flagCases:[])
		}
		var nameOverride:String? = nil
		var nameIsExpression = false
		var extraFlags:String? = nil
		var flagCases:Set<String> = []
		if let argList = attr.arguments?.as(LabeledExprListSyntax.self) {
			for arg in argList {
				guard let label = arg.label?.text else { continue }
				switch label {
					case "name":
						let content: String
						if let lit = arg.expression.as(StringLiteralExprSyntax.self),
						   let seg = lit.segments.first?.as(StringSegmentSyntax.self) {
							content = seg.content.text
						} else {
							// a referenced expression (e.g. `Tables.foo.rawValue`):
							// single-sourcing — it must be evaluated at RUNTIME,
							// not spliced as a string literal of its own text
							content = arg.expression.trimmedDescription
							nameIsExpression = true
						}
						guard content.isEmpty == false, content.contains("\u{0}") == false else {
							throw MacroError.invalidTableName(content)
						}
						nameOverride = content
					case "flags":
						extraFlags = arg.expression.trimmedDescription
						if let array = arg.expression.as(ArrayExprSyntax.self) {
							for element in array.elements {
								if let member = element.expression.as(MemberAccessExprSyntax.self) {
									flagCases.insert(member.declName.baseName.text)
								}
							}
						}
					default:
						break
				}
			}
		}
		return ResolvedTable(property:propertyName, name:nameOverride ?? propertyName, nameIsExpression:nameIsExpression, type:typeText, extraFlags:extraFlags, flagCases:flagCases)
	}
}
