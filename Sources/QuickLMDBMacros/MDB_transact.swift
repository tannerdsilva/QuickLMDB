import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// the boundary dialect (typed-environment architecture) on the real engine
// (capability-typed `Transaction<M>`, @MDB_environment cores).
//
// @MDB_transact(_ mode:) — attached BODY + PEER on INSTANCE methods.
//   every environment is its own TYPE (an @MDB_environment core). a boundary
//   lives on a core type (the environment is `self`) and may additionally take
//   other cores as typed parameters. the body is written with the TYPED VERB
//   FAMILY — `#store(E.self, database: \.events, key:..., value:...)` — where
//   E is the environment TYPE the operation targets and the database is a
//   KeyPath from that type to a `Database.X` handle. the tx plumbing is
//   entirely invisible: the authored signature has NO transaction parameters.
//
//   BODY — emits the SHELL at the authored name: opens
//   `tx_<E> = try Transaction<Mode>(env: <instance>.env)` per environment the
//   body touches (inferred from the verb's E argument; instance = self or a
//   typed parameter), calls the peer SIBLING with those transactions, and
//   closes every one: `.readOnly` aborts on throw AND on success (a read leaf
//   never commits); `.readWrite` aborts on throw and COMMITS on success.
//
//   PEER — emits the network SIBLING (same name + `tx_<E>: borrowing
//   Transaction<…>` per inferred environment): read-only siblings are generic
//   over the mode (`Transaction<M>`, so write boundaries can join reads);
//   read-write siblings require `Transaction<Write>`. its body is the authored
//   body with every verb lowered to the tx-bearing call and every
//   `#MDB_transacted(...)` join marker rewritten to pass THIS boundary's
//   transactions (one transaction across the composed call — atomic for
//   writes; joined reads see this boundary's own uncommitted state).
//
//   a bare call inside another boundary resolves to the SHELL — a fresh root
//   transaction (the deliberate sibling-read pattern for reads; a documented
//   footgun for accidental write composition). joining is spelled
//   `#MDB_transacted(callee(args))`.
//
// ownership shape is the proven v16 formulation: transactions flow into the
// sibling as `borrowing` parameters; the shell owns the lifecycle.

internal struct MDB_transact_macro: BodyMacro, PeerMacro {

	// - MARK: attribute parsing

	private enum Failure: Swift.Error, CustomStringConvertible {
		case notAFunction
		case noMode
		case childNotDesigned(String)
		case unknownMode(String)
		case mustBeThrowing
		case typedThrowsUnsupported
		case asyncNotSupported
		case mustBeInstance
		case noVerbs
		case missingEnvironmentInstance(String)
		case ambiguousEnvironment(String)

		var description: String {
			switch self {
			case .notAFunction:
				return "@MDB_transact can only be applied to a function"
			case .noMode:
				return "@MDB_transact requires a mode argument"
			case .childNotDesigned(let mode):
				return "@MDB_transact cannot accept '\(mode)': relationship (child) composition is designed separately — Design-B #MDB_transacted joining already composes calls into one transaction"
			case .unknownMode(let mode):
				return "@MDB_transact: unknown mode '\(mode)' — expected .readOnly or .readWrite"
			case .mustBeThrowing:
				return "@MDB_transact requires the method to be marked `throws` — the boundary can fail to open, commit, or abort"
			case .typedThrowsUnsupported:
				return "@MDB_transact requires an untyped `throws` — the boundary rethrows the body's error, so a typed throws clause cannot be represented"
			case .asyncNotSupported:
				return "@MDB_transact does not support async methods — a transaction must not cross an await"
			case .mustBeInstance:
				return "@MDB_transact methods must be INSTANCE methods — the environments are `self` and typed parameters of the same type"
			case .noVerbs:
				return "@MDB_transact body has no database verbs (#store/#load/#delete/#contains/#cursor/#clear/#stats/#drop) — the boundary's environments are inferred from the verbs. a boundary cannot be a pure coordinator — it owns the environments it operates on"
			case .missingEnvironmentInstance(let env):
				return "@MDB_transact: no instance of environment type '\(env)' is in scope — attach the boundary to '\(env)' itself, or add a parameter of type '\(env)'. a boundary owns the environments it OPERATES on — it cannot be a pure coordinator"
			case .ambiguousEnvironment(let env):
				return "@MDB_transact: more than one instance of environment type '\(env)' is in scope (self + a parameter, or two parameters) — the typed verbs can only address ONE instance per environment type; split the boundary or use the raw `Transaction` surface for the second"
			}
		}
	}

