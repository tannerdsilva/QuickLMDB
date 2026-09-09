import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

// @MDB_transact_span — cross-environment transaction boundary.
//
// attached BODY macro: like @MDB_transact, rewrites the annotated method's body
// in place, but coordinates MULTIPLE `@MDB_environment` cores at once — one
// top-level transaction per participating core, opened up front (full staging
// overlap), ALL aborted on body throw, and the write members committed
// back-to-back in declaration/inference order. reads are sibling transactions
// (never committed), exactly as in the single-env relationship matrix.
//
// usage:
//   @MDB_app
//   public struct HybridApp {
//       public var calendar: CalendarCore
//       public var contacts: ContactCore
//
//       @MDB_transact_span                       // bare: infer from the verbs
//       public func scheduleMeeting(...) throws {
//           try #store(calendar.events, key: day, value: event)
//           ...
//       }
//
//       @MDB_transact_span([.readWrite("calendar")])   // override: force modes/order
//       public func forceMode(...) throws { ... }
//   }
//
// the BARE form infers, from the verb calls in the body:
//   envs   = the receiver base identifiers (calendar, contacts, ...)
//   modes  = any write verb (#store/#delete/#clear) on an env ⇒ .readWrite;
//            read-only access alone ⇒ .readOnly
//   order  = first-touch order in the body (write members commit in that order)
//
// the container must be annotated @MDB_app (its stored-property scan is the
// routing table + the source of the unknown-base diagnostic). injected tx names
// are `tx_<base>` — the documented composition contract, mirroring single-env `tx`
// (pass one to a `.readWriteChild(parent:)` boundary to merge into a member).
//
// marker-gated lowering: ONLY the freestanding verbs are rewritten (via the
// shared MDB_verbLowering); every other line is byte-identical.
//
// honest ceiling: LMDB commits are per-environment, so the span is BEST-EFFORT
// ACROSS environments — a crash between the adjacent commit calls can still
// leave the first members durable and later ones not. the window is narrowed to
// the commit pair itself; cross-env atomicity is impossible and is documented.

internal struct MDB_transact_span_macro:BodyMacro {

		private enum MacroError:Swift.Error, CustomStringConvertible {
		case notAFunction
		case asyncNotSupported
		case mustBeThrowing
		case typedThrowsUnsupported
		case neverReturnUnsupported
		case requiresMDBApp
		case noVerbs
		case invalidMember(String)

		var description:String {
			switch self {
				case .notAFunction:
					return "@MDB_transact_span can only be applied to a function"
				case .asyncNotSupported:
					return "@MDB_transact_span does not support async methods - a transaction must not cross an await"
				case .mustBeThrowing:
					return "@MDB_transact_span requires the method to be marked `throws` - the boundary can fail to open, commit, or abort"
				case .typedThrowsUnsupported:
					return "@MDB_transact_span requires an untyped `throws` - the boundary rethrows the body's error, so a typed throws clause cannot be represented"
				case .neverReturnUnsupported:
					return "@MDB_transact_span does not support `-> Never` return types"
				case .requiresMDBApp:
					return "@MDB_transact_span requires the containing type to be annotated @MDB_app (the container's stored properties are the environment inventory)"
				case .noVerbs:
					return "@MDB_transact_span body has no verb calls (#store/#load/#delete/#contains/#cursor/#clear) - the span infers its environments from the verbs"
				case .invalidMember(let name):
					return "@MDB_transact_span member `\(name)` is invalid"
			}
		}
	}

	// a single span member: core name + whether it carries writes (@MDB_transact(.readWrite)-like)
	private struct Member {
		let name:String
		let isWrite:Bool
	}

	// - MARK: inference

