import SwiftParser
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import QuickLMDBMacros

// expansion fixtures for the PROVISIONAL boundary (v16-iterated design — port
// phases 1 + 2): the frozen oracle migrated from the MDBTransactedDemo spike,
// adapted to the real engine (noncopyable Transaction, borrowing sibling
// params, throwing shape, mode-driven commit/abort tails).

private func assertExpansion(
	_ source: String,
	expanded expected: String,
	diagnostics: [DiagnosticSpec] = [],
	macros: [String: Macro.Type] = boundaryMacros
) {
	assertMacroExpansion(
		source,
		expandedSource: expected,
		diagnostics: diagnostics,
		macroSpecs: macros.mapValues { MacroSpec(type: $0) },
		failureHandler: { spec in Issue.record(Comment(stringLiteral: spec.message)) }
	)
}

private let boundaryMacros: [String: Macro.Type] = [
	"MDB_transact": MDB_transact_macro.self,
	"MDB_transacted": MDB_transacted_macro.self,
	"MDB_entry_load": MDB_entry_load_macro.self,
	"MDB_entry_store": MDB_entry_store_macro.self,
]

/// negative-path helper: runs the expansion and asserts the recorded
/// diagnostics' messages — avoids DiagnosticSpec line/column position drift.
private func assertBoundaryError(_ source: String, _ expectedDiags: [String]) {
	let file = Parser.parse(source: source)
	var contexts: [BasicMacroExpansionContext] = []
	_ = file.expand(macros: boundaryMacros, contextGenerator: { node in
		let ctx = BasicMacroExpansionContext()
		contexts.append(ctx)
		return ctx
	})
	let actual = contexts.flatMap { $0.diagnostics.map { $0.message } }
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

	@Test func MDB_entry_loadOutsideBoundaryIsADiagnostic() {
		assertExpansion(
			"""
			let v = #MDB_entry_load(environment: calendar, database: calendar.primary, key: key)
			""",
			expanded: """
			let v = nil
			""",
			diagnostics: [
				.init(
					message: "#MDB_entry_load must appear inside an @MDB_transact body — the boundary lowers it to the tx-bearing load",
					line: 1,
					column: 9
				)
			]
		)
	}

	@Test func MDB_entry_storeOutsideBoundaryIsADiagnostic() {
		assertExpansion(
			"""
			try #MDB_entry_store(environment: calendar, database: calendar.primary, key: key, value: value)
			""",
			expanded: """
			try nil
			""",
			diagnostics: [
				.init(
					message: "#MDB_entry_store must appear inside an @MDB_transact body — the boundary lowers it to the tx-bearing store",
					line: 1,
					column: 5
				)
			]
		)
	}
}

@Suite("MDB_transact — hardening (negative + edge paths)")
struct BoundaryHardeningExpansionTests {

	@Test func rejectsChildModeUntilDesigned() {
		// the ratified mode pair is (.readOnly, .readWrite); the CHILD mode is
		// relationship composition, designed separately — attempting it here
		// must fail LOUDLY at expansion time.
		assertBoundaryError(
			"""
			struct Core {
				static let calendar = LeafCore()
				@MDB_transact(.readWriteChild, environments: calendar)
				static func store(_ key: Key) throws {
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
				static let calendar = LeafCore()
				@MDB_transact(.readWhatever, environments: calendar)
				static func store(_ key: Key) throws {
				}
			}
			""",
			["@MDB_transact: unknown mode '.readWhatever' — expected .readOnly or .readWrite"]
		)
	}

	@Test func requiresAtLeastOneEnvironment() {
		assertBoundaryError(
			"""
			struct Core {
				@MDB_transact(.readOnly)
				static func read(_ key: Key) throws -> Value? {
					return nil
				}
			}
			""",
			["@MDB_transact requires at least one environment in `environments:`"]
		)
	}

	@Test func rejectsNonFunctionTargets() {
		assertBoundaryError(
			"""
			@MDB_transact(.readOnly, environments: calendar)
			struct NotAFunction {
			}
			""",
			["@MDB_transact can only be applied to a function"]
		)
	}

