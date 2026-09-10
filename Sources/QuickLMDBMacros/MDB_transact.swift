import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// the boundary dialect (v16-iterated design) on the REAL engine (noncopyable
// Transaction, @MDB_environment cores).
//
// @MDB_transact: attached BODY + PEER.
//   BODY — scrapes the user's body, replaces it with a SHELL that opens
//          `tx_<E> = try Transaction(env: <E>.env, readOnly: <mode>)` per listed
//          environment, calls the WRAPPED SIBLING with those transactions, and
//          closes every one: `.readOnly` aborts on throw AND on success (a read
//          leaf never commits); `.readWrite` aborts on throw and COMMITS on
//          success.
//   PEER — emits the WRAPPED SIBLING (overload, same base name): the author's
//          parameters plus `tx_<E>: borrowing Transaction` per environment,
//          whose body is the scraped body with the trailing verbs (#MDB_entry_load,
//          #MDB_entry_store) lowered and every #MDB_transacted(...) marker rewritten to
//          a JOINED call (Design B: one transaction across the composed call —
//          atomic for writes).
//
// ownership shape is the proven v16 formulation: the transactions flow into
// the sibling as `borrowing` parameters; the shell owns the lifecycle
// (consuming abort on the throw path; abort or commit on the success path).
//
// modes: `.readOnly` and `.readWrite` (the ratified MDB_transact_mode pair).
// `.readWriteChild` is rejected: relationship composition is designed
// separately — Design-B joining already composes calls into ONE transaction.

internal struct MDB_transact_macro: BodyMacro, PeerMacro {

    // - MARK: attribute parsing

    private struct EnvSpec {
        let base: String   // calendarEnv -> derived name tx_calendarEnv
        let expr: String   // the argument as written, spliced into `Transaction(env: <expr>.env, ...)`
    }

    private struct ParsedMode {
        let envs: [EnvSpec]
        let isReadWrite: Bool
    }