	private struct ParsedMode {
		let isReadWrite: Bool
		var modeExpr: String { isReadWrite ? "Write" : "Read" }
	}

	private static func parse(_ node: AttributeSyntax) throws -> ParsedMode {
		guard let argList = node.arguments?.as(LabeledExprListSyntax.self), let first = argList.first else {
			throw Failure.noMode
		}
		let modeText = first.expression.trimmedDescription
		switch modeText {
		case ".readOnly", "MDB_transact_mode.readOnly":
			return ParsedMode(isReadWrite: false)
		case ".readWrite", "MDB_transact_mode.readWrite":
			return ParsedMode(isReadWrite: true)
		case ".readWriteChild", "MDB_transact_mode.readWriteChild":
			throw Failure.childNotDesigned(modeText)
		default:
			throw Failure.unknownMode(modeText)
		}
	}

	/// the value-typed verb vocabulary (freestanding, commandeered by this
	/// macro inside boundary bodies). each verb's SIMPLIFIED expansion is
	/// `db.<op>(<args>, tx: tx_<E>)`; the keypath resolves the handle at
	/// runtime so the table stays compiler-typed.
	private static let verbNames: [String] = ["store", "load", "delete", "contains", "cursor", "clear", "stats", "drop"]

	// - MARK: body verbs — the environment type arg

	/// `CalendarCore.self` or `E.self` (member access whose declName is `self`)
	private static func environmentTypeName(of verb: MacroExpansionExprSyntax) -> String? {
		guard let first = verb.arguments.first?.expression else { return nil }
		// `CalendarCore.self`
		if let member = first.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "self" {
			if let base = member.base?.as(DeclReferenceExprSyntax.self) {
				return base.baseName.text
			}
			return nil
		}
		// a bare type reference (`CalendarCore`)
		if let ref = first.as(DeclReferenceExprSyntax.self) {
			return ref.baseName.text
		}
		return nil
	}

	private static func verbDatabaseKeyPathText(_ verb: MacroExpansionExprSyntax) -> String? {
		verb.arguments.first { $0.label?.text == "database" }?.expression.trimmedDescription
	}

	// - MARK: environment instance resolution

	/// the instance expression + tx label for an environment type name.
	/// `self` when the boundary is attached to the environment type itself,
	/// otherwise the first parameter declared with that type.
	private static func resolveInstance(
		envName: String,
		enclosingType: String?,
		params: FunctionParameterClauseSyntax?
	) -> (expr: String, label: String)? {
		let label = "tx_" + envName
		if envName == enclosingType {
			return ("self", label)
		}
		if let params {
			for p in params.parameters {
				let typeText = p.type.trimmedDescription
				if typeText == envName || typeText.hasSuffix("." + envName) {
					let expr = p.secondName?.text ?? p.firstName.text
					return (expr, label)
				}
			}
		}
		return nil
	}

	/// how many instances of an environment type are in scope (self and/or
	/// typed parameters). more than one cannot be addressed by the verbs.
	private static func instanceSourceCount(envName: String, enclosingType: String?, params: FunctionParameterClauseSyntax?) -> Int {
		var count = 0
		if envName == enclosingType { count += 1 }
		if let params {
			for p in params.parameters {
				let t = p.type.trimmedDescription
				if t == envName || t.hasSuffix("." + envName) { count += 1 }
			}
		}
		return count
	}

	/// the name of the environment type a boundary is attached to: the
	/// enclosing struct, or the EXTENDED type when declared in an extension of
	/// a core (the README flagship pattern). a module qualifier is stripped so
	/// `Module.Core.self` and `Core.self` unify.
	private static func enclosingTypeName(from context: some MacroExpansionContext) -> String? {
		for decl in context.lexicalContext {
			if let s = decl.as(StructDeclSyntax.self) {
				return s.name.text
			}
			if let e = decl.as(ExtensionDeclSyntax.self) {
				let text = e.extendedType.trimmedDescription
				if let dot = text.lastIndex(of: ".") {
					return String(text[text.index(after: dot)...])
				}
				return text
			}
		}
		return nil
	}

