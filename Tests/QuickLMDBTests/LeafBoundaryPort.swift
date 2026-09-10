import Testing
import Foundation
import QuickLMDB

// PROVISIONAL leaf-dialect port slice (v16-iterated design — phase 1 of the
// port): the ratified Design-B stack on the REAL engine — noncopyable
// Transaction, @MDB_environment cores, #MDB_transacted joined calls, all
// through the real mmap'd databases.
//
// the boundary methods live on a container whose environment cores are
// STATIC stored properties: the macro's `environments:` attribute arguments
// are evaluated at TYPE scope (instance stored properties are not in scope
// there — the wall the spike verified), so the cores must be
// attribute-reachable.

enum LeafPortPaths {
	static let root = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-leafport", isDirectory: true)
	static let leafDir = root.appendingPathComponent("leaf", isDirectory: true)

	static func prepare() {
		try? FileManager.default.removeItem(at: root)
	}
}

@MDB_environment(file: "leaf.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct LeafPortCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
}

enum LeafPortDemo {
	// attribute-reachable static core; the env opens once through a
	// non-throwing factory closure (static initializers cannot throw)
	static let leafCore: LeafPortCore = {
		LeafPortPaths.prepare()
		return try! LeafPortCore.open(at: LeafPortPaths.leafDir.path)
	}()

	// the callee — a readOnly leaf over leafCore
	@MDB_transact(.readOnly, environments: leafCore)
	static func readCal(_ key: TestKey) throws -> TestValue? {
		#MDB_entry_load(environment: leafCore, database: leafCore.primary, key: key)
	}

	// Design B — the boundary CONSUMES the markers and rewrites each
	// #MDB_transacted(readCal(key)) into readCal(key, tx_leafCore:) so both
	// reads JOIN this boundary's transaction. mid-boundary a raw SIBLING
	// WRITE commits a new value (write-inside-read is a legal sibling write);
	// the joined reads must still see the boundary's snapshot from open.
	@MDB_transact(.readOnly, environments: leafCore)
	static func joinedOverview(_ key: TestKey) throws -> (TestValue?, TestValue?) {
		let a = try #MDB_transacted(readCal(key))
		let wtx = try Transaction(env: leafCore.env, readOnly: false)
		try leafCore.primary.setEntry(key: key, value: TestValue(RAW_native: 2), flags: [], tx: wtx)
		try wtx.commit()
		let b = try #MDB_transacted(readCal(key))
		return (a, b)
	}

	// - MARK: write side (port phase 2 — the ratified .readWrite mode)

	// a write boundary over leafCore
	@MDB_transact(.readWrite, environments: leafCore)
	static func writeCal(_ key: TestKey, _ value: TestValue) throws {
		try #MDB_entry_store(environment: leafCore, database: leafCore.primary, key: key, value: value)
	}

	// Design-B joins WRITES into ONE transaction: the joined writeCal call
	// writes through THIS boundary's tx — atomic by construction
	@MDB_transact(.readWrite, environments: leafCore)
	static func writePair(_ key1: TestKey, _ value1: TestValue, _ key2: TestKey, _ value2: TestValue) throws {
		try #MDB_entry_store(environment: leafCore, database: leafCore.primary, key: key1, value: value1)
		try #MDB_transacted(writeCal(key2, value2))
	}

	// the atomicity leg: a joined write that throws rolls back EVERY write in
	// the boundary's single transaction
	@MDB_transact(.readWrite, environments: leafCore)
	static func writePairThrowing(_ key1: TestKey, _ value1: TestValue, _ key2: TestKey, _ value2: TestValue) throws {
		try #MDB_entry_store(environment: leafCore, database: leafCore.primary, key: key1, value: value1)
		try #MDB_transacted(writeCalThrowing(key2, value2))
	}

	@MDB_transact(.readWrite, environments: leafCore)
	static func writeCalThrowing(_ key: TestKey, _ value: TestValue) throws {
		try #MDB_entry_store(environment: leafCore, database: leafCore.primary, key: key, value: value)
		throw LeafPortError.badWrite
	}

	// writing on a .readOnly boundary's transaction is the documented RUNTIME
	// path (engine access violation) — the read-only write lint is a later pass
	@MDB_transact(.readOnly, environments: leafCore)
	static func writeOnReadOnly(_ key: TestKey, _ value: TestValue) throws {
		try #MDB_entry_store(environment: leafCore, database: leafCore.primary, key: key, value: value)
	}
}

