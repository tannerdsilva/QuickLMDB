import SwiftParser
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
import Foundation
@testable import QuickLMDBMacros

// expansion fixtures for the typed-environment boundary dialect:
//   @MDB_transact(_ mode:) — instance methods (struct OR extension of a core),
//   environments inferred from the typed verb calls inside the body; the method
//   becomes a SHELL (opens/closes its own transactions) and the peer emits the
//   INVISIBLE SIBLING that carries the tx parameters. the authored surface has
//   no transaction vocabulary whatsoever.

private let boundaryMacros: [String: Macro.Type] = [
	"MDB_transact": MDB_transact_macro.self,
	"MDB_transacted": MDB_transacted_macro.self,
	"store": MDB_verb_error_macro.self,
	"load": MDB_verb_error_macro.self,
	"delete": MDB_verb_error_macro.self,
	"contains": MDB_verb_error_macro.self,
	"cursor": MDB_verb_error_macro.self,
	"clear": MDB_verb_error_macro.self,
	"stats": MDB_verb_error_macro.self,
	"drop": MDB_verb_error_macro.self,
]

private func assertExpansion(
	_ source: String,
	expanded expected: String,
	diagnostics: [DiagnosticSpec] = []
) {
	assertMacroExpansion(
		source,
		expandedSource: expected,
		diagnostics: diagnostics,
		macroSpecs: boundaryMacros.mapValues { MacroSpec(type: $0) },
		failureHandler: { spec in Issue.record(Comment(stringLiteral: spec.message)) }
	)
}

/// negative-path helper: collects diagnostics by message (immune to position
/// drift). the standalone verb fallback diagnoses too (a body containing a
/// verb also visits the verb node as a freestanding expansion) — those
/// verbOutsideBoundary messages are filtered so the boundary's own diagnostic
/// is the one asserted.
private func assertBoundaryError(_ source: String, _ expectedDiags: [String]) {
	let file = Parser.parse(source: source)
	var contexts: [BasicMacroExpansionContext] = []
	_ = file.expand(macros: boundaryMacros, contextGenerator: { node in
		let ctx = BasicMacroExpansionContext()
		contexts.append(ctx)
		return ctx
	})
	let actual = contexts.flatMap { $0.diagnostics }
		.filter { !$0.message.contains("must appear inside an @MDB_transact body") }
		.map { $0.message }
	#expect(actual == expectedDiags, Comment(stringLiteral: "diagnostics mismatch: \(actual)"))
}


@Suite("MDB_transact — standalone marker + verbs")
struct BoundaryStandaloneExpansionTests {

	@Test func transactedOutsideBoundaryIsADiagnostic() {
		assertExpansion(
			"""
			let a = #MDB_transacted(readCal(key))
			""",
			expanded: """
			let a = nil
			""",
			diagnostics: [
				.init(
					message: "#MDB_transacted must appear inside an @MDB_transact body — the boundary rewrites it to join its transactions",
					line: 1,
					column: 9
				)
			]
		)
	}

	@Test func storeOutsideBoundaryIsADiagnostic() {
		assertExpansion(
			"""
			let v = #store(Core.self, database: \\.primary, key: key, value: value)
			""",
			expanded: """
			let v = nil
			""",
			diagnostics: [
				.init(
					message: "#store must appear inside an @MDB_transact body — the boundary lowers it to the tx-bearing operation",
					line: 1,
					column: 9
				)
			]
		)
	}

	@Test func loadOutsideBoundaryIsADiagnostic() {
		assertExpansion(
			"""
			let v = #load(Core.self, database: \\.primary, key: key)
			""",
			expanded: """
			let v = nil
			""",
			diagnostics: [
				.init(
					message: "#load must appear inside an @MDB_transact body — the boundary lowers it to the tx-bearing operation",
					line: 1,
					column: 9
				)
			]
		)
	}
}

@Suite("MDB_transact — hardening (negative + edge paths)")
struct BoundaryHardeningExpansionTests {

	@Test func rejectsChildModeUntilDesigned() {
		assertBoundaryError(
			"""
			struct Core {
			    @MDB_transact(.readWriteChild)
			    func store(_ key: Key, _ value: Value) throws {
			    }
			}
			""",
			["@MDB_transact cannot accept '.readWriteChild': relationship (child) composition is designed separately — Design-B #MDB_transacted joining already composes calls into one transaction"]
		)
	}