	// - MARK: shared validation

	private static func validateMethod(_ declaration: some DeclSyntaxProtocol, node: AttributeSyntax) throws -> (fn: FunctionDeclSyntax, mode: ParsedMode) {
		guard let fn = declaration.as(FunctionDeclSyntax.self) else { throw Failure.notAFunction }
		let mode = try parse(node)
		if fn.modifiers.contains(where: { $0.name.text == "static" }) {
			throw Failure.mustBeInstance
		}
		if fn.signature.effectSpecifiers?.asyncSpecifier != nil {
			throw Failure.asyncNotSupported
		}
		guard fn.signature.effectSpecifiers?.throwsClause != nil else {
			throw Failure.mustBeThrowing
		}
		if let throwsClause = fn.signature.effectSpecifiers?.throwsClause, throwsClause.type != nil {
			throw Failure.typedThrowsUnsupported
		}
		return (fn, mode)
	}

	/// the environment types the body touches, in first-appearance order —
	/// from each verb's E argument.
	private static func inferredEnvironments(of statements: CodeBlockItemListSyntax) -> [String] {
		var seen: [String] = []
		var seenSet = Set<String>()
		let visitor = VerbEnvironmentCollector(found: {
			env in
			if !seenSet.contains(env) {
				seenSet.insert(env)
				seen.append(env)
			}
		})
		visitor.walk(statements)
		return seen
	}

