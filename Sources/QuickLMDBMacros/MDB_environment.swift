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
// the generated factory forces `.noTLS` onto the environment REGARDLESS of the declared
// flags. this is intentional and load-bearing: `.noTLS` binds each read transaction's
// reader slot to the transaction object instead of the thread, which is what makes
// Swift's task-based concurrency — where a task may migrate between threads — safe, and
// what permits multiple live read transactions on a thread (sibling reads) at all.
//
// this macro is purely schema assembly — it contains no transaction logic.
// transaction boundaries are owned by `@MDB_transact` (attached body + peer)
// on the methods of a container holding one or more of these cores. the C
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

	// marks every @MDB_environment struct as an environment core — the type
	// `@MDB_transact(_:environments:)` accepts in its environments variadic
	static func expansion(of node: SwiftSyntax.AttributeSyntax, attachedTo declaration: some SwiftSyntax.DeclGroupSyntax, providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol, conformingTo protocols: [SwiftSyntax.TypeSyntax], in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.ExtensionDeclSyntax] {
		return [try ExtensionDeclSyntax("""
			extension \(type):MDB_environment {}
			""")]
	}

	private enum MacroError:Swift.Error, CustomStringConvertible {
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

	private struct ResolvedTable {
		let property:String              // the stored property name (local + Self init label)
		var name:String                  // the resolved LMDB table name (property name unless overridden)
		var nameIsExpression:Bool        // true when `name:` was a referenced expression (evaluated at runtime, not spliced as a literal)
		let type:String
		var extraFlags:String?    // the `flags:` array expression as written, or nil
		var flagCases:Set<String> // member-case names for conflict validation
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
		guard let fileArg, fileArg.isEmpty == false else {
			throw MacroError.missingFileArg
		}

		// -- scan stored properties: env + tables (consuming @MDB_table)
		var hasEnv = false
		var tables:[ResolvedTable] = []
		for member in structDecl.memberBlock.members {
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
		guard hasEnv else {
			throw MacroError.missingEnv
		}

		// -- validated schema invariants (the "no missed opportunities" surface)
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

	// -- @MDB_table consumption

	/// the table's effective schema: derived defaults when no attribute present
	/// (name = property name, no extra flags); the explicit `name:`/`flags:`
	/// overrides plus their validation otherwise.
	private static func resolveTable(propertyName:String, typeText:String, attributes:AttributeListSyntax) throws -> ResolvedTable {
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
