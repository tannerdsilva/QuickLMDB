import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

// @MDB_app — container macro for one or more `@MDB_environment` cores.
//
// scans the attached struct's stored properties, treats every stored property
// that is neither the `env` handle nor a `Database.X` table as an environment
// CORE (the same "exactly env + tables" convention @MDB_environment enforces on
// a core's own members), and emits:
//
//   public static let mdb_environment_property_names: [String] = [...]
//
// plus the `MDB_environment_container` conformance. the `@MDB_transact_span`
// body macro uses the SAME scan (via the enclosing type's lexical context) to
// route verb calls to per-core transactions and to diagnose unknown core names;
// this static inventory is the documented surface of that routing table.
internal struct MDB_app_macro:MemberMacro, ExtensionMacro {

	private enum MacroError:Swift.Error, CustomStringConvertible {
		case notAStruct
		case noCores

		var description:String {
			switch self {
				case .notAStruct:
					return "@MDB_app can only be applied to a struct"
				case .noCores:
					return "@MDB_app requires at least one environment core (a stored property that is an @MDB_environment struct)"
			}
		}
	}

	// - MARK: shared core-property scan (also used by @MDB_transact_span)

	/// stored property identities of an environment core: a property whose name
	/// is not `env` and whose type is not a plain `Database` or `Database.X<...>`
	/// table. mirrors the `@MDB_environment` member scan so both macros agree.
	static func corePropertyBindings(in declaration:some DeclGroupSyntax) -> [(name:String, type:String)] {
		var results:[(name:String, type:String)] = []
		for member in declaration.memberBlock.members {
			guard let prop = member.decl.as(VariableDeclSyntax.self) else { continue }
			// skip static machinery, keep stored instance vars
			if prop.modifiers.contains(where: { $0.name.text == "static" }) { continue }
			guard let binding = prop.bindings.first, let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
			guard let typeText = binding.typeAnnotation?.type.trimmedDescription else { continue }
			if name == "env" { continue }
			if typeText == "Database" { continue }
			if typeText.hasPrefix("Database.") && typeText.contains("<") && typeText.hasSuffix(">") { continue }
			results.append((name:name, type:typeText))
		}
		return results
	}

	// - MARK: ExtensionMacro (the conformance)

	static func expansion(of node:SwiftSyntax.AttributeSyntax, attachedTo declaration:some SwiftSyntax.DeclGroupSyntax, providingExtensionsOf type:some SwiftSyntax.TypeSyntaxProtocol, conformingTo protocols:[SwiftSyntax.TypeSyntax], in context:some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.ExtensionDeclSyntax] {
		return [try ExtensionDeclSyntax("""
			extension \(type):MDB_environment_container {}
			""")]
	}

	// - MARK: MemberMacro (the inventory)

	static func expansion(of node:SwiftSyntax.AttributeSyntax, providingMembersOf declaration:some SwiftSyntax.DeclGroupSyntax, conformingTo protocols:[SwiftSyntax.TypeSyntax], in context:some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
		guard let structDecl = declaration.as(StructDeclSyntax.self) else {
			throw MacroError.notAStruct
		}
		let cores = Self.corePropertyBindings(in:structDecl)
		guard cores.isEmpty == false else {
			throw MacroError.noCores
		}
		let names = cores.map { "\"\($0.name)\"" }.joined(separator:", ")
		let access = structDecl.modifiers.filter { $0.name.text == "public" }.isEmpty ? "public" : "public"
		return [DeclSyntax("""
			\(raw: access) static let mdb_environment_property_names:[String] = [\(raw: names)]
			""")]
	}
}