	@Test func rejectsNonNameEnvironmentArguments() {
		assertBoundaryError(
			"""
			struct Core {
				static func makeCore() -> LeafCore { LeafCore() }
				@MDB_transact(.readOnly, environments: makeCore())
				static func read(_ key: Key) throws -> Value? {
					return nil
				}
			}
			""",
			["@MDB_transact cannot derive a transaction name from environment argument 'makeCore()' — use a plain variable name"]
		)
	}

	@Test func nonThrowingBoundaryShellSkipsDoCatch() {
		// non-throwing wrapped functions get the plain shell: open, call the
		// sibling, abort, return — no do/catch scaffolding.
		assertExpansion(
			"""
			struct Core {
				static let calendar = LeafCore()
				@MDB_transact(.readOnly, environments: calendar)
				static func readCal(_ key: Key) -> Value? {
					#MDB_entry_load(environment: calendar, database: calendar.primary, key: key)
				}
			}
			""",
			expanded: """
			struct Core {
			\tstatic let calendar = LeafCore()
			\tstatic func readCal(_ key: Key) -> Value? {
			\t    let tx_calendar = try Transaction(env: calendar.env, readOnly: true)
			\t    let __mdb_output: Value?
			\t    __mdb_output = readCal(key, tx_calendar: tx_calendar)
			\t    tx_calendar.abort()
			\t    return __mdb_output
			\t}

			\tstatic func readCal(_ key: Key, tx_calendar: borrowing Transaction) -> Value? {
			\t    calendar.primary.load(key: key, tx: tx_calendar)
			\t}
			}
			"""
		)
	}
}

@Suite("MDB_transact — shell + wrapped sibling (real engine)")
struct BoundaryExpansionTests {

	@Test func readCalShellAndSibling() {
		assertExpansion(
			"""
			struct Core {
				static let calendar = LeafCore()
				@MDB_transact(.readOnly, environments: calendar)
				static func readCal(_ key: Key) throws -> Value? {
					#MDB_entry_load(environment: calendar, database: calendar.primary, key: key)
				}
			}
			""",
			expanded: """
			struct Core {
			\tstatic let calendar = LeafCore()
			\tstatic func readCal(_ key: Key) throws -> Value? {
			\t    let tx_calendar = try Transaction(env: calendar.env, readOnly: true)
			\t    let __mdb_output: Value?
			\t    do {
			\t        __mdb_output = try readCal(key, tx_calendar: tx_calendar)
			\t    } catch let error {
			\t        tx_calendar.abort()
			\t        throw error
			\t    }
			\t    tx_calendar.abort()
			\t    return __mdb_output
			\t}

			\tstatic func readCal(_ key: Key, tx_calendar: borrowing Transaction) throws -> Value? {
			\t    calendar.primary.load(key: key, tx: tx_calendar)
			\t}
			}
			"""
		)
	}

	@Test func designBJoinedRewriteInsideTheSibling() {
		assertExpansion(
			"""
			struct Core {
				static let calendar = LeafCore()
				@MDB_transact(.readOnly, environments: calendar)
				static func overview(_ key: Key) throws -> (Value?, Value?) {
					let a = try #MDB_transacted(readCal(key))
					let b = try #MDB_transacted(readCal(key))
					return (a, b)
				}
			}
			""",
			expanded: """
			struct Core {
			\tstatic let calendar = LeafCore()
			\tstatic func overview(_ key: Key) throws -> (Value?, Value?) {
			\t    let tx_calendar = try Transaction(env: calendar.env, readOnly: true)
			\t    let __mdb_output: (Value?, Value?)
			\t    do {
			\t        __mdb_output = try overview(key, tx_calendar: tx_calendar)
			\t    } catch let error {
			\t        tx_calendar.abort()
			\t        throw error
			\t    }
			\t    tx_calendar.abort()
			\t    return __mdb_output
			\t}

			\tstatic func overview(_ key: Key, tx_calendar: borrowing Transaction) throws -> (Value?, Value?) {
			\t    let a = try readCal(key, tx_calendar: tx_calendar)
			\t    let b = try readCal(key, tx_calendar: tx_calendar)
			\t    return (a, b)
			\t}
			}
			"""
		)
	}

