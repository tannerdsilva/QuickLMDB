import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

/// shared fallback implementation for the verb vocabulary (`#store`/`#load`/
/// `#delete`/`#contains`/`#cursor`/`#clear`).
///
/// a verb is only meaningful INSIDE a transaction boundary: the boundary macro
/// (`MDB_transact`) consumes the verb calls in its body and lowers them to the
/// tx-bearing operation call before these standalone expansions run. this
/// implementation is therefore only ever reached for a verb written OUTSIDE a
/// boundary — the intended misuse — where it emits a compile-time diagnostic.
///
/// the verb name is read from the node itself, so one implementation serves
/// all six declarations.
internal struct MDB_verb_error_macro:ExpressionMacro {

	static func expansion(of node:some FreestandingMacroExpansionSyntax, in context:some MacroExpansionContext) throws -> ExprSyntax {
		let verbName = node.macroName.text
		context.diagnose(Diagnostic(node:Syntax(node), message:MDB_verb_error_diagnostic(verbName:verbName)))
		// the diagnostic is the payload; the placeholder expression is never
		// reached in a compiling program (the diagnostic fails the build).
		return "nil"
	}
}

private struct MDB_verb_error_diagnostic:DiagnosticMessage {
	let verbName:String

	var message:String {
		"\(verbName) must only appear inside an @MDB_transact body"
	}
	var diagnosticID:MessageID {
		MessageID(domain:"QuickLMDB", id:"verbOutsideBoundary")
	}
	var severity:DiagnosticSeverity {
		.error
	}
}
