import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// @MDB_table(name:flags:) — per-table configuration on a `Database.X` stored
// property inside an `@MDB_environment` core.
//
// this macro produces NOTHING (returns []): its entire job is to (a) be a
// configuration attribute the `@MDB_environment` scan consumes, and (b) validate
// its own PLACEMENT with friendly diagnostics:
//   1. the target must be a stored property whose type is `Database` or
//      Database.X<...> — "target must be a table property";
//   2. the enclosing type must be an `@MDB_environment` struct (a core) —
//      "tables belong inside an environment core".
//
// semantic checks (name validity/uniqueness, flags-vs-type conflicts) run on
// the CONSUMING side (@MDB_environment), where the whole schema is visible.

internal struct MDB_table_macro: PeerMacro {

    private enum Failure: Swift.Error, CustomStringConvertible {
        case notAProperty
        case notATable(String)

        var description: String {
            switch self {
            case .notAProperty:
                return "@MDB_table must be attached to a stored table property (a `Database` or `Database.X<...>` stored property) — it configures a table's declaration"
            case .notATable(let type):
                return "@MDB_table target has type '\(type)', which is not a table — expected `Database` or `Database.X<...>`"
            }
        }
    }

    private static func isTableType(_ typeText: String) -> Bool {
        if typeText == "Database" { return true }
        return typeText.hasPrefix("Database.") && typeText.contains("<") && typeText.hasSuffix(">")
    }

    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // 1 — the target must be a stored property of a table type
        guard let prop = declaration.as(VariableDeclSyntax.self),
              let binding = prop.bindings.first,
              binding.pattern.is(IdentifierPatternSyntax.self),
              let typeText = binding.typeAnnotation?.type.trimmedDescription else {
            throw Failure.notAProperty
        }
        guard isTableType(typeText) else {
            throw Failure.notATable(typeText)
        }

        // 2 — the enclosing type must be an @MDB_environment core
        var isInsideCore = false
        for lexical in context.lexicalContext {
            if let structDecl = lexical.as(StructDeclSyntax.self),
               structDecl.attributes.contains(where: { attr in
                   (attr.as(AttributeSyntax.self)?.attributeName.trimmedDescription) == "MDB_environment"
               }) {
                isInsideCore = true
                break
            }
        }
        guard isInsideCore else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: TableDiagnostic(
                    id: "tableOutsideCore",
                    text: "@MDB_table can only be used inside an @MDB_environment core — tables belong to a core's schema"
                )
            ))
            return []
        }

        // a configuration attribute: nothing to generate
        return []
    }
}

private struct TableDiagnostic: DiagnosticMessage {
    let id: String
    let text: String
    var message: String { text }
    var diagnosticID: MessageID { MessageID(domain: "QuickLMDB", id: id) }
    var severity: DiagnosticSeverity { .error }
}