	@Test func rejectsUnknownModes() {
		assertBoundaryError(
			"""
			struct Core {
			    @MDB_transact(.readWhatever)
			    func store(_ key: Key, _ value: Value) throws {
			    }
			}
			""",
			["@MDB_transact: unknown mode '.readWhatever' — expected .readOnly or .readWrite"]
		)
	}

	@Test func requiresThrows() {
		assertBoundaryError(
			"""
			struct Core {
			    @MDB_transact(.readOnly)
			    func read(_ key: Key) -> Value? {
			        #load(Core.self, database: \\.primary, key: key)
			    }
			}
			""",
			["@MDB_transact requires the method to be marked `throws` — the boundary can fail to open, commit, or abort"]
		)
	}

	@Test func rejectsTypedThrows() {
		assertBoundaryError(
			"""
			struct Core {
			    @MDB_transact(.readOnly)
			    func read(_ key: Key) throws(SomeError) -> Value? {
			        #load(Core.self, database: \\.primary, key: key)
			    }
			}
			""",
			["@MDB_transact requires an untyped `throws` — the boundary rethrows the body's error, so a typed throws clause cannot be represented"]
		)
	}

	@Test func rejectsStaticMethods() {
		assertBoundaryError(
			"""
			struct Core {
			    @MDB_transact(.readOnly)
			    static func read(_ key: Key) throws -> Value? {
			        #load(Core.self, database: \\.primary, key: key)
			    }
			}
			""",
			["@MDB_transact methods must be INSTANCE methods — the environments are `self` and typed parameters of the same type"]
		)
	}

	@Test func rejectsBodiesWithNoVerbs() {
		assertBoundaryError(
			"""
			struct Core {
			    @MDB_transact(.readWrite)
			    func nothing() throws {
			    }
			}
			""",
			["@MDB_transact body has no database verbs (#store/#load/#delete/#contains/#cursor/#clear/#stats/#drop) — the boundary's environments are inferred from the verbs. a boundary cannot be a pure coordinator — it owns the environments it operates on"]
		)
	}

	@Test func rejectsUnknownEnvironmentInstances() {
		// the seeded context has an empty lexicalContext, so even the enclosing
		// type is unresolvable here — the FIRST environment in first-appearance
		// order is the one reported
		assertBoundaryError(
			"""
			struct Core {
			    @MDB_transact(.readWrite)
			    func sync(_ k: Key, _ v: Value, other: OtherCore) throws {
			        try #store(Core.self, database: \\.primary, key: k, value: v)
			        try #store(OtherCore.self, database: \\.secondary, key: k, value: v)
			    }
			}
			""",
			["@MDB_transact: no instance of environment type 'Core' is in scope — attach the boundary to 'Core' itself, or add a parameter of type 'Core'. a boundary owns the environments it OPERATES on — it cannot be a pure coordinator"]
		)
	}

	@Test func rejectsAmbiguousEnvironmentInstances() {
		// two instances of one environment type cannot be addressed by the
		// typed verbs — a real diagnostic, never silent first-param binding
		assertBoundaryError(
			"""
			struct Core {
			    let env: Environment
			    @MDB_transact(.readWrite)
			    func sync(_ k: Key, _ v: Value, a: OtherCore, b: OtherCore) throws {
			        try #store(OtherCore.self, database: \\.secondary, key: k, value: v)
			    }
			}
			struct OtherCore {
			    let env: Environment
			    let secondary: Database.Strict<Key, Value>
			}
			""",
			["@MDB_transact: more than one instance of environment type 'OtherCore' is in scope (self + a parameter, or two parameters) — the typed verbs can only address ONE instance per environment type; split the boundary or use the raw `Transaction` surface for the second"]
		)
	}

	// NOTE: the mustBeOnCore attachment validation has no seeded oracle — the
	// seeded expand context exposes an EMPTY lexicalContext, so the enclosing
	// struct (and its `env` property) is invisible and the check cannot fire
	// there; it is enforced in real compiles.

	@Test func readBoundaryShellAndSibling() {
		assertExpansion(
			"""
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			    @MDB_transact(.readOnly)
			    func readCal(_ key: Key) throws -> Value? {
			        #load(Core.self, database: \\.primary, key: key)
			    }
			}
			""",
			expanded: """
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			    func readCal(_ key: Key) throws -> Value? {
			        let tx_Core = try Transaction<Read>(env: self.env)
			        let __mdb_output: Value?
			        do {
			            __mdb_output = try self.readCal(key, tx_Core: tx_Core)
			        } catch let error {
			            tx_Core.abort()
			            throw error
			        }
			        tx_Core.abort()
			        return __mdb_output
			    }

			    func readCal<M: TransactionMode>(_ key: Key, tx_Core: borrowing Transaction<M>) throws -> Value? {
			        self[keyPath: \\.primary].load(key: key, tx: tx_Core)
			    }
			}
			"""
		)
	}

