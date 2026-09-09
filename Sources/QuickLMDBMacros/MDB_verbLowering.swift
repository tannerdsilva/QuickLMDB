import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

// shared marker-gated verb lowering, used by BOTH boundary macros
// (`@MDB_transact` and `@MDB_transact_span`). the only difference between the
// two is the ROUTE: single-env sends every verb to its one injected `tx`;
// a span sends each verb to `tx_<baseName>` by the receiver's base identifier.
//
// the rawdog principle holds for both: only freestanding verb macros in the
// closed set below are touched; every other line is emitted byte-identical.

enum MDB_verbLowering {

	/// the closed set of freestanding verb macros the rewriter lowers.
	static let names:Set<String> = ["store", "load", "delete", "contains", "cursor", "clear"]

	/// maps a verb's receiver BASE identifier to the transaction expression that
	/// should thread it. stateless by contract (the route closures only pattern
	/// match on the base name), so it is `@Sendable`.
	typealias Route = @Sendable (String) -> String

	/// the receiver base identifier of a verb's first (unlabeled) argument:
	/// `calendar.events` → `calendar`, `primary` → `primary`. nil when the
	/// argument is not a member access / direct reference (unroutable shape).
	static func baseName(of firstArg:LabeledExprSyntax) -> String? {
		let expr = firstArg.expression
		if let member = expr.as(MemberAccessExprSyntax.self) {
			// the owner of the LAST member segment: `calendar.events` → `calendar`,
			// `app.calendar.events` → `calendar` (the core property name).
			return deepBaseIdentifier(member)
		}
		if let declRef = expr.as(DeclReferenceExprSyntax.self) {
			return declRef.baseName.text
		}
		return nil
	}

	private static func deepBaseIdentifier(_ member:MemberAccessExprSyntax) -> String? {
		if let base = member.base {
			if let declRef = base.as(DeclReferenceExprSyntax.self) {
				return declRef.baseName.text
			}
			if let baseMember = base.as(MemberAccessExprSyntax.self) {
				// the identifier immediately before the handle segment: for
				// `app.calendar.events` this is `calendar`, not `app`
				return baseMember.declName.baseName.text
			}
		}
		return member.declName.baseName.text
	}

	/// lowers a single verb call to the tx-bearing operation form. `route`
	/// supplies the tx expression for a receiver base identifier. returns nil
	/// when the call shape is unrecognized (the node is left as-is; the
	/// standalone verb expansion diagnoses the misuse).
	static func lower(_ node:MacroExpansionExprSyntax, route:Route) -> ExprSyntax? {
		guard let firstArg = node.arguments.first, firstArg.label == nil else { return nil }
		let receiver = firstArg.expression.trimmedDescription
		let base = baseName(of:firstArg) ?? "tx"          // unroutable shape falls back to the single-env name
		let tx = route(base)
		var labeled:[String:String] = [:]
		for arg in node.arguments.dropFirst() {
			if let label = arg.label?.text {
				labeled[label] = arg.expression.trimmedDescription
			}
		}
		let get = { (label:String) -> String? in labeled[label] }

		switch node.macroName.text {
			case "store":
				guard let key = get("key"), let value = get("value") else { return nil }
				var parts = ["key: \(key)", "value: \(value)"]
				if let flags = get("flags") { parts.append("flags: \(flags)") }
				parts.append("tx: \(tx)")
				return ExprSyntax(stringLiteral:"\(receiver).store(\(parts.joined(separator:", ")))")

			case "load":
				if let asType = get("as") {
					guard let key = get("key") else { return nil }
					return ExprSyntax(stringLiteral:"\(receiver).loadEntry(key: \(key), as: \(asType), tx: \(tx))")
				}
				guard let key = get("key") else { return nil }
				return ExprSyntax(stringLiteral:"\(receiver).load(key: \(key), tx: \(tx))")

			case "delete":
				if let value = get("value") {
					guard let key = get("key") else { return nil }
					return ExprSyntax(stringLiteral:"\(receiver).delete(key: \(key), value: \(value), tx: \(tx))")
				}
				guard let key = get("key") else { return nil }
				return ExprSyntax(stringLiteral:"\(receiver).delete(key: \(key), tx: \(tx))")

			case "contains":
				guard let key = get("key") else { return nil }
				if let value = get("value") {
					// the pair check is CURSOR-only (real MDB_GET_BOTH). a DB-level pair
					// contains would answer true for any existing key (silent no-op).
					return ExprSyntax(stringLiteral:"\(receiver).cursor(tx: \(tx)) { try $0.containsEntry(key: \(key), value: \(value)) }")
				}
				return ExprSyntax(stringLiteral:"\(receiver).contains(key: \(key), tx: \(tx))")

			case "cursor":
				// only the trailing-closure form is supported (the documented contract)
				guard let closure = node.trailingClosure else { return nil }
				return ExprSyntax(stringLiteral:"\(receiver).cursor(tx: \(tx)) \(closure.trimmedDescription)")

			case "clear":
				return ExprSyntax(stringLiteral:"\(receiver).deleteAllEntries(tx: \(tx))")

			default:
				return nil
		}
	}

	/// a `SyntaxRewriter` that lowers every verb call in the visited subtree,
	/// routing through `route`. used by both boundary macros.
	final class Rewriter:SyntaxRewriter {
		let route:Route

		init(route:@escaping Route) {
			self.route = route
		}

		override func visit(_ node:MacroExpansionExprSyntax) -> ExprSyntax {
			// NESTED VERBS CONSUME INNER-FIRST: visit children before folding this node,
			// so an inner verb inside an outer verb's arguments/closures is already
			// lowered before the outer rewrites (an un-lowered inner would hit the
			// standalone diagnostic on the next expansion pass).
			let processed = super.visit(node)
			let expansion = processed.cast(MacroExpansionExprSyntax.self)
			// marker gate: only a freestanding verb in the closed set is touched
			guard MDB_verbLowering.names.contains(expansion.macroName.text) else {
				return ExprSyntax(expansion)
			}
			return MDB_verbLowering.lower(expansion, route:route) ?? ExprSyntax(expansion)
		}
	}
}
