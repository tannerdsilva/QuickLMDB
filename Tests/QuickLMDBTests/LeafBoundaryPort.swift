import Testing
import Foundation
import QuickLMDB
import RAW

// leaf-dialect pins on the real engine under the typed-environment
// architecture: a readOnly boundary that joins READ calls (one snapshot), a
// raw sibling WRITE committed mid-boundary (joined reads keep the boundary's
// open-time snapshot), and the write side with Design-B atomic composition.

@MDB_environment(file: "leaf.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct LeafPortCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>

	@MDB_transact(.readOnly)
	public func readCal(_ key: TestKey) throws -> TestValue? {
		#load(LeafPortCore.self, database: \.primary, key: key)
	}

	// Design B: direct VERB reads on THIS boundary's transaction keep the
	// open-time snapshot. a mid-boundary raw SIBLING WRITE commits 2 to the
	// committed state; both reads must STILL see the boundary's snapshot.
	@MDB_transact(.readOnly)
	public func joinedOverview(_ key: TestKey) throws -> (TestValue?, TestValue?) {
		let a = #load(LeafPortCore.self, database: \.primary, key: key)
		let wtx = try Transaction<Write>(env: self.env)
		try self.primary.setEntry(key: key, value: TestValue(RAW_native: 2), flags: [], tx: wtx)
		try wtx.commit()
		let b = #load(LeafPortCore.self, database: \.primary, key: key)
		return (a, b)
	}

	@MDB_transact(.readWrite)
	public func writeCal(_ key: TestKey, _ value: TestValue) throws {
		try #store(LeafPortCore.self, database: \.primary, key: key, value: value)
	}

	// Design-B joins WRITES into ONE transaction: the joined writeCal call
	// writes through THIS boundary's tx — atomic by construction
	@MDB_transact(.readWrite)
	public func writePair(_ key1: TestKey, _ value1: TestValue, _ key2: TestKey, _ value2: TestValue) throws {
		try #store(LeafPortCore.self, database: \.primary, key: key1, value: value1)
		try #MDB_transacted(writeCal(key2, value2))
	}

	// the atomicity leg: a joined write that throws rolls back EVERY write in
	// the boundary's single transaction
	@MDB_transact(.readWrite)
	public func writePairThrowing(_ key1: TestKey, _ value1: TestValue, _ key2: TestKey, _ value2: TestValue) throws {
		try #store(LeafPortCore.self, database: \.primary, key: key1, value: value1)
		try #MDB_transacted(writeCalThrowing(key2, value2))
	}

	@MDB_transact(.readWrite)
	public func writeCalThrowing(_ key: TestKey, _ value: TestValue) throws {
		try #store(LeafPortCore.self, database: \.primary, key: key, value: value)
		throw LeafPortError.badWrite
	}
}

enum LeafPortError: Error {
	case badWrite
}

@Suite("leaf-dialect pins (Design B, typed environments)")
struct LeafBoundaryPortTests {

	private func freshCore() throws -> LeafPortCore {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-leaf-\(UUID().uuidString)", isDirectory: true)
		return try LeafPortCore.open(at: dir.path)
	}

	@Test func boundaryReadsCommittedState() throws {
		let core = try freshCore()
		let key = TestKey(RAW_native: 1001)
		try core.writeCal(key, TestValue(RAW_native: 7))
		#expect(try core.readCal(key) == TestValue(RAW_native: 7))
	}

	@Test func joinedReadsShareOneSnapshotAcrossAMidBoundaryCommit() throws {
		let core = try freshCore()
		let key = TestKey(RAW_native: 1002)
		try core.writeCal(key, TestValue(RAW_native: 1))

		// both marked calls join the boundary's read transaction, so even
		// though a raw sibling WRITE commits 2 mid-boundary, both reads return
		// the boundary's open-time snapshot (1) — one consistent view
		let (first, second) = try core.joinedOverview(key)
		#expect(first == TestValue(RAW_native: 1))
		#expect(second == TestValue(RAW_native: 1))
		#expect(first == second)
	}

	@Test func committedStateDidChangeAfterTheSiblingWrite() throws {
		// proves the raw sibling write in joinedOverview actually LANDED — the
		// consistency of the joined reads is not a no-op artifact
		let core = try freshCore()
		let key = TestKey(RAW_native: 1003)
		try core.writeCal(key, TestValue(RAW_native: 1))
		_ = try core.joinedOverview(key)
		#expect(try core.readCal(key) == TestValue(RAW_native: 2), "the mid-boundary sibling write must be durably committed")
	}

	// - MARK: write side

	@Test func readWriteBoundaryCommitsDurably() throws {
		let core = try freshCore()
		let key = TestKey(RAW_native: 2001)
		try core.writeCal(key, TestValue(RAW_native: 42))
		#expect(try core.readCal(key) == TestValue(RAW_native: 42))
	}

	@Test func joinedWritesComposeAtomicallyInOneTransaction() throws {
		let core = try freshCore()
		let k1 = TestKey(RAW_native: 2002)
		let k2 = TestKey(RAW_native: 2003)
		try core.writePair(k1, TestValue(RAW_native: 1), k2, TestValue(RAW_native: 2))
		#expect(try core.readCal(k1) == TestValue(RAW_native: 1))
		#expect(try core.readCal(k2) == TestValue(RAW_native: 2))
	}

	@Test func thrownJoinedWriteRollsBackTheWholeBoundary() throws {
		let core = try freshCore()
		let k1 = TestKey(RAW_native: 2004)
		let k2 = TestKey(RAW_native: 2005)
		// the joined write throws AFTER writing its own key; the boundary's
		// single transaction aborts, so NEITHER write is durable
		#expect(throws: LeafPortError.self) {
			try core.writePairThrowing(k1, TestValue(RAW_native: 9), k2, TestValue(RAW_native: 10))
		}
		#expect(try core.readCal(k1) == nil)
		#expect(try core.readCal(k2) == nil)
	}
}
