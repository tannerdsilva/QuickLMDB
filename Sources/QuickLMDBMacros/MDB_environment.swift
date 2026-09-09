import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

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
// this macro is purely schema assembly — it contains no transaction logic. transaction
// boundaries are owned by `@MDB_transact` (an attached body macro) on the methods of the
// struct. the C wrapper layer is untouched; the generated code uses the existing public
// `Environment`, `Transaction`, and `Database.*` API (plus the underscored file-size
// probe in `QuickLMDB._MDBEnvironmentSupport`).
//
// contract: the struct's stored properties must be exactly `env` plus `Database.X` tables.
// plain `Database` (raw MDB_val) tables are supported.

internal struct MDB_environment_macro:MemberMacro, ExtensionMacro {

	// marks every @MDB_environment struct as an environment core for @MDB_app containers
	static func expansion(of node: SwiftSyntax.AttributeSyntax, attachedTo declaration: some SwiftSyntax.DeclGroupSyntax, providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol, conformingTo protocols: [SwiftSyntax.TypeSyntax], in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.ExtensionDeclSyntax] {
		return [try ExtensionDeclSyntax("""
			extension \(type):MDB_environment {}
			""")]
	}

	private enum MacroError:Swift.Error, CustomStringConvertible {
		case notAStruct
		case missingEnv
		case missingFileArg

		var description:String {
			switch self {
				case .notAStruct:
					return "@MDB_environment can only be applied to a struct"
				case .missingEnv:
					return "@MDB_environment requires the struct to have a stored property named `env` of type `Environment`"
				case .missingFileArg:
					return "@MDB_environment requires a `file:` argument naming the environment file (e.g. @MDB_environment(file: \"store.mdb\"))"
			}
		}
	}

	private struct ParsedTable {
		var name:String
		let type:String
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
		if let argList = node.arguments?.as(LabeledExprListSyntax.self) {
			for arg in argList {
				guard let label = arg.label?.text else {
					continue
				}
				let value = arg.expression.trimmedDescription
				switch label {
					case "file": fileArg = value
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

		// -- scan stored properties: env + tables
		var hasEnv = false
		var tables:[ParsedTable] = []
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
				tables.append(ParsedTable(name:propName, type:typeText))
			}
		}
		guard hasEnv else {
			throw MacroError.missingEnv
		}

		// -- build the open(at:) factory
		var lines:[String] = []
		lines.append("/// opens the environment and all of its tables with a single setup write-transaction.")
		lines.append("/// - parameter basePath: an existing directory that will contain the environment file.")
		lines.append("/// - parameter mapHeadroom: added to the current file size when sizing the memory map.")
		lines.append("@available(*, noasync)")
		lines.append("public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {")
		lines.append("    let slash = basePath.hasSuffix(\"/\") ? \"\" : \"/\"")
		lines.append("    let targetPath = basePath + slash + \(fileArg)")
		lines.append("    let fileSize = QuickLMDB._MDBEnvironmentSupport.__fileSize(at: targetPath)")
		lines.append("    let env = try Environment(path: targetPath, flags: QuickLMDB.Environment.Flags([.noTLS]).union(\(flagsArg)), mapSize: Int(fileSize + mapHeadroom), maxReaders: \(maxReadersArg), maxDBs: \(maxDBsArg), mode: \(modeArg))")
		lines.append("    let setupTX = try Transaction(env: env, readOnly: false)")
		for table in tables {
			lines.append("    let \(table.name) = try \(table.type)(env: env, name: \"\(table.name)\", flags: [.create], tx: setupTX)")
		}
		lines.append("    try setupTX.commit()")
		var initArgs:[String] = ["env: env"]
		for table in tables {
			initArgs.append("\(table.name): \(table.name)")
		}
		lines.append("    return Self(\(initArgs.joined(separator:", ")))")
		lines.append("}")

		return lines.map { DeclSyntax(stringLiteral: $0) }
	}
}