enum LeafPortError: Error {
	case badWrite
}

@Suite("leaf-dialect port (Design B, real engine)")
struct LeafBoundaryPortTests {

	/// committed setup: seed `key` with `value` through a raw write transaction
	private func seed(_ core: LeafPortCore, _ key: TestKey, _ value: UInt64) throws {
		let tx = try Transaction(env: core.env, readOnly: false)
		try core.primary.setEntry(key: key, value: TestValue(RAW_native: value), flags: [], tx: tx)
		try tx.commit()
	}

	@Test func boundaryReadsCommittedState() throws {
		let key = TestKey(RAW_native: 1001)
		try seed(LeafPortDemo.leafCore, key, 7)
		let value = try LeafPortDemo.readCal(key)
		#expect(value == TestValue(RAW_native: 7))
	}

	@Test func joinedReadsShareOneSnapshotAcrossAMidBoundaryCommit() throws {
		let key = TestKey(RAW_native: 1002)
		try seed(LeafPortDemo.leafCore, key, 1)

		// Design B: both marked calls join the boundary's read transaction, so
		// even though a raw sibling WRITE commits 2 mid-boundary, both reads
		// return the boundary's open-time snapshot (1) — one consistent view.
		let (first, second) = try LeafPortDemo.joinedOverview(key)
		#expect(first == TestValue(RAW_native: 1))
		#expect(second == TestValue(RAW_native: 1))
		#expect(first == second)
	}

	@Test func committedStateDidChangeAfterTheSiblingWrite() throws {
		// proves the raw sibling write in joinedOverview actually LANDED — the
		// consistency of the joined reads is not a no-op artifact
		let key = TestKey(RAW_native: 1003)
		try seed(LeafPortDemo.leafCore, key, 1)
		_ = try LeafPortDemo.joinedOverview(key)
		let now = try LeafPortDemo.readCal(key)
		#expect(now == TestValue(RAW_native: 2), "the mid-boundary sibling write must be durably committed")
	}

	// - MARK: write side

	@Test func readWriteBoundaryCommitsDurably() throws {
		let key = TestKey(RAW_native: 2001)
		try LeafPortDemo.writeCal(key, TestValue(RAW_native: 42))
		#expect(try LeafPortDemo.leafCore.primary.readCommitted(key: key) == TestValue(RAW_native: 42))
	}

	@Test func joinedWritesComposeAtomicallyInOneTransaction() throws {
		let k1 = TestKey(RAW_native: 2002)
		let k2 = TestKey(RAW_native: 2003)
		// one boundary, one transaction: the direct write AND the joined write
		// land together on commit
		try LeafPortDemo.writePair(k1, TestValue(RAW_native: 1), k2, TestValue(RAW_native: 2))
		#expect(try LeafPortDemo.leafCore.primary.readCommitted(key: k1) == TestValue(RAW_native: 1))
		#expect(try LeafPortDemo.leafCore.primary.readCommitted(key: k2) == TestValue(RAW_native: 2))
	}

	@Test func thrownJoinedWriteRollsBackTheWholeBoundary() throws {
		let k1 = TestKey(RAW_native: 2004)
		let k2 = TestKey(RAW_native: 2005)
		// the joined write throws AFTER writing its own key; the boundary's
		// single transaction aborts, so NEITHER write is durable
		#expect(throws: LeafPortError.self) {
			try LeafPortDemo.writePairThrowing(k1, TestValue(RAW_native: 9), k2, TestValue(RAW_native: 10))
		}
		#expect(try LeafPortDemo.leafCore.primary.readCommitted(key: k1) == nil)
		#expect(try LeafPortDemo.leafCore.primary.readCommitted(key: k2) == nil)
	}

	@Test func writingOnAReadOnlyBoundaryThrowsAtRuntime() throws {
		// the documented runtime path: a write verb on a .readOnly boundary's
		// transaction surfaces as the engine's access violation (the
		// read-only-write lint is a later pass)
		let key = TestKey(RAW_native: 2006)
		#expect(throws: (any Error).self) {
			try LeafPortDemo.writeOnReadOnly(key, TestValue(RAW_native: 3))
		}
		#expect(try LeafPortDemo.leafCore.primary.readCommitted(key: key) == nil)
	}
}