	@Test func equalEnvSetContractEmitsBothLabels() {
		// the documented Design-B contract: a two-env caller rewrites
		// #MDB_transacted into a call passing BOTH tx labels — the callee
		// sibling must declare exactly those, or the type checker reports a
		// missing/extra argument at this site.
		assertExpansion(
			"""
			struct Core {
				static let calendar = LeafCore()
				static let contacts = LeafCore()
				@MDB_transact(.readOnly, environments: calendar, contacts)
				static func overview(_ key: Key) throws -> Value? {
					#MDB_transacted(readCal(key))
				}
			}
			""",
			expanded: """
			struct Core {
			\tstatic let calendar = LeafCore()
			\tstatic let contacts = LeafCore()
			\tstatic func overview(_ key: Key) throws -> Value? {
			\t    let tx_calendar = try Transaction(env: calendar.env, readOnly: true)
			\t    let tx_contacts = try Transaction(env: contacts.env, readOnly: true)
			\t    let __mdb_output: Value?
			\t    do {
			\t        __mdb_output = try overview(key, tx_calendar: tx_calendar, tx_contacts: tx_contacts)
			\t    } catch let error {
			\t        tx_calendar.abort()
			\t        tx_contacts.abort()
			\t        throw error
			\t    }
			\t    tx_calendar.abort()
			\t    tx_contacts.abort()
			\t    return __mdb_output
			\t}

			\tstatic func overview(_ key: Key, tx_calendar: borrowing Transaction, tx_contacts: borrowing Transaction) throws -> Value? {
			\t    readCal(key, tx_calendar: tx_calendar, tx_contacts: tx_contacts)
			\t}
			}
			"""
		)
	}
}

@Suite("MDB_transact — write mode (.readWrite)")
struct WriteBoundaryExpansionTests {

	@Test func readWriteShellCommitsOnSuccess() {
		// the .readWrite shell: open readOnly:false, abort on throw, COMMIT on
		// success — the only structural difference from the readOnly shell.
		assertExpansion(
			"""
			struct Core {
				static let calendar = LeafCore()
				@MDB_transact(.readWrite, environments: calendar)
				static func writeCal(_ key: Key, _ value: Value) throws {
					try #MDB_entry_store(environment: calendar, database: calendar.primary, key: key, value: value)
				}
			}
			""",
			expanded: """
			struct Core {
				static let calendar = LeafCore()
				static func writeCal(_ key: Key, _ value: Value) throws {
				    let tx_calendar = try Transaction(env: calendar.env, readOnly: false)
				    do {
				        try writeCal(key, value, tx_calendar: tx_calendar)
				    } catch let error {
				        tx_calendar.abort()
				        throw error
				    }
				    try tx_calendar.commit()
				}

				static func writeCal(_ key: Key, _ value: Value, tx_calendar: borrowing Transaction) throws {
				    try calendar.primary.store(key: key, value: value, tx: tx_calendar)
				}
			}
			"""
		)
	}

	@Test func joinedWriteComposesIntoTheSingleTransaction() {
		// Design-B joining in the write side: the marked call becomes
		// writeCal(key2, value2, tx_calendar:) — the joined write runs on THIS
		// boundary's transaction, atomic by construction.
		assertExpansion(
			"""
			struct Core {
				static let calendar = LeafCore()
				@MDB_transact(.readWrite, environments: calendar)
				static func writePair(_ key1: Key, _ value1: Value, _ key2: Key, _ value2: Value) throws {
					try #MDB_entry_store(environment: calendar, database: calendar.primary, key: key1, value: value1)
					try #MDB_transacted(writeCal(key2, value2))
				}
			}
			""",
			expanded: """
			struct Core {
			\tstatic let calendar = LeafCore()
			\tstatic func writePair(_ key1: Key, _ value1: Value, _ key2: Key, _ value2: Value) throws {
			\t    let tx_calendar = try Transaction(env: calendar.env, readOnly: false)
			\t    do {
			\t        try writePair(key1, value1, key2, value2, tx_calendar: tx_calendar)
			\t    } catch let error {
			\t        tx_calendar.abort()
			\t        throw error
			\t    }
			\t    try tx_calendar.commit()
			\t}

			\tstatic func writePair(_ key1: Key, _ value1: Value, _ key2: Key, _ value2: Value, tx_calendar: borrowing Transaction) throws {
			\t    try calendar.primary.store(key: key1, value: value1, tx: tx_calendar)
			\t    try writeCal(key2, value2, tx_calendar: tx_calendar)
			\t}
			}
			"""
		)
	}
}