	@Test func writeBoundaryShellCommitsAndSiblingWrites() {
		assertExpansion(
			"""
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			    @MDB_transact(.readWrite)
			    func writeCal(_ key: Key, _ value: Value) throws {
			        try #store(Core.self, database: \\.primary, key: key, value: value)
			    }
			}
			""",
			expanded: """
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			    func writeCal(_ key: Key, _ value: Value) throws {
			        let tx_Core = try Transaction<Write>(env: self.env)
			        do {
			            try self.writeCal(key, value, tx_Core: tx_Core)
			        } catch let error {
			            tx_Core.abort()
			            throw error
			        }
			        try tx_Core.commit()
			    }

			    func writeCal(_ key: Key, _ value: Value, tx_Core: borrowing Transaction<Write>) throws {
			        try self[keyPath: \\.primary].store(key: key, value: value, tx: tx_Core)
			    }
			}
			"""
		)
	}

	@Test func designBJoinRewritesInsideTheSibling() {
		assertExpansion(
			"""
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			    @MDB_transact(.readOnly)
			    func overview(_ key: Key) throws -> (Value?, Value?) {
			        let a = try #MDB_transacted(readCal(key))
			        let b = #load(Core.self, database: \\.primary, key: key)
			        return (a, b)
			    }
			    @MDB_transact(.readOnly)
			    func readCal(_ key: Key) throws -> Value? {
			        #load(Core.self, database: \\.primary, key: key)
			    }
			}
			""",
			expanded: """
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			    func overview(_ key: Key) throws -> (Value?, Value?) {
			        let tx_Core = try Transaction<Read>(env: self.env)
			        let __mdb_output: (Value?, Value?)
			        do {
			            __mdb_output = try self.overview(key, tx_Core: tx_Core)
			        } catch let error {
			            tx_Core.abort()
			            throw error
			        }
			        tx_Core.abort()
			        return __mdb_output
			    }

			    func overview<M: TransactionMode>(_ key: Key, tx_Core: borrowing Transaction<M>) throws -> (Value?, Value?) {
			        let a = try self.readCal(key, tx_Core: tx_Core)
			        let b = self[keyPath: \\.primary].load(key: key, tx: tx_Core)
			        return (a, b)
			    }
			    func readCal(_ key: Key) throws -> Value? {
			        let tx_Core = try Transaction<Read>(env: self.env)
			        let __mdb_output: Value?
			        do {
			            __mdb_output = try self.readCal(key, tx_Core: tx_Core)
			        } catch let error {
			            tx_Core.abort()
			            throw error
			        }
			        tx_Core.abort()
			        return __mdb_output
			    }

			    func readCal<M: TransactionMode>(_ key: Key, tx_Core: borrowing Transaction<M>) throws -> Value? {
			        self[keyPath: \\.primary].load(key: key, tx: tx_Core)
			    }
			}
			"""
		)
	}

	@Test func multiEnvironmentBoundaryResolvesTypedParameters() {
		assertExpansion(
			"""
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			    @MDB_transact(.readWrite)
			    func sync(_ k: Key, _ v: Value, other: OtherCore) throws {
			        try #store(Core.self, database: \\.primary, key: k, value: v)
			        try #store(OtherCore.self, database: \\.secondary, key: k, value: v)
			    }
			}
			struct OtherCore {
			    let env: Environment
			    let secondary: Database.Strict<Key, Value>
			}
			""",
			expanded: """
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			    func sync(_ k: Key, _ v: Value, other: OtherCore) throws {
			        let tx_Core = try Transaction<Write>(env: self.env)
			        let tx_OtherCore = try Transaction<Write>(env: other.env)
			        do {
			            try self.sync(k, v, other: other, tx_Core: tx_Core, tx_OtherCore: tx_OtherCore)
			        } catch let error {
			            tx_Core.abort()
			            tx_OtherCore.abort()
			            throw error
			        }
			        try tx_Core.commit()
			        try tx_OtherCore.commit()
			    }

			    func sync(_ k: Key, _ v: Value, other: OtherCore, tx_Core: borrowing Transaction<Write>, tx_OtherCore: borrowing Transaction<Write>) throws {
			        try self[keyPath: \\.primary].store(key: k, value: v, tx: tx_Core)
			        try other[keyPath: \\.secondary].store(key: k, value: v, tx: tx_OtherCore)
			    }
			}
			struct OtherCore {
			    let env: Environment
			    let secondary: Database.Strict<Key, Value>
			}
			"""
		)
	}

