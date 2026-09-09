import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

// @MDB_transact(.readWrite) / @MDB_transact(.readOnly) / @MDB_transact(.readWriteChild)
//
// attached BODY macro: rewrites the annotated method's body in place so the method itself
// is a transaction boundary, with no ambient storage of any kind (no task-local, no
// thread-local, no registry). the expansion:
//
//   1. injects a local `let tx = try Transaction(env: self.env, ...)` owning the scope,
//   2. wraps the original body in a nested local function `__mdb_body(_ tx: borrowing
//      Transaction)` so the transaction is passed by explicit borrow (never captured),
//   3. lowers freestanding VERB calls (#store / #load / #delete / #contains / #cursor /
//      #clear) to the tx-bearing operation form. every other line is emitted
//      byte-identical — marker-gated attribution (a user function named `setEntry`
//      is unreachable-by-rewrite by construction),
//   4. commits once on success, aborts exactly once on any thrown error, and returns the
//      body's captured result.
//
// wrapping in a nested function means function-level `return`s inside the original body
// return from the nested function unmodified — no return-rewriting is needed, and returns
// inside inner closures (e.g. cursor handlers) are untouched by construction.
//
// contract:
//   - the method must be marked `throws` (the boundary can fail to open or commit).
//   - async methods are rejected (a transaction must never cross an await).
//   - the enclosing type must have a stored `env` property of type `Environment`.
//   - `.readWriteChild` requires a `parent: borrowing Transaction` parameter, which the
//     expansion uses as the child's parent.
//   - the name `tx` exists for ONE composition purpose: passing as `parent:` to a
//     `.readWriteChild` boundary. reusable write logic is a `.readWriteChild`
//     boundary (its mode lives in its own attribute); reusable read logic is a
//     `.readOnly` boundary. there is deliberately no plain-helper-with-`tx:`
//     pattern: a helper that does DB work declares its mode as a boundary, not
//     via a transaction parameter the caller must already know.
//
// the underlying C wrapper layer is untouched: the expansion only adds ownership of an
// `Environment` transaction and forwards calls through the existing public protocol API.

internal struct MDB_transact_macro: BodyMacro {

	private enum MacroError:Swift.Error, CustomStringConvertible {
		case notAFunction
		case missingMode
		case invalidMode(String)
		case asyncNotSupported
		case mustBeThrowing
		case typedThrowsUnsupported
		case txNameCollision
		case childNeedsParent
		case neverReturnUnsupported

		var description:String {
			switch self {
				case .notAFunction:
					return "@MDB_transact can only be applied to a function"
				case .missingMode:
					return "@MDB_transact requires a mode argument (e.g. @MDB_transact(.readWrite))"
				case .invalidMode(let mode):
					return "unknown @MDB_transact mode '\(mode)'. expected .readWrite, .readOnly, or .readWriteChild"
				case .asyncNotSupported:
					return "@MDB_transact does not support async methods - a transaction must not cross an await"
				case .mustBeThrowing:
					return "@MDB_transact requires the method to be marked `throws` - the boundary can fail to open, commit, or abort"
				case .typedThrowsUnsupported:
					return "@MDB_transact requires an untyped `throws` - the boundary rethrows the body's error, so a typed throws clause cannot be represented"
				case .txNameCollision:
					return "@MDB_transact injects the name `tx` into the method body for the boundary transaction - the method must not declare a parameter named `tx`"
				case .childNeedsParent:
					return "@MDB_transact(.readWriteChild) requires a `parent: borrowing Transaction` parameter on the method"
				case .neverReturnUnsupported:
					return "@MDB_transact does not support `-> Never` return types"
			}
		}
	}

	/// the single-env route: every verb threads the boundary's one injected `tx`.
	/// (the span boundary uses a per-core route instead — see MDB_transact_span.)
	private static let singleEnvRoute: MDB_verbLowering.Route = { _ in "tx" }

	// - MARK: mode parsing

	private enum Mode {
		case readWrite
		case readOnly
		case readWriteChild
	}

	private static func parseMode(from node:AttributeSyntax) throws -> Mode {
		guard let argList = node.arguments?.as(LabeledExprListSyntax.self), let firstExpr = argList.first?.expression else {
			throw MacroError.missingMode
		}
		guard let member = firstExpr.as(MemberAccessExprSyntax.self) else {
			throw MacroError.missingMode
		}
		switch member.declName.baseName.text {
			case "readWrite": return .readWrite
			case "readOnly": return .readOnly
			case "readWriteChild": return .readWriteChild
			default: throw MacroError.invalidMode(member.declName.baseName.text)
		}
	}

	// - MARK: body macro entry point

