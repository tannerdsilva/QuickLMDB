import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// @MDB_state — configuration state on an `@MDB_environment` type: a stored
// property that is neither the environment handle nor a table.
//
// this macro produces NOTHING (returns []): its entire job is to (a) be the
// marker the `@MDB_environment` scan recognises as declarative intent, and
// (b) validate its own PLACEMENT with friendly diagnostics:
//   1. the target must be a stored property with an explicit type annotation
//      (the generated factory takes it as a parameter and cannot spell an
//      inferred type);
//   2. it must be immutable (`let`) — an environment core is a handle;
//   3. it must NOT carry an initializer. Swift's implicit memberwise
//      initializer OMITS `let` properties that already hold a value
//      (probe-verified: `extra argument 'b' in call`), so a defaulted state
//      property could never be set at open. author the default at the call
//      site instead — the established `static func openFor…` alias pattern;
//   4. the enclosing type must be an `@MDB_environment` struct.
//
// the CONSUMING side (`@MDB_environment`) turns each marked property into one
// REQUIRED `open` parameter, in declaration order, and threads it into the
// generated instance.

internal struct MDB_state_macro:PeerMacro {

	private enum Failure:Swift.Error, CustomStringConvertible {
		case notAProperty

		var description:String {
			switch self {
				case .notAProperty:
					return "@MDB_state must be attached to a stored property — it declares configuration the generated `open` takes as a parameter"
			}
		}
	}

	static func expansion(
		of node: AttributeSyntax,
		providingPeersOf declaration: some DeclSyntaxProtocol,
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		// 1 — the target must be a stored property
		guard let prop = declaration.as(VariableDeclSyntax.self),
			  let binding = prop.bindings.first,
			  binding.pattern.is(IdentifierPatternSyntax.self) else {
			throw Failure.notAProperty
		}
		// 2 — the enclosing type must be an @MDB_environment type. the SEMANTIC
		//     rules (immutable, explicitly typed, never pre-initialized) run on the
		//     consuming side (@MDB_environment), where the whole schema is visible —
		//     the same split @MDB_table uses.

		var isInsideEnvironment = false
		for lexical in context.lexicalContext {
			if let structDecl = lexical.as(StructDeclSyntax.self),
			   structDecl.attributes.contains(where: { attr in
				   (attr.as(AttributeSyntax.self)?.attributeName.trimmedDescription) == "MDB_environment"
			   }) {
				isInsideEnvironment = true
				break
			}
		}
		guard isInsideEnvironment else {
			context.diagnose(Diagnostic(
				node: Syntax(node),
				message: StateDiagnostic(
					id: "stateOutsideEnvironment",
					text: "@MDB_state can only be used inside an @MDB_environment — configuration state belongs to the environment it configures"
				)
			))
			return []
		}

		// a marker attribute: nothing to generate
		return []
	}
}

private struct StateDiagnostic:DiagnosticMessage {
	let id:String
	let text:String
	var message:String { text }
	var diagnosticID:MessageID { MessageID(domain:"QuickLMDB", id:id) }
	var severity:DiagnosticSeverity { .error }
}