	private final class VerbEnvironmentCollector: SyntaxVisitor {
		let found: (String) -> Void
		init(found: @escaping (String) -> Void) {
			self.found = found
			super.init(viewMode: .sourceAccurate)
		}
		override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
			if MDB_transact_macro.verbNames.contains(node.macroName.text),
			   let env = MDB_transact_macro.environmentTypeName(of: node) {
				found(env)
			}
			// keep descending: verbs can be nested inside other expressions
			return .visitChildren
		}
	}

	// - MARK: BodyMacro — the shell

	static func expansion(
		of node: AttributeSyntax,
		providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
		in context: some MacroExpansionContext
	) throws -> [CodeBlockItemSyntax] {
		let (fn, mode) = try validateMethod(declaration, node: node)
		let body = fn.body?.statements ?? CodeBlockItemListSyntax([])

		let envNames = inferredEnvironments(of: body)
		guard !envNames.isEmpty else { throw Failure.noVerbs }

		let enclosingType = MDB_transact_macro.enclosingTypeName(from: context)
		var resolutions: [(name: String, expr: String, label: String)] = []
		for envName in envNames {
			if MDB_transact_macro.instanceSourceCount(envName: envName, enclosingType: enclosingType, params: fn.signature.parameterClause) > 1 {
				throw Failure.ambiguousEnvironment(envName)
			}
			guard let resolved = resolveInstance(envName: envName, enclosingType: enclosingType, params: fn.signature.parameterClause) else {
				throw Failure.missingEnvironmentInstance(envName)
			}
			resolutions.append((name: envName, expr: resolved.expr, label: resolved.label))
		}

		let params = fn.signature.parameterClause.parameters
		let name = fn.name.text
		let isThrowing = fn.signature.effectSpecifiers?.throwsClause != nil
		let retText = fn.signature.returnClause?.type.trimmedDescription

		// the shell's call into the sibling: the author's arguments by their
		// original labels, then one `tx_<E>: tx_<E>` per inferred environment.
		// INOUT parameters must be re-prefixed with `&` — the sibling takes
		// them by reference and the caller owns the storage.
		var callArgs: [String] = []
		for p in params {
			let isInout = p.type.trimmedDescription.hasPrefix("inout ")
			let ampersand = isInout ? "&" : ""
			if p.firstName.text == "_" {
				callArgs.append("\(ampersand)\(p.secondName?.text ?? "")")
			} else if let second = p.secondName {
				callArgs.append("\(p.firstName.text): \(ampersand)\(second.text)")
			} else {
				callArgs.append("\(p.firstName.text): \(ampersand)\(p.firstName.text)")
			}
		}
		for r in resolutions { callArgs.append("\(r.label): \(r.label)") }
		// qualify with `self.` — the typed verb macros (#store/#load/...)
		// shadow bare same-named member calls in this scope
		let call = "self.\(name)(\(callArgs.joined(separator: ", ")))"

		let abortLines = resolutions.map { "    \($0.label).abort()" }.joined(separator: "\n")
		let txMode = mode.modeExpr
		let tryKw = isThrowing ? "try " : ""

		var items: [CodeBlockItemSyntax] = []
		for r in resolutions {
			items.append(CodeBlockItemSyntax(stringLiteral: "let \(r.label) = try Transaction<\(txMode)>(env: \(r.expr).env)"))
		}
		if let retText {
			items.append(CodeBlockItemSyntax(stringLiteral: "let __mdb_output: \(retText)"))
			items.append(CodeBlockItemSyntax(stringLiteral: """
			do {
			    __mdb_output = \(tryKw)\(call)
			} catch let error {
			\(abortLines)
			    throw error
			}
			"""))
		} else {
			items.append(CodeBlockItemSyntax(stringLiteral: """
			do {
			    \(tryKw)\(call)
			} catch let error {
			\(abortLines)
			    throw error
			}
			"""))
		}
		// success path: readOnly aborts every tx; readWrite COMMITS every tx
		if mode.isReadWrite {
			for r in resolutions { items.append(CodeBlockItemSyntax(stringLiteral: "try \(r.label).commit()")) }
		} else {
			for r in resolutions { items.append(CodeBlockItemSyntax(stringLiteral: "\(r.label).abort()")) }
		}
		if retText != nil {
			items.append(CodeBlockItemSyntax(stringLiteral: "return __mdb_output"))
		}
		return items
	}

	// - MARK: PeerMacro — the invisible sibling

	static func expansion(
		of node: AttributeSyntax,
		providingPeersOf declaration: some DeclSyntaxProtocol,
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		let (fn, mode): (FunctionDeclSyntax, ParsedMode)
		do {
			(fn, mode) = try validateMethod(declaration, node: node)
		} catch {
			return []   // the BODY role owns the diagnostics
		}
		let body = fn.body?.statements ?? CodeBlockItemListSyntax([])
		let envNames = inferredEnvironments(of: body)
		if envNames.isEmpty { return [] }

		let enclosingType = MDB_transact_macro.enclosingTypeName(from: context)
		var resolutions: [(name: String, expr: String, label: String)] = []
		for envName in envNames {
			if MDB_transact_macro.instanceSourceCount(envName: envName, enclosingType: enclosingType, params: fn.signature.parameterClause) > 1 {
				return []   // the BODY role owns the diagnostic
			}
			guard let resolved = resolveInstance(envName: envName, enclosingType: enclosingType, params: fn.signature.parameterClause) else {
				return []
			}
			resolutions.append((name: envName, expr: resolved.expr, label: resolved.label))
		}

		// the sibling's parameters: the author's params + one `tx_<E>` each.
		// `borrowing` is the v16-proven shape — the transaction flows in by
		// explicit borrow (never captured); the CALLER owns the lifecycle.
		var paramStrs: [String] = []
		for p in fn.signature.parameterClause.parameters {
			var s = p.trimmedDescription
			if s.hasSuffix(",") { s = String(s.dropLast()) }
			paramStrs.append(s)
		}
		let txParamType = mode.isReadWrite ? "Transaction<Write>" : "Transaction<M>"
		for r in resolutions { paramStrs.append("\(r.label): borrowing \(txParamType)") }

		let modifiers = fn.modifiers.trimmedDescription
		var startAttrs = ""
		if fn.attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "discardableResult" }) {
			startAttrs = "@discardableResult "
		}
		// attributes must precede modifiers in the declaration grammar
		let modifierPrefix = startAttrs + (modifiers.isEmpty ? "" : modifiers + (modifiers.last == " " ? "" : " "))
		let name = fn.name.text
		// the sibling's generic clause: the AUTHOR's generic parameters PLUS
		// the mode-generic `M` (a read-only sibling is generic over the mode so
		// a read-write boundary can join it — write transactions read). a bare
		// authored generic method would otherwise lose its own parameter list
		// (`P` in `func bulkLoad<P>(...) where P:PairProtocol`), breaking the
		// body. the author's `where` clause rides on the SIGNATURE and is
		// appended after the return type.
		let genericNameList = fn.genericParameterClause?.parameters.map { $0.trimmedDescription } ?? []
		var genericClause: String
		if !genericNameList.isEmpty {
			genericClause = "<" + genericNameList.joined(separator: ", ") + (mode.isReadWrite ? ">" : ", M:TransactionMode>")
		} else {
			genericClause = mode.isReadWrite ? "" : "<M:TransactionMode>"
		}
		let authorWhere = fn.genericWhereClause.map { " \($0.trimmedDescription)" } ?? ""
		var effects = ""
		if fn.signature.effectSpecifiers?.throwsClause != nil { effects += " throws" }
		let ret = fn.signature.returnClause.map { " \($0.trimmedDescription)" } ?? ""

		// lower the body: every verb xruns the tx-bearing op; every
		// #MDB_transacted(...) marker joins this boundary's transactions
		let rewriter = SiblingRewriter(resolutions: resolutions)
		let rewritten = rewriter.visit(body)
		let bodyText = rewritten.map { $0.trimmedDescription }.joined(separator: "\n")

		let decl = "\(modifierPrefix)func \(name)\(genericClause)(\(paramStrs.joined(separator: ", ")))\(effects)\(ret)\(authorWhere) {\n\(bodyText)\n}"
		return [DeclSyntax(stringLiteral: decl)]
	}

	// - MARK: the sibling-body rewriter

	private final class SiblingRewriter: SyntaxRewriter {
		let resolutions: [(name: String, expr: String, label: String)]
		// env label lookup by type name
		private let labelBy: [String: String]
		private let exprBy: [String: String]

		init(resolutions: [(name: String, expr: String, label: String)]) {
			self.resolutions = resolutions
			self.labelBy = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.name, $0.label) })
			self.exprBy = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.name, $0.expr) })
		}

		override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
			let processed = super.visit(node)
			let expansion = processed.cast(MacroExpansionExprSyntax.self)
			let trailingTrivia = expansion.trailingTrivia
			let replacement: ExprSyntax
			switch expansion.macroName.text {
			case "store", "load", "delete", "contains", "cursor", "clear", "stats", "drop":
				replacement = lowerVerb(expansion) ?? ExprSyntax(expansion)
			case "MDB_transacted":
				replacement = rewriteJoined(expansion) ?? ExprSyntax(expansion)
			default:
				replacement = ExprSyntax(expansion)
			}
			// the lowered expression replaces the macro node, so the node's trailing
			// trivia (e.g. the space before a following `==`) lives only on the
			// ORIGINAL. dropping it makes an adjacent infix operator asymmetric
			// (`x)== y` — whitespace on one side only), which Swift lexes as UNARY,
			// and a `guard` condition then fails to parse ("expected 'else' after
			// 'guard' condition"). preserve the trivia so operators stay symmetric.
			if replacement.trailingTrivia.isEmpty {
				return replacement.with(\.trailingTrivia, trailingTrivia)
			}
			return replacement
		}

		private func arg(_ node: MacroExpansionExprSyntax, _ label: String) -> LabeledExprSyntax? {
			node.arguments.first { $0.label?.text == label }
		}

		/// #store(E.self, database: \.events, key: K, value: V, flags: F)
		///   -> <instance>[keyPath: \.events].store(key: K, value: V, flags: F, tx: tx_E)
		private func lowerVerb(_ node: MacroExpansionExprSyntax) -> ExprSyntax? {
			guard let envName = MDB_transact_macro.environmentTypeName(of: node),
				  let label = labelBy[envName],
				  let expr = exprBy[envName],
				  let keyPath = MDB_transact_macro.verbDatabaseKeyPathText(node) else { return nil }
			let receiver = "\(expr)[keyPath: \(keyPath)]"
			switch node.macroName.text {
			case "store":
				let value = arg(node, "value")?.expression.trimmedDescription ?? ""
				let flags = arg(node, "flags").map { ", flags: \($0.expression.trimmedDescription)" } ?? ""
				return ExprSyntax(stringLiteral: "\(receiver).store(key: \(arg(node, "key")?.expression.trimmedDescription ?? ""), value: \(value)\(flags), tx: \(label))")
			case "load":
				return ExprSyntax(stringLiteral: "\(receiver).load(key: \(arg(node, "key")?.expression.trimmedDescription ?? ""), tx: \(label))")
			case "delete":
				if let value = arg(node, "value") {
					return ExprSyntax(stringLiteral: "\(receiver).delete(key: \(arg(node, "key")?.expression.trimmedDescription ?? ""), value: \(value.expression.trimmedDescription), tx: \(label))")
				}
				return ExprSyntax(stringLiteral: "\(receiver).delete(key: \(arg(node, "key")?.expression.trimmedDescription ?? ""), tx: \(label))")
			case "contains":
				return ExprSyntax(stringLiteral: "\(receiver).contains(key: \(arg(node, "key")?.expression.trimmedDescription ?? ""), tx: \(label))")
			case "cursor":
				// the trailing closure is the final argument; keep it verbatim
				let closure = (node.trailingClosure)?.trimmedDescription ?? ""
				return ExprSyntax(stringLiteral: "\(receiver).cursor(tx: \(label)) \(closure)")
			case "clear":
				return ExprSyntax(stringLiteral: "\(receiver).deleteAllEntries(tx: \(label))")
			case "stats":
				return ExprSyntax(stringLiteral: "\(receiver).dbStatistics(tx: \(label))")
			case "drop":
				return ExprSyntax(stringLiteral: "\(receiver).deleteDatabase(tx: \(label))")
			default:
				return nil
			}
		}

		/// #MDB_transacted(callee(args)) -> callee(args, tx_<E>: tx_<E>, ...)
		/// Design B: route into the callee's sibling with THIS boundary's
		/// transactions. the callee must touch the same environment-type set —
		/// the equal-env-set contract, enforced by the rewrite's labels.
		private func rewriteJoined(_ node: MacroExpansionExprSyntax) -> ExprSyntax? {
			guard let call = node.arguments.first?.expression.as(FunctionCallExprSyntax.self) else { return nil }
			var parts: [String] = []
			for argument in call.arguments {
				var s = argument.trimmedDescription
				if s.hasSuffix(",") { s = String(s.dropLast()) }
				parts.append(s)
			}
			for r in resolutions { parts.append("\(r.label): \(r.label)") }
			// qualify bare callees with `self.` — the typed verb macros shadow
			// bare same-named member calls in this scope
			let calleeText: String
			if call.calledExpression.is(DeclReferenceExprSyntax.self) {
				calleeText = "self." + call.calledExpression.trimmedDescription
			} else {
				calleeText = call.calledExpression.trimmedDescription
			}
			var text = "\(calleeText)(\(parts.joined(separator: ", ")))"
			// a trailing closure may attach to the INNER call or to the marker
			// itself — preserve whichever the parser placed
			if let trailing = call.trailingClosure {
				text += " " + trailing.trimmedDescription
			}
			if let trailing = node.trailingClosure {
				text += " " + trailing.trimmedDescription
			}
			return ExprSyntax(stringLiteral: text)
		}
	}
}