	/// collects every verb call in the subtree as (baseName, verbName) pairs, in
	/// source order, descending into closures so verbs inside cursor handlers
	/// participate.
	private final class VerbCollector:SyntaxVisitor {
		var found:[(base:String, verb:String)] = []
		override func visit(_ node:MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
			let verb = node.macroName.text
			if MDB_verbLowering.names.contains(verb) {
				if let firstArg = node.arguments.first, firstArg.label == nil, let base = MDB_verbLowering.baseName(of:firstArg) {
					found.append((base:base, verb:verb))
				}
			}
			// keep descending: verbs can be nested inside other expressions
			return .visitChildren
		}
		override func visit(_ node:ClosureExprSyntax) -> SyntaxVisitorContinueKind {
			return .visitChildren
		}
	}

	private static func isWriteVerb(_ verb:String) -> Bool {
		// #drop (deleteDatabase) is destructive even though it does not write rows
		return verb == "store" || verb == "delete" || verb == "clear" || verb == "drop"
	}

	// - MARK: the enclosing @MDB_app container

	/// walks the lexical context to find the enclosing type and verify it carries
	/// the `@MDB_app` attribute — the span's GATE. NOTE: a body macro's lexical
	/// context exposes the type NAME and ATTRIBUTES but NOT its stored members
	/// (verified: lexicalContext yields an empty member shell, and
	/// `declaration.parent` stops at the function decl). routing therefore comes
	/// from the body's OWN verb calls (receiver base identifiers), and unknown
	/// names surface as a compiler error at the generated `self.<name>.env`
	/// splice — loud and precise, though not a custom macro diagnostic.
	private static func containerHasMDBApp(from context:some MacroExpansionContext) -> Bool {
		for decl in context.lexicalContext {
			if let structDecl = decl.as(StructDeclSyntax.self) {
				return structDecl.attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "MDB_app" })
			}
			if let classDecl = decl.as(ClassDeclSyntax.self) {
				return classDecl.attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "MDB_app" })
			}
		}
		return false
	}

	// - MARK: override parsing

	/// parses `@MDB_transact_span([.readWrite("calendar"), .readOnly("contacts")])`
	private static func parseOverride(_ node:AttributeSyntax) throws -> [Member]? {
		guard let argList = node.arguments?.as(LabeledExprListSyntax.self), let first = argList.first else {
			return nil   // bare form
		}
		guard let array = first.expression.as(ArrayExprSyntax.self) else {
			return nil   // bare form (no arguments)
		}
		var members:[Member] = []
		for element in array.elements {
			guard let call = element.expression.as(FunctionCallExprSyntax.self),
				  let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) else {
				throw MacroError.invalidMember(element.expression.trimmedDescription)
			}
			// the core is named by its stored property name as a string literal
			guard let nameArg = call.arguments.first?.expression.as(StringLiteralExprSyntax.self) else {
				throw MacroError.invalidMember(element.expression.trimmedDescription)
			}
			let modeName = memberAccess.declName.baseName.text
			guard modeName == "readWrite" || modeName == "readOnly" else {
				throw MacroError.invalidMember(element.expression.trimmedDescription)
			}
			let name = nameArg.segments.first?.as(StringSegmentSyntax.self)?.content.text ?? ""
			guard name.isEmpty == false else {
				throw MacroError.invalidMember(element.expression.trimmedDescription)
			}
			members.append(Member(name:name, isWrite:modeName == "readWrite"))
		}
		return members
	}

	// - MARK: body macro entry point

	static func expansion(of node:AttributeSyntax, providingBodyFor declaration:some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax, in context:some MacroExpansionContext) throws -> [CodeBlockItemSyntax] {
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
		let retTypeText:String? = fn.signature.returnClause?.type.trimmedDescription
		if let retTypeText, retTypeText == "Never" {
			throw MacroError.neverReturnUnsupported
		}
		let hasReturnValue = retTypeText != nil

		// -- the @MDB_app container gate (attribute presence is the toolchain-visible
		//    signal; the member inventory itself is generated for the public surface
		//    but NOT scanable from inside a body macro — see containerHasMDBApp)
		guard containerHasMDBApp(from:context) else {
			throw MacroError.requiresMDBApp
		}

		// -- determine members: bare form infers from the body verbs, override form
		//    is explicit
		let rawStatements = fn.body?.statements ?? CodeBlockItemListSyntax([])
		let collector = VerbCollector(viewMode:.sourceAccurate)
		collector.walk(rawStatements)

		let members:[Member]
		if let override = try parseOverride(node) {
			members = override
		} else {
			// bare inference: first-touch order, any write verb ⇒ readWrite
			var order:[String] = []
			var writes = Set<String>()
			for (base, verb) in collector.found {
				if order.contains(base) == false { order.append(base) }
				if isWriteVerb(verb) { writes.insert(base) }
			}
			guard order.isEmpty == false else {
				throw MacroError.noVerbs
			}
			members = order.map { Member(name:$0, isWrite:writes.contains($0)) }
		}
		// an override with no members is meaningless; the bare form already
		// guaranteed non-empty
		guard members.isEmpty == false else {
			throw MacroError.noVerbs
		}

		// a write verb on an env the override pinned readOnly is an internal
		// contradiction (the compiler would fail the write call with EACCES at
		// runtime — catch it at expansion instead)
		for member in members where member.isWrite == false {
			if collector.found.contains(where: { $0.base == member.name && isWriteVerb($0.verb) }) {
				throw MacroError.invalidMember(member.name + " (pinned .readOnly but the body writes to it)")
			}
		}

		// -- per-member transaction locals, first-touch/declaration order
		let openLines:[String] = members.map { member in
			"let tx_\(member.name) = try Transaction(env: self.\(member.name).env, readOnly: \(member.isWrite ? "false" : "true"))"
		}

		// -- nested function: same parameters as the method + one borrowed tx per member
		var nestedParams:[String] = params.map { p in
			let s = p.trimmedDescription
			return s.hasSuffix(",") ? String(s.dropLast()) : s
		}
		for member in members {
			nestedParams.append("_ tx_\(member.name): borrowing Transaction")
		}
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
		for member in members {
			callArgs.append("tx_\(member.name)")
		}

		// -- transform the original body: lower verbs, routing by receiver base
		let rewriter = MDB_verbLowering.Rewriter(route: { base in "tx_\(base)" })
		let transformedItems = rewriter.visit(rawStatements)
		let bodyText = transformedItems.map { $0.trimmedDescription }.joined(separator:"\n")

		var items:[CodeBlockItemSyntax] = []
		for line in openLines {
			items.append(CodeBlockItemSyntax(stringLiteral: line))
		}
		items.append(CodeBlockItemSyntax(stringLiteral: "func __mdb_body(\(nestedParams.joined(separator:", ")))\(throwsAndReturns) {\n\(bodyText)\n}"))
		if let retTypeText {
			items.append(CodeBlockItemSyntax(stringLiteral: "let __mdb_output: \(retTypeText)"))
		}
		// the do/catch boundary is a SINGLE statement item (control flow must not
		// be assembled from separate top-level code block items)
		var doCatchLines:[String] = []
		doCatchLines.append("do {")
		if hasReturnValue {
			doCatchLines.append("    __mdb_output = try __mdb_body(\(callArgs.joined(separator:", ")))")
		} else {
			doCatchLines.append("    try __mdb_body(\(callArgs.joined(separator:", ")))")
		}
		doCatchLines.append("} catch let error {")
		for member in members {
			doCatchLines.append("    tx_\(member.name).abort()")
		}
		doCatchLines.append("    throw error")
		doCatchLines.append("}")
		items.append(CodeBlockItemSyntax(stringLiteral: doCatchLines.joined(separator:"\n")))
		// commit write members back-to-back in member order; close read members
		for member in members {
			if member.isWrite {
				items.append(CodeBlockItemSyntax(stringLiteral: "try tx_\(member.name).commit()"))
			} else {
				items.append(CodeBlockItemSyntax(stringLiteral: "tx_\(member.name).abort()"))
			}
		}
		if hasReturnValue {
			items.append(CodeBlockItemSyntax(stringLiteral: "return __mdb_output"))
		}
		return items
	}
}
