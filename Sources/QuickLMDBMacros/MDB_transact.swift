import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// the boundary dialect (typed-environment architecture) on the real engine
// (capability-typed `Transaction<M>`, @MDB_environment types).
//
// @MDB_transact(_ mode:) — attached BODY + PEER on INSTANCE methods.
//   every environment is its own TYPE (an @MDB_environment type). a boundary
//   lives on an environment type (the environment is `self`) and may
//   additionally take other environments as typed parameters. the body is written with the TYPED VERB
//   FAMILY — `#store(E.self, database: \\.events, key:..., value:...)` — where
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
				return "@MDB_transact body has no database verbs (#store/#load/#delete/#contains/#cursor/#clear/#stats/#drop) — the boundary's environments are inferred from the verbs"
			case .missingEnvironmentInstance(let env):
				return "@MDB_transact: no instance of environment type '\(env)' is in scope — attach the boundary to '\(env)' itself, or add a parameter of type '\(env)'"
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

	/// `MyEnvironment.self` or `E.self` — member access whose declName is
	/// `self`, with a possibly-COMPOUND base (a namespaced environment:
	/// `MyNamespace.Environment.self` yields `"MyNamespace.Environment"`).
	private static func environmentTypeName(of verb: MacroExpansionExprSyntax) -> String? {
		guard let first = verb.arguments.first?.expression else { return nil }
		// `MyEnvironment.self`
		if let member = first.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "self" {
			return compoundName(of: member.base)
		}
		// a bare type reference (`MyEnvironment`)
		if let ref = first.as(DeclReferenceExprSyntax.self) {
			return ref.baseName.text
		}
		return nil
	}

	/// unwraps a `self`-member's base chain into a dotted type name:
	/// `MyNamespace.Environment` (base of `.self`) → `"MyNamespace.Environment"`.
	private static func compoundName(of base: ExprSyntax?) -> String? {
		var parts: [String] = []
		var cur: ExprSyntax? = base
		while let c = cur {
			if let ref = c.as(DeclReferenceExprSyntax.self) {
				parts.insert(ref.baseName.text, at: 0)
				break
			}
			if let m = c.as(MemberAccessExprSyntax.self), m.declName.baseName.text != "self" {
				parts.insert(m.declName.baseName.text, at: 0)
				cur = m.base
				continue
			}
			return nil
		}
		return parts.isEmpty ? nil : parts.joined(separator: ".")
	}

	private static func verbDatabaseKeyPathText(_ verb: MacroExpansionExprSyntax) -> String? {
		verb.arguments.first { $0.label?.text == "database" }?.expression.trimmedDescription
	}

	// - MARK: environment type identity + tx labels

	/// whether two type spellings denote the SAME environment type. with the
	/// group layer gone, every environment is a standalone type: references
	/// are simple names (`MyEnvironment.self`), so equality is exact.
	private static func isSameEnvironmentType(_ a: String, _ b: String) -> Bool {
		a == b
	}

	/// the transaction label for an environment type reference: `tx_<Type>`
	/// — one type = one physical env = one label.
	private static func labelFor(_ envName: String) -> String {
		"tx_" + envName
	}

	// - MARK: environment instance resolution

	/// the instance expression for an environment type name: `self` when the
	/// boundary is attached to the environment type itself, otherwise the
	/// first parameter declared with that type.
	private static func resolveInstance(
		envName: String,
		enclosingType: String?,
		params: FunctionParameterClauseSyntax?
	) -> String? {
		if let enclosingType, isSameEnvironmentType(envName, enclosingType) {
			return "self"
		}
		if let params {
			for p in params.parameters {
				let typeText = p.type.trimmedDescription
				if isSameEnvironmentType(envName, typeText) {
					let expr = p.secondName?.text ?? p.firstName.text
					return expr
				}
			}
		}
		return nil
	}

	/// how many instances of an environment type are in scope (self and/or
	/// typed parameters). more than one cannot be addressed by the verbs.
	private static func instanceSourceCount(envName: String, enclosingType: String?, params: FunctionParameterClauseSyntax?) -> Int {
		var count = 0
		if let enclosingType, isSameEnvironmentType(envName, enclosingType) { count += 1 }
		if let params {
			for p in params.parameters {
				let t = p.type.trimmedDescription
				if isSameEnvironmentType(envName, t) { count += 1 }
			}
		}
		return count
	}

	/// resolves every env type the body touched to `(name, label, instance)`,
	/// in canonical label-sorted order — the shell/sibling/join emission. one
	/// type = one env = one label, so there is no per-label collapse.
	private static func resolveEnvironments(
		envNames: [String],
		enclosingType: String?,
		params: FunctionParameterClauseSyntax?
	) throws -> [(name: String, label: String, expr: String)] {
		var raw: [(name: String, label: String, expr: String)] = []
		for envName in envNames {
			if instanceSourceCount(envName: envName, enclosingType: enclosingType, params: params) > 1 {
				throw Failure.ambiguousEnvironment(envName)
			}
			guard let expr = resolveInstance(envName: envName, enclosingType: enclosingType, params: params) else {
				throw Failure.missingEnvironmentInstance(envName)
			}
			raw.append((name: envName, label: labelFor(envName), expr: expr))
		}
		// canonical order: label-sorted
		return raw.sorted { $0.label < $1.label }
	}

	/// the name of the environment type a boundary is attached to: the
	/// enclosing struct's name, or the extended-type text when declared in an
	/// extension of an environment type.
	private static func enclosingTypeName(from context: some MacroExpansionContext) -> String? {
		for decl in context.lexicalContext {
			if let s = decl.as(StructDeclSyntax.self) {
				return s.name.text
			}
			if let e = decl.as(ExtensionDeclSyntax.self) {
				return e.extendedType.trimmedDescription
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

	// - MARK: the cursor closure's try-ability (DEBT item 4)

	/// true when the AUTHORED site wrapped this verb in an explicit `try`
	/// (`try #cursor(...)` — the recommended spelling). the check walks the
	/// parent chain through parens and argument labels only, so an UNRELATED
	/// try further out (`try foo(#cursor(...))`) never counts — the try must
	/// wrap the cursor call itself.
	private static func authoredTryWrapping(_ node: MacroExpansionExprSyntax) -> Bool {
		var cur = node.parent
		while let c = cur {
			if c.is(TupleExprSyntax.self) || c.is(LabeledExprSyntax.self) {
				cur = c.parent
				continue
			}
			if c.is(TryExprSyntax.self) { return true }
			return false
		}
		return false
	}

	/// rebuild the trailing closure with an explicit `throws` annotation after
	/// its parameter clause. the handler type is `throws(E)`, and an
	/// explicitly-throwing closure forces E away from `Never` — so the emitted
	/// call is UNCONDITIONALLY throwing: `try` is always required and never a
	/// warning, in every `#if` configuration. nil when injection is impossible
	/// (no parameter clause — a `$0`-style closure — the author already
	/// declared `throws`, or the signature carries elements this emitter
	/// cannot reproduce faithfully).
	private static func forceThrowsClosure(_ closure: ClosureExprSyntax) -> String? {
		guard let sig = closure.signature,
			  sig.effectSpecifiers?.throwsClause == nil,
			  sig.attributes.isEmpty,
			  sig.effectSpecifiers?.asyncSpecifier == nil,
			  let paramClause = sig.parameterClause else { return nil }
		// unexpected-node scan: any parse gap (or an element this rebuild does
		// not emit) means the authored signature cannot be mirrored byte-safe —
		// injecting would silently drop or corrupt it (e.g. a capture list was
		// once dropped here by reconstruction). fall back to the verbatim
		// closure instead of risking silent semantic change.
		for child in sig.children(viewMode: .sourceAccurate) {
			if child.is(UnexpectedNodesSyntax.self) { return nil }
		}
		var out = "{"
		if let cap = sig.capture { out += " " + cap.trimmedDescription }
		out += " " + paramClause.trimmedDescription
		out += " throws"
		if let ret = sig.returnClause { out += " " + ret.trimmedDescription }
		out += " in" + closure.statements.description
		// the trivia between the last body statement and the closing brace
		// lives on `rightBrace.leadingTrivia` — dropped, an `#if`/`#endif`
		// block closing a closure would glue its `#endif` to the brace
		// (`#endif}` — "extra tokens following conditional compilation")
		out += closure.rightBrace.leadingTrivia.description
		out += "}"
		return out
	}

	// - MARK: BodyMacro — the shell

	/// the author's arguments by their original labels for a sibling/body
	/// call. INOUT parameters must be re-prefixed with `&` — the callee takes
	/// them by reference and the caller owns the storage.
	private static func callArgsText(parameters: FunctionParameterClauseSyntax?) -> [String] {
		guard let parameters else { return [] }
		var callArgs: [String] = []
		for p in parameters.parameters {
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
		return callArgs
	}

	static func expansion(
		of node: AttributeSyntax,
		providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
		in context: some MacroExpansionContext
	) throws -> [CodeBlockItemSyntax] {
		let (fn, mode) = try validateMethod(declaration, node: node)
		let body = fn.body?.statements ?? CodeBlockItemListSyntax([])

		let envNames = inferredEnvironments(of: body)
		let enclosingType = MDB_transact_macro.enclosingTypeName(from: context)
		guard !envNames.isEmpty else { throw Failure.noVerbs }

		let resolutions = try resolveEnvironments(envNames: envNames, enclosingType: enclosingType, params: fn.signature.parameterClause)

		let name = fn.name.text
		let isThrowing = fn.signature.effectSpecifiers?.throwsClause != nil
		let retText = fn.signature.returnClause?.type.trimmedDescription

		// the shell's call into the sibling: the author's arguments by their
		// original labels, then one `tx_<E>: tx_<E>` per inferred environment.
		var callArgs = MDB_transact_macro.callArgsText(parameters: fn.signature.parameterClause)
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
		let enclosingType = MDB_transact_macro.enclosingTypeName(from: context)
		if envNames.isEmpty { return [] }

		let resolutions: [(name: String, label: String, expr: String)]
		do {
			resolutions = try resolveEnvironments(envNames: envNames, enclosingType: enclosingType, params: fn.signature.parameterClause)
		} catch {
			return []   // the BODY role owns the diagnostic
		}

		// the sibling's parameters: the author's params + one `tx_<E>` each.
		// `borrowing` is the v16-proven shape — the transaction flows in by
		// explicit borrow (never captured); the CALLER owns the lifecycle.
		var authorParams: [String] = []
		for p in fn.signature.parameterClause.parameters {
			var s = p.trimmedDescription
			if s.hasSuffix(",") { s = String(s.dropLast()) }
			authorParams.append(s)
		}
		let txParamType = mode.isReadWrite ? "Transaction<Write>" : "Transaction<M>"
		let paramStrs = authorParams + resolutions.map { "\($0.label): borrowing \(txParamType)" }

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

		// lower the body: every verb runs the tx-bearing op; every
		// #MDB_transacted(...) marker joins this boundary's transactions
		// (the rewriter's lookups carry every env reference)
		let rewriter = SiblingRewriter(resolutions: resolutions)
		let rewritten = rewriter.visit(body)
		let bodyText = rewritten.map { $0.trimmedDescription }.joined(separator: "\n")

		let flatDecl = "\(modifierPrefix)func \(name)\(genericClause)(\(paramStrs.joined(separator: ", ")))\(effects)\(ret)\(authorWhere) {\n\(bodyText)\n}"

		// the CHILD variant — the peer'd `_child` entry the join rewrite routes
		// into. a WRITE variant opens one child transaction per environment
		// label (of the tx it was handed — a root at top level, or an outer
		// join's child), runs the body DIRECTLY INLINE against the child txns
		// (no closure wrapper), commits each child (folds into the parent) or
		// aborts them (selective rollback when the caller catches). the
		// authored `return` statements are re-pointed to a labeled exit
		// (`__mdb_output = …` + `break childWrapped`) so every path lands AFTER
		// the commits. a READ variant is byte-identical to flat — the join
		// site cannot classify read-vs-write, so reads carry the flat twin.
		let childName = name + "_child"
		let childDecl: String
		if mode.isReadWrite {
			let override = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.label, "__child_" + $0.label) })
			let childRewriter = SiblingRewriter(resolutions: resolutions, txOverride: override)
			let childBodyText = childRewriter.visit(body).map { $0.trimmedDescription }.joined(separator: "\n")
			let retType = fn.signature.returnClause?.type.trimmedDescription
			let hasReturns = MDB_transact_macro.bodyHasReturns(of: body)
			let abortLines = resolutions.map { "    __child_\($0.label).abort()" }.joined(separator: "\n")
			let commitLines = resolutions.map { "    try __child_\($0.label).commit()" }.joined(separator: "\n")
			var childLines: [String] = []
			for r in resolutions {
				childLines.append("    let __child_\(r.label) = try Transaction<Write>(env: \(r.expr).env, parent: \(r.label))")
			}
			if let retType {
				childLines.append("    let __mdb_output: \(retType)")
				if hasReturns {
					// lower the body first (verbs + inner joins), THEN re-point
					// its returns to the labeled exit
					let lowered = childRewriter.visit(body)
					let reroute = ChildReturnRewriter(assignTo: "__mdb_output", label: "childWrapped").visit(lowered)
					let reroutedText = reroute.map { $0.trimmedDescription }.joined(separator: "\n")
					childLines.append("    childWrapped: do {")
					childLines.append("        \(reroutedText)")
					childLines.append("    } catch let error {")
					childLines.append(abortLines)
					childLines.append("        throw error")
					childLines.append("    }")
				} else {
					childLines.append("    do {")
					childLines.append("        __mdb_output = \(childBodyText)")
					childLines.append("    } catch let error {")
					childLines.append(abortLines)
					childLines.append("        throw error")
					childLines.append("    }")
				}
				childLines.append(commitLines)
				childLines.append("    return __mdb_output")
			} else if hasReturns {
				let lowered = childRewriter.visit(body)
				let reroute = ChildReturnRewriter(assignTo: nil, label: "childWrapped").visit(lowered)
				let reroutedText = reroute.map { $0.trimmedDescription }.joined(separator: "\n")
				childLines.append("    childWrapped: do {")
				childLines.append("        \(reroutedText)")
				childLines.append("    } catch let error {")
				childLines.append(abortLines)
				childLines.append("        throw error")
				childLines.append("    }")
				childLines.append(commitLines)
			} else {
				childLines.append("    do {")
				childLines.append("        \(childBodyText)")
				childLines.append("    } catch let error {")
				childLines.append(abortLines)
				childLines.append("        throw error")
				childLines.append("    }")
				childLines.append(commitLines)
			}
			childDecl = "\(modifierPrefix)func \(childName)\(genericClause)(\(paramStrs.joined(separator: ", ")))\(effects)\(ret)\(authorWhere) {\n\(childLines.joined(separator: "\n"))\n}"
		} else {
			// a READ `_child` twin is a THIN REDIRECT to the flat sibling: a
			// joined read threads THIS caller's transaction (it NEVER spawns a
			// child — LMDB has no read-only children, pinned MDB_BAD_TXN), so
			// the redirect is the entire body. no duplicated body per peer.
			var redirectArgs = MDB_transact_macro.callArgsText(parameters: fn.signature.parameterClause)
			for r in resolutions { redirectArgs.append("\(r.label): \(r.label)") }
			let redirect = "    try self.\(name)(\(redirectArgs.joined(separator: ", ")))"
			childDecl = "\(modifierPrefix)func \(childName)\(genericClause)(\(paramStrs.joined(separator: ", ")))\(effects)\(ret)\(authorWhere) {\n\(redirect)\n}"
		}
		return [DeclSyntax(stringLiteral: flatDecl), DeclSyntax(stringLiteral: childDecl)]
	}

	// - MARK: the sibling-body rewriter

	/// whether the authored body contains a RETURN outside any closure (a
	/// closure's `return` belongs to the closure and must not be re-pointed).
	private static func bodyHasReturns(of body: CodeBlockItemListSyntax) -> Bool {
		let scanner = ReturnScanner()
		scanner.walk(body)
		return scanner.found
	}

	private final class ReturnScanner: SyntaxVisitor {
		var found = false
		init() {
			super.init(viewMode: .sourceAccurate)
		}
		override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
			.skipChildren
		}
		override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
			found = true
			return .skipChildren
		}
	}

	/// re-points authored `return` statements to a LABELED EXIT so a `_child`
	/// variant can run the body INLINE and still close its child transactions
	/// (commit/abort) before the boundary returns through `__mdb_output`:
	/// - `return expr` → `__mdb_output = expr` + `break childWrapped`
	/// - `return`      → `break childWrapped`
	/// returns inside CLOSURES are the closure's own and are left untouched.
	private final class ChildReturnRewriter: SyntaxRewriter {
		private let assignTo: String?
		private let label: String
		init(assignTo: String?, label: String) {
			self.assignTo = assignTo
			self.label = label
			super.init(viewMode: .sourceAccurate)
		}
		override func visit(_ node: ClosureExprSyntax) -> ExprSyntax {
			ExprSyntax(node)
		}
		override func visit(_ node: CodeBlockItemListSyntax) -> CodeBlockItemListSyntax {
			var items: [CodeBlockItemSyntax] = []
			for item in node {
				if let ret = item.item.as(ReturnStmtSyntax.self) {
					// constructed items carry NO trailing trivia — a
					// CodeBlockItemList serializes elements back-to-back, so
					// each replacement must end with its own newline
					if let assignTo, let expr = ret.expression {
						items.append(CodeBlockItemSyntax(stringLiteral: "\(assignTo) = \(expr.trimmedDescription)").with(\.trailingTrivia, .newline))
					}
					items.append(CodeBlockItemSyntax(stringLiteral: "break \(label)").with(\.trailingTrivia, .newline))
				} else {
					items.append(visit(item))
				}
			}
			return CodeBlockItemListSyntax(items)
		}
	}

	private final class SiblingRewriter: SyntaxRewriter {
		let resolutions: [(name: String, label: String, expr: String)]
		// env label lookup by type name
		private let labelBy: [String: String]
		private let exprBy: [String: String]
		/// the tx EXPRESSION for a label — the child variant substitutes its
		/// own child local (`__child_<label>`); flat bodies keep the label.
		private let txOverride: [String: String]

		init(resolutions: [(name: String, label: String, expr: String)], txOverride: [String: String] = [:]) {
			self.resolutions = resolutions
			self.labelBy = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.name, $0.label) })
			self.exprBy = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.name, $0.expr) })
			self.txOverride = txOverride
		}

		private func txExpr(for label: String) -> String {
			txOverride[label] ?? label
		}

		override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
			// whether the AUTHORED site wrapped this verb in `try` (the
			// recommended spelling). computed on the ORIGINAL node — the
			// processed node's parent pointers are not reliable.
			let authoredTry = MDB_transact_macro.authoredTryWrapping(node)
			let processed = super.visit(node)
			let expansion = processed.cast(MacroExpansionExprSyntax.self)
			let trailingTrivia = expansion.trailingTrivia
			let replacement: ExprSyntax
			switch expansion.macroName.text {
			case "store", "load", "delete", "contains", "cursor", "clear", "stats", "drop":
				replacement = lowerVerb(expansion, authoredTry: authoredTry) ?? ExprSyntax(expansion)
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
		private func lowerVerb(_ node: MacroExpansionExprSyntax, authoredTry: Bool) -> ExprSyntax? {
			guard let envName = MDB_transact_macro.environmentTypeName(of: node),
				  let label = labelBy[envName],
				  let expr = exprBy[envName],
				  let keyPath = MDB_transact_macro.verbDatabaseKeyPathText(node) else { return nil }
			let receiver = "\(expr)[keyPath: \(keyPath)]"
			let txText = txExpr(for: label)
			switch node.macroName.text {
			case "store":
				let value = arg(node, "value")?.expression.trimmedDescription ?? ""
				let flags = arg(node, "flags").map { ", flags: \($0.expression.trimmedDescription)" } ?? ""
				return ExprSyntax(stringLiteral: "\(receiver).store(key: \(arg(node, "key")?.expression.trimmedDescription ?? ""), value: \(value)\(flags), tx: \(txText))")
			case "load":
				return ExprSyntax(stringLiteral: "\(receiver).load(key: \(arg(node, "key")?.expression.trimmedDescription ?? ""), tx: \(txText))")
			case "delete":
				if let value = arg(node, "value") {
					return ExprSyntax(stringLiteral: "\(receiver).delete(key: \(arg(node, "key")?.expression.trimmedDescription ?? ""), value: \(value.expression.trimmedDescription), tx: \(txText))")
				}
				return ExprSyntax(stringLiteral: "\(receiver).delete(key: \(arg(node, "key")?.expression.trimmedDescription ?? ""), tx: \(txText))")
			case "contains":
				return ExprSyntax(stringLiteral: "\(receiver).contains(key: \(arg(node, "key")?.expression.trimmedDescription ?? ""), tx: \(txText))")
			case "cursor":
				// the trailing closure is the final argument. the emitted call
				// must never require a CONDITIONAL `try`: the handler type is
				// `throws(E)`, so a non-throwing closure makes `try` spurious
				// (the pricedb warnings), and an `#if`-gated closure makes
				// try-ness configuration-dependent. an explicitly-`throws`
				// closure forces E away from `Never`, so `try` is ALWAYS
				// correct and never a warning. inject it when the authored
				// site carries `try` (the recommended spelling) or when the
				// closure contains `#if`; a bare non-`#if` closure keeps the
				// non-throwing (`Never`) path, so consumers who omit `try` on
				// pure closures keep compiling.
				guard let closure = node.trailingClosure else {
					return ExprSyntax(stringLiteral: "\(receiver).cursor(tx: \(txText)")
				}
				let closureText: String
				if (authoredTry || closure.description.contains("#if")),
				   let injected = MDB_transact_macro.forceThrowsClosure(closure) {
					closureText = injected
				} else {
					closureText = closure.trimmedDescription
				}
				return ExprSyntax(stringLiteral: "\(receiver).cursor(tx: \(txText)) \(closureText)")
			case "clear":
				return ExprSyntax(stringLiteral: "\(receiver).deleteAllEntries(tx: \(txText))")
			case "stats":
				return ExprSyntax(stringLiteral: "\(receiver).dbStatistics(tx: \(txText))")
			case "drop":
				return ExprSyntax(stringLiteral: "\(receiver).deleteDatabase(tx: \(txText))")
			default:
				return nil
			}
		}

		/// #MDB_transacted(callee(args)) -> callee_child(args, tx_<E>: tx_<E>)
		/// Design B: route into the callee's `_child` sibling — a child
		/// transaction of this boundary's CURRENT tx per environment (the `tx`
		/// values here are the ones this boundary holds, which at depth are
		/// themselves children). the `_child` suffix selects the child variant;
		/// the callee must touch the same environment-label set — the
		/// equal-label-set contract, enforced by the rewrite's labels.
		private func rewriteJoined(_ node: MacroExpansionExprSyntax) -> ExprSyntax? {
			guard let call = node.arguments.first?.expression.as(FunctionCallExprSyntax.self) else { return nil }
			var parts: [String] = []
			for argument in call.arguments {
				var s = argument.trimmedDescription
				if s.hasSuffix(",") { s = String(s.dropLast()) }
				parts.append(s)
			}
			for r in resolutions { parts.append("\(r.label): \(txExpr(for: r.label))") }
			// qualify bare callees with `self.` — the typed verb macros shadow
			// bare same-named member calls in this scope
			let calleeText: String
			if call.calledExpression.is(DeclReferenceExprSyntax.self) {
				calleeText = "self." + call.calledExpression.trimmedDescription
			} else {
				calleeText = call.calledExpression.trimmedDescription
			}
			// route into the peer'd `_child` variant: splice the suffix onto
			// the METHOD name (before any trailing generic clause — never onto
			// a dotted type prefix)
			let childCallee: String
			if let lt = calleeText.firstIndex(of: "<"),
				let lastDot = calleeText.lastIndex(of: "."),
				lt > lastDot {
				childCallee = String(calleeText[..<lt]) + "_child" + String(calleeText[lt...])
			} else {
				childCallee = calleeText + "_child"
			}
			var text = "\(childCallee)(\(parts.joined(separator: ", ")))"
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