    private enum Failure: Swift.Error, CustomStringConvertible {
        case notAFunction
        case noMode
        case childNotDesigned(String)
        case unknownMode(String)
        case noEnvironments
        case envNotName(String)

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
            case .noEnvironments:
                return "@MDB_transact requires at least one environment in `environments:`"
            case .envNotName(let expr):
                return "@MDB_transact cannot derive a transaction name from environment argument '\(expr)' — use a plain variable name"
            }
        }
    }

    /// base identifier of an environment argument: `calendarEnv` → "calendarEnv",
    /// `Demo.calendarEnv` → "calendarEnv"
    private static func baseName(of expression: ExprSyntax) -> String? {
        if let ref = expression.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    /// the variadic `environments:` flattens into the argument list and only
    /// the FIRST element keeps the label (verified in the spike). position is
    /// the anchor: index 0 = mode, everything after = an environment.
    private static func parse(_ node: AttributeSyntax) throws -> ParsedMode {
        guard let argList = node.arguments?.as(LabeledExprListSyntax.self), !argList.isEmpty else {
            throw Failure.noMode
        }
        var envs: [EnvSpec] = []
        var isReadWrite = false
        for (index, arg) in argList.enumerated() {
            if index == 0 {
                let modeText = arg.expression.trimmedDescription
                switch modeText {
                case ".readOnly", "MDB_transact_mode.readOnly":
                    isReadWrite = false
                case ".readWrite", "MDB_transact_mode.readWrite":
                    isReadWrite = true
                case ".readWriteChild", "MDB_transact_mode.readWriteChild":
                    throw Failure.childNotDesigned(modeText)
                default:
                    throw Failure.unknownMode(modeText)
                }
            } else {
                let exprText = arg.expression.trimmedDescription
                guard let base = baseName(of: arg.expression) else {
                    throw Failure.envNotName(exprText)
                }
                envs.append(EnvSpec(base: base, expr: exprText))
            }
        }
        guard !envs.isEmpty else { throw Failure.noEnvironments }
        return ParsedMode(envs: envs, isReadWrite: isReadWrite)
    }

    // - MARK: BodyMacro — the shell

    static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        guard let fn = declaration.as(FunctionDeclSyntax.self) else { throw Failure.notAFunction }
        let parsed = try parse(node)
        let envs = parsed.envs
        let isReadWrite = parsed.isReadWrite

        let params = fn.signature.parameterClause.parameters
        let name = fn.name.text
        let isThrowing = fn.signature.effectSpecifiers?.throwsClause != nil
        let retText = fn.signature.returnClause?.type.trimmedDescription

        // the shell's call into the wrapped sibling: the author's arguments by
        // their original labels, then one `tx_<E>: tx_<E>` per environment
        // (overload resolution selects the sibling — only it has these params)
        var callArgs: [String] = []
        for p in params {
            if p.firstName.text == "_" {
                callArgs.append(p.secondName?.text ?? "")
            } else if let second = p.secondName {
                callArgs.append("\(p.firstName.text): \(second.text)")
            } else {
                callArgs.append("\(p.firstName.text): \(p.firstName.text)")
            }
        }
        for e in envs { callArgs.append("tx_\(e.base): tx_\(e.base)") }
        let call = "\(name)(\(callArgs.joined(separator: ", ")))"
        // abort lines carry the SAME source indent as `throw error` below so
        // BasicFormat normalizes the whole catch block to one level
        let abortLines = envs.map { "    tx_\($0.base).abort()" }.joined(separator: "\n")

        var items: [CodeBlockItemSyntax] = []
        for e in envs {
            let readOnly = isReadWrite ? "false" : "true"
            items.append(CodeBlockItemSyntax(stringLiteral: "let tx_\(e.base) = try Transaction(env: \(e.expr).env, readOnly: \(readOnly))"))
        }

        if let retText {
            items.append(CodeBlockItemSyntax(stringLiteral: "let __mdb_output: \(retText)"))
            if isThrowing {
                items.append(CodeBlockItemSyntax(stringLiteral: """
                do {
                    __mdb_output = try \(call)
                } catch let error {
                \(abortLines)
                    throw error
                }
                """))
            } else {
                items.append(CodeBlockItemSyntax(stringLiteral: "__mdb_output = \(call)"))
            }
            // success path: readOnly aborts every tx; readWrite COMMITS every tx
            if isReadWrite {
                for e in envs { items.append(CodeBlockItemSyntax(stringLiteral: "try tx_\(e.base).commit()")) }
            } else {
                // one ITEM per abort: a joined multi-line string lets BasicFormat
                // re-indent the continuation lines differently from the first
                for e in envs { items.append(CodeBlockItemSyntax(stringLiteral: "tx_\(e.base).abort()")) }
            }
            items.append(CodeBlockItemSyntax(stringLiteral: "return __mdb_output"))
        } else {
            if isThrowing {
                items.append(CodeBlockItemSyntax(stringLiteral: """
                do {
                    try \(call)
                } catch let error {
                \(abortLines)
                    throw error
                }
                """))
            } else {
                items.append(CodeBlockItemSyntax(stringLiteral: call))
            }
            if isReadWrite {
                for e in envs { items.append(CodeBlockItemSyntax(stringLiteral: "try tx_\(e.base).commit()")) }
            } else {
                for e in envs { items.append(CodeBlockItemSyntax(stringLiteral: "tx_\(e.base).abort()")) }
            }
        }
        return items
    }

    // - MARK: PeerMacro — the wrapped sibling (the implementation)

    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let fn = declaration.as(FunctionDeclSyntax.self) else { throw Failure.notAFunction }
        // the BODY role is only invoked for functions, so for function-target
        // validation failures the body's single diagnostic already speaks —
        // this peer must not double-report. return no sibling silently.
        let parsed: ParsedMode
        do {
            parsed = try parse(node)
        } catch {
            return []
        }
        let envs = parsed.envs

        // the author's parameters + one `tx_<E>: borrowing Transaction` each.
        // `borrowing` is the v16-proven shape: the transaction flows in by
        // explicit borrow (never captured); the CALLER owns the lifecycle.
        var paramStrs: [String] = []
        for p in fn.signature.parameterClause.parameters {
            var s = p.trimmedDescription
            if s.hasSuffix(",") { s = String(s.dropLast()) }
            paramStrs.append(s)
        }
        for e in envs { paramStrs.append("tx_\(e.base): borrowing Transaction") }

        let modifiers = fn.modifiers.trimmedDescription
        let modifierPrefix = modifiers.isEmpty ? "" : modifiers + " "
        let name = fn.name.text
        var effects = ""
        if fn.signature.effectSpecifiers?.throwsClause != nil { effects += " throws" }
        let ret = fn.signature.returnClause.map { " \($0.trimmedDescription)" } ?? ""

        // scrape the author's body: lower the trailing verbs and consume every
        // #MDB_transacted(...) marker (Design B join)
        let body = fn.body?.statements ?? CodeBlockItemListSyntax([])
        let rewriter = SiblingRewriter(envs: envs)
        let rewritten = rewriter.visit(body)
        let bodyText = rewritten.map { $0.trimmedDescription }.joined(separator: "\n")

        let decl = "\(modifierPrefix)func \(name)(\(paramStrs.joined(separator: ", ")))\(effects)\(ret) {\n\(bodyText)\n}"
        return [DeclSyntax(stringLiteral: decl)]
    }

    // - MARK: the sibling-body rewriter

    private final class SiblingRewriter: SyntaxRewriter {
        let envs: [EnvSpec]

        init(envs: [EnvSpec]) {
            self.envs = envs
        }

        override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
            // children first, so a nested macro is processed before this node folds
            let processed = super.visit(node)
            let expansion = processed.cast(MacroExpansionExprSyntax.self)
            switch expansion.macroName.text {
            case "MDB_entry_load":
                return lowerQLoad(expansion) ?? ExprSyntax(expansion)
            case "MDB_entry_store":
                return lowerQStore(expansion) ?? ExprSyntax(expansion)
            case "MDB_transacted":
                return rewriteJoined(expansion) ?? ExprSyntax(expansion)
            default:
                return ExprSyntax(expansion)
            }
        }

        private func arg(_ node: MacroExpansionExprSyntax, _ label: String) -> LabeledExprSyntax? {
            node.arguments.first { $0.label?.text == label }
        }

        /// #MDB_entry_load(environment: E, database: D, key: K) -> D.load(key: K, tx: tx_<E>)
        private func lowerQLoad(_ node: MacroExpansionExprSyntax) -> ExprSyntax? {
            guard let env = arg(node, "environment"),
                  let db = arg(node, "database"),
                  let key = arg(node, "key"),
                  let base = MDB_transact_macro.baseName(of: env.expression) else { return nil }
            return ExprSyntax(stringLiteral:
                "\(db.expression.trimmedDescription).load(key: \(key.expression.trimmedDescription), tx: tx_\(base))")
        }

        /// #MDB_entry_store(environment: E, database: D, key: K, value: V) -> D.store(key: K, value: V, tx: tx_<E>)
        private func lowerQStore(_ node: MacroExpansionExprSyntax) -> ExprSyntax? {
            guard let env = arg(node, "environment"),
                  let db = arg(node, "database"),
                  let key = arg(node, "key"),
                  let value = arg(node, "value"),
                  let base = MDB_transact_macro.baseName(of: env.expression) else { return nil }
            return ExprSyntax(stringLiteral:
                "\(db.expression.trimmedDescription).store(key: \(key.expression.trimmedDescription), value: \(value.expression.trimmedDescription), tx: tx_\(base))")
        }

        /// #MDB_transacted(callee(args)) -> callee(args, tx_<E>: tx_<E>, ...)
        /// Design B: route into the callee's WRAPPED SIBLING with THIS
        /// boundary's transaction values. the callee's sibling must declare
        /// exactly these tx labels — the equal-env-set contract is enforced by
        /// the type checker (extra/missing argument at the call site).
        private func rewriteJoined(_ node: MacroExpansionExprSyntax) -> ExprSyntax? {
            guard let call = node.arguments.first?.expression.as(FunctionCallExprSyntax.self) else { return nil }
            var parts: [String] = []
            for argument in call.arguments {
                var s = argument.trimmedDescription
                if s.hasSuffix(",") { s = String(s.dropLast()) }
                parts.append(s)
            }
            for e in envs { parts.append("tx_\(e.base): tx_\(e.base)") }
            return ExprSyntax(stringLiteral:
                "\(call.calledExpression.trimmedDescription)(\(parts.joined(separator: ", ")))")
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

/// trailing read verb, standalone: no boundary to lower it.
internal struct MDB_entry_load_macro: ExpressionMacro {
    static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        context.diagnose(Diagnostic(
            node: Syntax(node),
            message: BoundaryDiagnostic(
                id: "MDB_entry_loadOutsideBoundary",
                text: "#MDB_entry_load must appear inside an @MDB_transact body — the boundary lowers it to the tx-bearing load"
            )
        ))
        return "nil"
    }
}

/// trailing write verb, standalone: no boundary to lower it.
internal struct MDB_entry_store_macro: ExpressionMacro {
    static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        context.diagnose(Diagnostic(
            node: Syntax(node),
            message: BoundaryDiagnostic(
                id: "MDB_entry_storeOutsideBoundary",
                text: "#MDB_entry_store must appear inside an @MDB_transact body — the boundary lowers it to the tx-bearing store"
            )
        ))
        return "nil"
    }
}