// - MARK: standalone expansions (outside a boundary)

private struct BoundaryDiagnostic: DiagnosticMessage {
	let id: String
	let text: String
	var message: String { text }
	var diagnosticID: MessageID { MessageID(domain: "QuickLMDB", id: id) }
	var severity: DiagnosticSeverity { .error }
}

/// Design-B marker, standalone: there is no boundary transaction to join.
internal struct MDB_transacted_macro: ExpressionMacro {
	static func expansion(
		of node: some FreestandingMacroExpansionSyntax,
		in context: some MacroExpansionContext
	) throws -> ExprSyntax {
		context.diagnose(Diagnostic(
			node: Syntax(node),
			message: BoundaryDiagnostic(
				id: "transactedOutsideBoundary",
				text: "#MDB_transacted must appear inside an @MDB_transact body — the boundary rewrites it to join its transactions"
			)
		))
		return "nil"
	}
}

/// the typed verb vocabulary, standalone: no boundary to lower them.
/// one implementation serves every verb (the verb name is read from the node).
internal struct MDB_verb_error_macro: ExpressionMacro {
	static func expansion(
		of node: some FreestandingMacroExpansionSyntax,
		in context: some MacroExpansionContext
	) throws -> ExprSyntax {
		let verbName = node.macroName.text
		context.diagnose(Diagnostic(
			node: Syntax(node),
			message: BoundaryDiagnostic(
				id: "verbOutsideBoundary",
				text: "#\(verbName) must appear inside an @MDB_transact body — the boundary lowers it to the tx-bearing operation"
			)
		))
		return "nil"
	}
}