	static func expansion(of node:AttributeSyntax, providingBodyFor declaration:some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax, in context:some MacroExpansionContext) throws -> [CodeBlockItemSyntax] {
		let mode = try parseMode(from:node)

		guard let fn = declaration.as(FunctionDeclSyntax.self) else {
			throw MacroError.notAFunction
		}
		if fn.signature.effectSpecifiers?.asyncSpecifier != nil {
			throw MacroError.asyncNotSupported
		}
		guard fn.signature.effectSpecifiers?.throwsClause != nil else {
			throw MacroError.mustBeThrowing
		}
		if let throwsClause = fn.signature.effectSpecifiers?.throwsClause, throwsClause.type != nil {
			throw MacroError.typedThrowsUnsupported
		}

		let params = fn.signature.parameterClause.parameters
		if params.contains(where: { $0.firstName.text == "tx" || $0.secondName?.text == "tx" }) {
			throw MacroError.txNameCollision
		}
		if mode == .readWriteChild {
			guard params.contains(where: { $0.firstName.text == "parent" || $0.secondName?.text == "parent" }) else {
				throw MacroError.childNeedsParent
			}
		}
		let retClause = fn.signature.returnClause
		if let retClause, retClause.type.trimmedDescription == "Never" {
			throw MacroError.neverReturnUnsupported
		}
		let retTypeText:String? = fn.signature.returnClause?.type.trimmedDescription
		let hasReturnValue = retTypeText != nil

		// -- nested function: same parameters as the method + the borrowed boundary transaction
		//    (param descriptions include their trailing separator comma — strip it before joining)
		var nestedParams:[String] = params.map { p in
			let s = p.trimmedDescription
			return s.hasSuffix(",") ? String(s.dropLast()) : s
		}
		nestedParams.append("_ tx: borrowing Transaction")
		let nestedParamClause = "(\(nestedParams.joined(separator:", ")))"
		var throwsAndReturns = " throws"
		if let fnReturnClause = fn.signature.returnClause {
			throwsAndReturns += " " + fnReturnClause.trimmedDescription
		}

		// -- call arguments for __mdb_body(...)
		var callArgs:[String] = []
		for param in params {
			if param.firstName.text == "_" {
				callArgs.append(param.secondName?.text ?? "")
			} else if let second = param.secondName {
				callArgs.append("\(param.firstName.text): \(second.text)")
			} else {
				callArgs.append("\(param.firstName.text): \(param.firstName.text)")
			}
		}
		var bodyCallArgs = callArgs
		bodyCallArgs.append("tx")
		let bodyCall = "__mdb_body(\(bodyCallArgs.joined(separator:", ")))"

		// -- transform the original body: lower verb calls to tx-bearing form
		let rewriter = MDB_verbLowering.Rewriter(route:singleEnvRoute)
		let originalStatements = fn.body?.statements ?? CodeBlockItemListSyntax([])
		let transformedItems = rewriter.visit(originalStatements)
		let bodyText = transformedItems.map { $0.trimmedDescription }.joined(separator:"\n")

		// -- transaction opening line per mode
		let openLine:String
		switch mode {
			case .readWrite:
				openLine = "let tx = try Transaction(env: self.env, readOnly: false)"
			case .readOnly:
				openLine = "let tx = try Transaction(env: self.env, readOnly: true)"
			case .readWriteChild:
				openLine = "let tx = try Transaction(env: self.env, readOnly: false, parent: parent)"
		}

		// -- nested function declaration, body injected as parsed text
		let nestedFuncText = "func __mdb_body\(nestedParamClause)\(throwsAndReturns) {\n\(bodyText)\n}"

		var items:[CodeBlockItemSyntax] = []
		items.append(CodeBlockItemSyntax(stringLiteral: openLine))
		items.append(CodeBlockItemSyntax(stringLiteral: nestedFuncText))
		if let retTypeText {
			items.append(CodeBlockItemSyntax(stringLiteral: "let __mdb_output: \(retTypeText)"))
		}
		// the do/catch boundary is a SINGLE statement item (control flow must not be
		// assembled from separate top-level code block items)
		var doCatchLines:[String] = []
		doCatchLines.append("do {")
		if hasReturnValue {
			doCatchLines.append("    __mdb_output = try \(bodyCall)")
		} else {
			doCatchLines.append("    try \(bodyCall)")
		}
		doCatchLines.append("} catch let error {")
		doCatchLines.append("    tx.abort()")
		doCatchLines.append("    throw error")
		doCatchLines.append("}")
		items.append(CodeBlockItemSyntax(stringLiteral: doCatchLines.joined(separator:"\n")))
		switch mode {
			case .readOnly:
				items.append(CodeBlockItemSyntax(stringLiteral: "tx.abort()"))
			default:
				items.append(CodeBlockItemSyntax(stringLiteral: "try tx.commit()"))
		}
		if hasReturnValue {
			items.append(CodeBlockItemSyntax(stringLiteral: "return __mdb_output"))
		}
		return items
	}
}
