import Testing
import Foundation
import QuickLMDB
import RAW

// runtime pins for the multi-environment boundary relationships that no
// consumer exercised (DEBT item 1): a boundary whose verbs address TWO
// environment types, and a `#MDB_transacted` join of a MULTI-env sibling
// (the equal-env-set contract — the joining boundary must reference the SAME
// environment-type set as the callee, enforced at compile time by the
// rewrite's label threading).

@MDB_environment(file: "ledger-a.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct LedgerA: Sendable {
	public let env: Environment
	public let entries: Database.Strict<TestKey, TestValue>
}

@MDB_environment(file: "ledger-b.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct LedgerB: Sendable {
	public let env: Environment
	public let entries: Database.Strict<TestKey, TestValue>
}

extension LedgerB {

	// MULTI-ENV boundary: self (LedgerB) writes first, then mirrors into the
	// LedgerA parameter. its environment set is {LedgerB, LedgerA} — the
	// shell opens BOTH transactions and commits/aborts them together.
	@MDB_transact(.readWrite)
	func writePair(_ key: TestKey, _ value: TestValue, mirrorTo other: LedgerA, failBeforeMirror: Bool) throws {
		try #store(LedgerB.self, database: \.entries, key: key, value: value)
		if failBeforeMirror { throw TestError.simulatedFailure }
		try #store(LedgerA.self, database: \.entries, key: key, value: value)
	}

	// MULTI-ENV joined READ: reads B's entry and A's entry through ONE
	// transaction set (one snapshot across both environments).
	@MDB_transact(.readOnly)
	func readPair(_ key: TestKey, from other: LedgerA) throws -> (TestValue?, TestValue?) {
		let b = #load(LedgerB.self, database: \.entries, key: key)
		let a = #load(LedgerA.self, database: \.entries, key: key)
		return (b, a)
	}
}

extension LedgerA {

	// MULTI-ENV boundary + CROSS-ENV JOIN: verbs reference LedgerA (self) and
	// LedgerB (the parameter) — the equal-environment-type-set of the joined
	// writePair sibling. the join threads BOTH transactions through it, so
	// the composed write is ONE atomic set across the two environments.
	@MDB_transact(.readWrite)
	func crossWrite(_ key: TestKey, _ value: TestValue, to other: LedgerB, failBeforeMirror: Bool) throws {
		try #store(LedgerA.self, database: \.entries, key: key, value: value)
		// LedgerB is referenced by a verb so it joins the environment set;
		// the actual LedgerB write happens inside the joined callee.
		_ = try #contains(LedgerB.self, database: \.entries, key: key)
		try #MDB_transacted(other.writePair(key, value, mirrorTo: self, failBeforeMirror: failBeforeMirror))
	}

	// a write boundary that JOINS a multi-env read sibling: the joined read
	// must observe THIS boundary's uncommitted write (Design-B semantics
	// across two environments).
	@MDB_transact(.readWrite)
	func storeAndVerify(_ key: TestKey, _ value: TestValue, to other: LedgerB) throws -> Bool {
		try #store(LedgerA.self, database: \.entries, key: key, value: value)
		_ = try #contains(LedgerB.self, database: \.entries, key: key)
		let (b, a) = try #MDB_transacted(other.readPair(key, from: self))
		return b == nil && a == value
	}

	// the multi-env shell's COMMIT path without a join: both environments
	// committed, both readable.
	@MDB_transact(.readWrite)
	func writeBoth(_ key: TestKey, _ value: TestValue, to other: LedgerB) throws {
		try #store(LedgerA.self, database: \.entries, key: key, value: value)
		try #store(LedgerB.self, database: \.entries, key: key, value: value)
	}

	// the multi-env shell's ABORT path: the failure aborts EVERY transaction
	// in the set — a mid-boundary throw leaves both environments untouched.
	@MDB_transact(.readWrite)
	func writeBothFailing(_ key: TestKey, _ value: TestValue, to other: LedgerB) throws {
		try #store(LedgerA.self, database: \.entries, key: key, value: value)
		try #store(LedgerB.self, database: \.entries, key: key, value: value)
		throw TestError.simulatedFailure
	}
}

@Suite("multi-environment atomic boundary + cross-env join")
struct MultiEnvironmentAtomicityTests {

	private func freshPair() throws -> (LedgerA, LedgerB) {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-multienv-\(UUID().uuidString)", isDirectory: true)
		let a = try LedgerA.open(at: root.appendingPathComponent("a").path)
		let b = try LedgerB.open(at: root.appendingPathComponent("b").path)
		return (a, b)
	}

	@Test func multiEnvShellCommitsBothEnvironments() throws {
		let (a, b) = try freshPair()
		let key = TestKey(RAW_native: 1)
		let value = TestValue(RAW_native: 100)
		try a.writeBoth(key, value, to: b)
		#expect(try a.entries.readCommitted(key: key) == value)
		#expect(try b.entries.readCommitted(key: key) == value)
	}

	@Test func multiEnvShellAbortLeavesBothEnvironmentsUntouched() throws {
		let (a, b) = try freshPair()
		let key = TestKey(RAW_native: 2)
		let value = TestValue(RAW_native: 200)
		#expect(throws: TestError.self) {
			try a.writeBothFailing(key, value, to: b)
		}
		// the mid-boundary failure aborted BOTH write transactions — neither
		// environment saw any part of the write set
		#expect(try a.entries.readCommitted(key: key) == nil)
		#expect(try b.entries.readCommitted(key: key) == nil)
	}

	@Test func crossEnvJoinIsAtomicAcrossBothEnvironments() throws {
		let (a, b) = try freshPair()
		let key = TestKey(RAW_native: 3)
		let value = TestValue(RAW_native: 300)

		// success: ONE atomic set across {LedgerA, LedgerB}
		try a.crossWrite(key, value, to: b, failBeforeMirror: false)
		#expect(try a.entries.readCommitted(key: key) == value)
		#expect(try b.entries.readCommitted(key: key) == value)

		// failure inside the JOINED callee: the outer boundary aborts both
		// transactions — the LedgerA store (from the outer body) and the
		// LedgerB store + LedgerA mirror (from the joined sibling) all roll
		// back as one unit
		let key2 = TestKey(RAW_native: 4)
		#expect(throws: TestError.self) {
			try a.crossWrite(key2, value, to: b, failBeforeMirror: true)
		}
		#expect(try a.entries.readCommitted(key: key2) == nil)
		#expect(try b.entries.readCommitted(key: key2) == nil)
	}

	@Test func joinedReadSeesUncommittedStateAcrossEnvironments() throws {
		let (a, b) = try freshPair()
		let key = TestKey(RAW_native: 5)
		let value = TestValue(RAW_native: 500)

		// the joined multi-env read runs inside THIS boundary's transaction
		// set, so it sees the uncommitted LedgerA write (a SIBLING read would
		// open a fresh committed-only transaction and see nil)
		let seen = try a.storeAndVerify(key, value, to: b)
		#expect(seen)
		#expect(try a.entries.readCommitted(key: key) == value)
	}
}
