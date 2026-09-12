import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// @MDB_layout — the multi-environment ARRANGEMENT helper.
//
// with the typed-environment architecture, every environment is its own type
// and boundaries live ON those types; a layout is purely an arrangement: a
// struct holding N `@MDB_environment` cores that wants a single open + an
// inventory. it generates:
//
//   static func open(at basePath: String, mapHeadroom: UInt64) throws -> Self
//       opens every core at `<basePath>/<propertyName>` (path-stemming) and
//       assembles a fresh instance — the container-level initialization story
//       for multi-environment apps.
//
//   static let mdb_core_names: [String]
//       the core inventory, declaration order (docs/tooling).
//
// no per-core factories, no static singletons, no basePath argument — the
// cores open through each type's own generated `open(at:)`. members are
// fixed-name only, so there is no arbitrary-name registration.
//
// validation: struct only; at least one stored instance property (the cores).

internal struct MDB_layout_macro: MemberMacro {

	private enum Failure: Swift.Error, CustomStringConvertible {
		case notAStruct
		case noProperties

		var description: String {
			switch self {
			case .notAStruct:
				return "@MDB_layout can only be applied to a struct"
			case .noProperties:
				return "@MDB_layout requires at least one stored property — the environment cores the arrangement owns"
			}
		}
	}

	private struct CoreSpec {
		let name: String
		let type: String
		let access: String
	}

	static func expansion(
		of node: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		guard let structDecl = declaration.as(StructDeclSyntax.self) else {
			throw Failure.notAStruct
		}

		// scan stored instance properties (the cores)
		var cores: [CoreSpec] = []
		for member in structDecl.memberBlock.members {
			guard let prop = member.decl.as(VariableDeclSyntax.self) else { continue }
			if prop.modifiers.contains(where: { $0.name.text == "static" }) { continue }
			guard let binding = prop.bindings.first,
				  let propName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
				  let typeAnnot = binding.typeAnnotation else { continue }
			if binding.accessorBlock != nil { continue }
			let access = prop.modifiers.first(where: { ["public", "internal", "fileprivate", "private"].contains($0.name.text) })?.name.text ?? ""
			cores.append(CoreSpec(name: propName, type: typeAnnot.type.trimmedDescription, access: access))
		}
		guard !cores.isEmpty else { throw Failure.noProperties }
		let accessPrefix = cores.allSatisfy { $0.access == cores[0].access } ? cores[0].access : ""
		let mods = accessPrefix.isEmpty ? "" : accessPrefix + " "

		var lines: [String] = []
		// -- the core inventory (declaration order)
		let names = cores.map { "\"\($0.name)\"" }.joined(separator: ", ")
		lines.append("\(mods)static let mdb_core_names: [String] = [\(names)]")
		// -- the arrangement open
		var openLines: [String] = []
		openLines.append("@available(*, noasync)")
		openLines.append("\(mods)static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {")
		for core in cores {
			openLines.append("    let \(core.name) = try \(core.type).open(at: basePath + \"/\" + \"\(core.name)\", mapHeadroom: mapHeadroom)")
		}
		let initArgs = cores.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
		openLines.append("    return Self(\(initArgs))")
		openLines.append("}")
		lines.append(openLines.joined(separator: "\n"))

		return lines.map { DeclSyntax(stringLiteral: $0) }
	}
}