	@Test func boundaryInExtensionOfACore() {
		// the README flagship multi-env pattern: boundaries on an EXTENSION of
		// the core — self still resolves (the extended type), so the environment
		// set infers and the shell/sibling emit
		assertExpansion(
			"""
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			}
			extension Core {
			    @MDB_transact(.readOnly)
			    func readCal(_ key: Key) throws -> Value? {
			        #load(Core.self, database: \\.primary, key: key)
			    }
			}
			""",
			expanded: """
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			}
			extension Core {
			    func readCal(_ key: Key) throws -> Value? {
			        let tx_Core = try Transaction<Read>(env: self.env)
			        let __mdb_output: Value?
			        do {
			            __mdb_output = try self.readCal(key, tx_Core: tx_Core)
			        } catch let error {
			            tx_Core.abort()
			            throw error
			        }
			        tx_Core.abort()
			        return __mdb_output
			    }

			    func readCal<M: TransactionMode>(_ key: Key, tx_Core: borrowing Transaction<M>) throws -> Value? {
			        self[keyPath: \\.primary].load(key: key, tx: tx_Core)
			    }
			}
			"""
		)
	}

	@Test func joinPreservesAnInnerTrailingClosure() {
		assertExpansion(
			"""
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			    @MDB_transact(.readOnly)
			    func overview(_ key: Key) throws -> Value? {
			        let x = try #MDB_transacted(cursorRead(key) { _ in })
			        let y = #load(Core.self, database: \\.primary, key: key)
			        return y
			    }
			    @MDB_transact(.readOnly)
			    func cursorRead(_ key: Key) throws -> Value? {
			        #load(Core.self, database: \\.primary, key: key)
			    }
			}
			""",
			expanded: """
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			    func overview(_ key: Key) throws -> Value? {
			        let tx_Core = try Transaction<Read>(env: self.env)
			        let __mdb_output: Value?
			        do {
			            __mdb_output = try self.overview(key, tx_Core: tx_Core)
			        } catch let error {
			            tx_Core.abort()
			            throw error
			        }
			        tx_Core.abort()
			        return __mdb_output
			    }

			    func overview<M: TransactionMode>(_ key: Key, tx_Core: borrowing Transaction<M>) throws -> Value? {
			        let x = try self.cursorRead(key, tx_Core: tx_Core) { _ in
			        }
			        let y = self[keyPath: \\.primary].load(key: key, tx: tx_Core)
			        return y
			    }
			    func cursorRead(_ key: Key) throws -> Value? {
			        let tx_Core = try Transaction<Read>(env: self.env)
			        let __mdb_output: Value?
			        do {
			            __mdb_output = try self.cursorRead(key, tx_Core: tx_Core)
			        } catch let error {
			            tx_Core.abort()
			            throw error
			        }
			        tx_Core.abort()
			        return __mdb_output
			    }

			    func cursorRead<M: TransactionMode>(_ key: Key, tx_Core: borrowing Transaction<M>) throws -> Value? {
			        self[keyPath: \\.primary].load(key: key, tx: tx_Core)
			    }
			}
			"""
		)
	}
}
	@Test func guardWithVerbPredicateKeepsOperatorSpacing() {
		assertExpansion(
			"""
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			    @discardableResult
			    @MDB_transact(.readWrite)
			    func domainMake(name: Key, subnet: Key) throws {
				guard try #contains(Core.self, database: \\.primary, key: subnet) == false else { throw TestError.bad }
			    }
			}
			""",
			expanded: """
			struct Core {
			    let env: Environment
			    let primary: Database.Strict<Key, Value>
			    @discardableResult
			    func domainMake(name: Key, subnet: Key) throws {
			        let tx_Core = try Transaction<Write>(env: self.env)
			        do {
			            try self.domainMake(name: name, subnet: subnet, tx_Core: tx_Core)
			        } catch let error {
			            tx_Core.abort()
			            throw error
			        }
			        try tx_Core.commit()
			    }
			
			    @discardableResult func domainMake(name: Key, subnet: Key, tx_Core: borrowing Transaction<Write>) throws {
			        guard try self[keyPath: \\.primary].contains(key: subnet, tx: tx_Core) == false else {
			            throw TestError.bad
			        }
			    }
			}
			"""
		)
	}
