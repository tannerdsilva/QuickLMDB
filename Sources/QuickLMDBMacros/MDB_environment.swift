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
// write-transaction, deriving each table's name from its property name.
//
// the file name has two modes, selected by whether `file:` is written:
//   - `file:` written -> a FIXED name (an expression, spliced into the factory).
//   - `file:` OMITTED -> RUNTIME mode: the generated factory takes a REQUIRED
//     `fileName: String` parameter, so one type can own per-tenant files
//     (`fiat-<base>.mdb`). `version:` applies to the supplied name exactly as it
//     does to a fixed one, and `encryption:` composes with it (both parameters
//     are required, `fileName:` first).
//
// configuration state: a stored property that is neither `env` nor a table MUST be
// marked `@MDB_state`. each marked property becomes one REQUIRED parameter on the
// generated factory (declaration order, after `fileName:` and before
// `encryptionKey:`) and is carried into the instance — so an environment core can
// own its own logger/config instead of pushing them onto a wrapper type. an
// UNMARKED extra property is a diagnostic: the previous silent skip surfaced as a
// cryptic memberwise-initializer failure at the generated `Self(...)` call.
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
		case invalidTableName(String)
		case duplicateTableName(String)
		case flagTypeConflict(String, String)
		case undeclaredProperty(String)
		case mutableState(String)
		case stateNeedsType(String)
		case defaultedState(String)

		var description:String {
			switch self {
				case .notAStruct:
					return "@MDB_environment can only be applied to a struct"
				case .missingEnv:
					return "@MDB_environment requires the struct to have a stored property named `env` of type `Environment`"
				case .invalidTableName(let name):
					return "@MDB_table(name: \"\(name)\") is not a valid LMDB table name — the name must be a non-empty string without NUL characters"
				case .duplicateTableName(let name):
					return "two tables resolve to the same LMDB table name \"\(name)\" — table names must be unique within an environment"
				case .flagTypeConflict(let prop, let flag):
					return "@MDB_table(flags: [.\(flag)]) on '\(prop)' contradicts its declared type — the dup-sort flags are expressed by the typed subtype (Strict/DupSort/DupFixed), not by this attribute"
				case .undeclaredProperty(let prop):
					return "stored property '\(prop)' is neither the `env` handle nor a `Database.X` table — declare it `@MDB_state` if it is environment configuration, or remove it: the generated initializer cannot carry it"
				case .mutableState(let prop):
					return "`@MDB_state` property '\(prop)' must be declared `let` — an environment core is an immutable handle, not a mutable bag"
				case .stateNeedsType(let prop):
					return "`@MDB_state` property '\(prop)' requires an explicit type annotation — the generated `open` takes it as a parameter"
				case .defaultedState(let prop):
					return "`@MDB_state` property '\(prop)' cannot carry a default value — Swift's implicit memberwise initializer omits `let` properties that already hold one, so the generated `open` could never set it; author the default at the call site instead (e.g. a `static func openForDaemon(...)` alias)"
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

	// a resolved `@MDB_state` configuration property: the property name (also the
	// generated `open` parameter label) and its declared type, verbatim.
	internal struct ResolvedState {
		let property:String
		let type:String
	}

	// the ordered scan of an environment's stored properties. DECLARATION ORDER
	// matters: the generated `Self(...)` call must match the implicit memberwise
	// initializer's parameter order, which follows declaration order.
	internal enum ScannedProperty {
		case env
		case table(ResolvedTable)
		case state(ResolvedState)
	}

	// scans an environment's stored properties: the `env` handle, `Database.X`
	// tables (consuming `@MDB_table`), and `@MDB_state` configuration. anything
	// else is a diagnostic — the generated initializer cannot carry it, and the
	// previous silent skip surfaced as a cryptic memberwise-init failure.
	internal static func scanEnvironment(_ decl: StructDeclSyntax) throws -> [ScannedProperty] {
		var scanned:[ScannedProperty] = []
		for member in decl.memberBlock.members {
			guard let prop = member.decl.as(VariableDeclSyntax.self) else {
				continue
			}
			// statics are not instance state; computed properties are not stored state
			if prop.modifiers.contains(where: { $0.name.text == "static" || $0.name.text == "class" }) {
				continue
			}
			guard let binding = prop.bindings.first, let propName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
				continue
			}
			if binding.accessorBlock != nil {
				continue
			}
			if propName == "env" {
				guard let typeAnnot = binding.typeAnnotation, typeAnnot.type.trimmedDescription.contains("Environment") else {
					continue
				}
				scanned.append(.env)
				continue
			}
			let typeText = binding.typeAnnotation?.type.trimmedDescription
			let isTable: Bool
			if typeText == "Database" {
				isTable = true
			} else if let typeText, typeText.hasPrefix("Database.") && (typeText.contains("<") && typeText.hasSuffix(">")) {
				isTable = true
			} else {
				isTable = false
			}
			if isTable, let typeText {
				scanned.append(.table(try resolveTable(propertyName:propName, typeText:typeText, attributes:prop.attributes)))
				continue
			}
			// everything else is configuration state and must say so
			guard prop.attributes.contains(where: { ($0.as(AttributeSyntax.self)?.attributeName.trimmedDescription) == "MDB_state" }) else {
				throw MacroError.undeclaredProperty(propName)
			}
			guard prop.bindingSpecifier.text == "let" else {
				throw MacroError.mutableState(propName)
			}
			guard let typeText else {
				throw MacroError.stateNeedsType(propName)
			}
			guard binding.initializer == nil else {
				throw MacroError.defaultedState(propName)
			}
			scanned.append(.state(ResolvedState(property:propName, type:typeText)))
		}
		return scanned
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
		var encryptionArg:String? = nil // nil = no LMDB 1.0 encryption (unencrypted environment)
		var checksumArg:String? = nil   // nil = no per-page checksums
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
					case "encryption": encryptionArg = value
					case "checksum": checksumArg = value
					default: break
				}
			}
		}

		// -- scan stored properties: env + tables (consuming @MDB_table) + @MDB_state
		let scanned = try scanEnvironment(structDecl)
		let tables:[ResolvedTable] = scanned.compactMap { if case .table(let table) = $0 { return table } else { return nil } }
		let states:[ResolvedState] = scanned.compactMap { if case .state(let state) = $0 { return state } else { return nil } }
		guard scanned.contains(where: { if case .env = $0 { return true } else { return false } }) else {
			throw MacroError.missingEnv
		}

		try validateTableNames(tables)

		// -- the file-name mode: `file:` written = a fixed name (spliced as an
		//    expression); `file:` omitted = RUNTIME mode, where the generated
		//    factory takes the name as a required `fileName:` parameter.
		let runtimeFileName = (fileArg == nil)
		let fileExpr = fileArg ?? "fileName"

		// -- the write-at-depth lint (compile-time, same-type write callees)
		lintWriteBoundaryCalls(in: structDecl, context: context)

		// -- build the open(at:) factory
		var lines:[String] = []
		lines.append("/// opens the environment and all of its tables with a single setup write-transaction.")
		lines.append("/// - parameter basePath: the directory that will contain the environment file (created if")
		lines.append("///   it does not already exist).")
		lines.append("/// - parameter mapHeadroom: added to the current file size when sizing the memory map.")
		if runtimeFileName {
			lines.append("/// - parameter fileName: the environment file name, resolved against `basePath` at open")
			lines.append("///   time (this environment declares no fixed `file:`).")
		}
		for state in states {
			lines.append("/// - parameter \(state.property): environment configuration state, carried on the instance (`@MDB_state`).")
		}
		if encryptionArg != nil {
			// the encryption key is runtime data (secrets never ride in source or the
			// attribute); declaring `encryption:` on the environment forces this
			// parameter to be REQUIRED so an encrypted environment cannot be opened
			// without its key.
			lines.append("/// - parameter encryptionKey: the cipher key bytes for the environment's declared")
			lines.append("///   encryption implementation. required because this environment declares `encryption:`.")
		}
		lines.append("@available(*, noasync)")
		var openParams:[String] = ["at basePath: String", "mapHeadroom: UInt64 = 1073741824"]
		if runtimeFileName {
			openParams.append("fileName: String")
		}
		for state in states {
			openParams.append("\(state.property): \(state.type)")
		}
		if encryptionArg != nil {
			openParams.append("encryptionKey: [UInt8]")
		}
		lines.append("public static func open(\(openParams.joined(separator: ", "))) throws -> Self {")
		lines.append("    _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)")
		lines.append("    let slash = basePath.hasSuffix(\"/\") ? \"\" : \"/\"")
		if let versionArg {
			// versioned environment files: the schema version rides in the
			// FILE NAME (`<stem>-v<N>.mdb`) — engaged by writing the version
			// attribute. bump the version to ship a fresh file + stream the
			// old one; the old file stays untouched and readable by older
			// binaries (no sentinel, no in-place migration).
			lines.append("    let targetPath = basePath + slash + (\(fileExpr).hasSuffix(\".mdb\") ? String(\(fileExpr).dropLast(4)) + \"-v\(versionArg)\" + \".mdb\" : \(fileExpr) + \"-v\(versionArg)\")")
		} else {
			lines.append("    let targetPath = basePath + slash + \(fileExpr)")
		}
		lines.append("    let fileSize = QuickLMDB._MDBEnvironmentSupport.__fileSize(at: targetPath)")
		var envInitArgs = "path: targetPath, flags: QuickLMDB.Environment.Flags([.noTLS]).union(\(flagsArg)), mapSize: Int(fileSize + mapHeadroom), maxReaders: \(maxReadersArg), maxDBs: \(maxDBsArg), mode: \(modeArg)"
		if let encryptionArg, let checksumArg {
			envInitArgs += ", encrypt: QuickLMDB.Environment.EncryptionConfiguration(\(encryptionArg), key: encryptionKey), checksum: \(checksumArg)"
		} else if let encryptionArg {
			envInitArgs += ", encrypt: QuickLMDB.Environment.EncryptionConfiguration(\(encryptionArg), key: encryptionKey)"
		} else if let checksumArg {
			envInitArgs += ", checksum: \(checksumArg)"
		}
		lines.append("    let env = try Environment(\(envInitArgs))")
		lines.append("    let setupTX = try Transaction<Write>(env: env)")
		for table in tables {
			let flagsText = table.extraFlags.map { "QuickLMDB.MDB_db_flags([.create]).union(\($0))" } ?? "[.create]"
			let nameLiteral = table.nameIsExpression ? table.name : "\"\(table.name)\""
			lines.append("    let \(table.property) = try \(table.type)(env: env, name: \(nameLiteral), flags: \(flagsText), tx: setupTX)")
		}
		lines.append("    try setupTX.commit()")
		var initArgs:[String] = []
		for prop in scanned {
			switch prop {
				case .env:
					initArgs.append("env: env")
				case .table(let table):
					initArgs.append("\(table.property): \(table.property)")
				case .state(let state):
					initArgs.append("\(state.property): \(state.property)")
			}
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
				findings.append((node, "calling write boundary '\(name)' from inside a write boundary opens a SECOND root write on this environment and deadlocks LMDB's writer mutex — compose with try #MDB_transacted(\(name)(...)) so the callee runs as a child transaction of this boundary"))
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
