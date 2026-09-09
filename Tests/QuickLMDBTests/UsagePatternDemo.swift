import Testing
import Foundation
import QuickLMDB

// usage-pattern demonstration for the body-macro transaction design (current API).
//
// every boundary is a TOP-LEVEL transaction of its mode; relationships between
// boundaries are LMDB's own defaults, pinned by TransactionRelationshipTests:
//
//   .readWrite                                -> own write txn; commits on success, aborts on throw
//   .readOnly                                 -> own read txn; never commits
//   .readOnly inside .readWrite               -> sibling read: sees last COMMITTED state
//   .readOnly inside .readOnly                -> sibling read: legal because .noTLS is forced
//   .readWrite inside .readOnly               -> sibling write: legal, commits independently
//   .readWriteChild(parent:) inside a write   -> child txn: merges on commit, aborts independently
//   .readWrite inside .readWrite (no parent:) -> FORBIDDEN: lmdb deadlocks on its writer mutex
//
// the injected `tx` name is the composition contract: hand it to plain helpers that
// take `tx: borrowing Transaction`, or to a `.readWriteChild` boundary as `parent:`.
// operation call sites inside a boundary use the VERB vocabulary (#store / #load /
// #delete / #contains / #cursor / #clear), lowered by the body macro to the
// tx-bearing calls; plain operation calls must carry `tx:` explicitly or fail to
// compile (marker-gated attribution — shipped 16.1.0). this file demonstrates the
// shipped verb form.

@MDB_environment(file: "demo.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct DemoCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
	public let secondary: Database.DupSort<TestKey, TestValue>
}

extension DemoCore {

	// 1. read-write boundary: own write txn, committed exactly once on success
	@MDB_transact(.readWrite)
	public func store(_ key: consuming TestKey, _ value: consuming TestValue) throws {
		try #store(primary, key: key, value: value)
	}

	// 2. read-only boundary: own read txn, aborted on exit — never commits
	@MDB_transact(.readOnly)
	public func fetch(_ key: borrowing TestKey) throws -> TestValue? {
		return #load(primary, key: key)
	}

	// 3. helper composition: the injected `tx` is passed to a plain helper whose
	//    `tx:` parameter the operation call carries explicitly
	@MDB_transact(.readWrite)
	public func storeViaHelper(_ key: consuming TestKey, _ value: consuming TestValue) throws {
		try storeOne(key, value, tx: tx)
	}

	public func storeOne(_ key: borrowing TestKey, _ value: consuming TestValue, tx: borrowing Transaction) throws {
		try primary.setEntry(key: key, value: value, flags: [], tx: tx)
	}

	// 4. one boundary = one atomic unit, across any number of tables
	@MDB_transact(.readWrite)
	public func storeBoth(_ key: consuming TestKey, _ v1: consuming TestValue, _ v2: consuming TestValue) throws {
		try #store(primary, key: key, value: v1)
		try #store(secondary, key: key, value: v2)
	}

	// 5. write composition INSIDE a write: the child boundary merges into the parent.
	//    note the strict API consumes the value — handing it to a second consumer
	//    requires an explicit copy, which is the owning-class discipline here.
	@MDB_transact(.readWrite)
	public func storeWithAudit(_ key: consuming TestKey, _ value: consuming TestValue) throws {
		let auditValue = value                       // explicit copy for the audit row
		try #store(primary, key: key, value: value)
		try logAudit(key, auditValue, parent: tx)
	}

	@MDB_transact(.readWriteChild)
	public func logAudit(_ key: consuming TestKey, _ value: consuming TestValue, parent: borrowing Transaction) throws {
		try #store(secondary, key: key, value: value)
	}

	// 6. sibling READ inside a WRITE: the inner read is an independent snapshot of
	//    the last COMMITTED state — it does not see this boundary's uncommitted write.
	//    the pattern for "validate against durable data before committing":
	@MDB_transact(.readWrite)
	public func validateThenStore(_ key: consuming TestKey, _ value: consuming TestValue) throws -> TestValue? {
		let committed = try currentValue(key)   // sibling read: predates the write below
		try #store(primary, key: key, value: value)
		return committed
	}

	@MDB_transact(.readOnly)
	public func currentValue(_ key: borrowing TestKey) throws -> TestValue? {
		return #load(primary, key: key)
	}

	// 7. sibling WRITE inside a READ: legal; it commits independently and the outer
	//    read's snapshot is unaffected (it keeps seeing the pre-write state)
	@MDB_transact(.readOnly)
	public func snapshotThenBump(_ key: consuming TestKey, _ bump: consuming TestValue) throws -> TestValue? {
		let before = try currentValue(key)      // this read boundary's snapshot
		try store(key, bump)                    // sibling write, commits on its own
		return before
	}

	// 8. read INSIDE a read: multiple sibling reads on one thread are legal because
	//    @MDB_environment forces .noTLS (each transaction owns its reader slot)
	@MDB_transact(.readOnly)
	public func fetchTwice(_ key: borrowing TestKey) throws -> (TestValue?, TestValue?) {
		let a = try fetch(key)
		let b = try fetch(key)
		return (a, b)
	}

	// 9. cursors bind inside the boundary like any other operation
	@MDB_transact(.readOnly)
	public func scan() throws -> [(key: TestKey, value: TestValue)] {
		var result: [(key: TestKey, value: TestValue)] = []
		#cursor(primary) { cursor in
			for (k, v) in cursor {
				result.append((key: k, value: v))
			}
		}
		return result
	}

	// 10. the raw path is untouched: any code that wants its own transaction owns it
	public func readRaw(_ key: borrowing TestKey) throws -> TestValue? {
		let tx = try Transaction(env: env, readOnly: true)
		let result = try? primary.loadEntry(key: key, as: TestValue.self, tx: tx)
		tx.abort()
		return result
	}
}

@Suite("Boundary usage patterns (current API)")
struct UsagePatternDemo {

	private func makeCore() throws -> DemoCore {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-demo-\(UUID().uuidString)", isDirectory:true)
		try FileManager.default.createDirectory(at:dir, withIntermediateDirectories:true)
		return try DemoCore.open(at: dir.path)
	}

	@Test func endToEndBoundaryComposition() throws {
		let core = try makeCore()

		// 1 + 2: a write boundary, then a read boundary
		try core.store(TestKey(RAW_native: 1), TestValue(RAW_native: 10))
		#expect(try core.fetch(TestKey(RAW_native: 1)) == TestValue(RAW_native: 10))

		// 3: helper composition through the injected `tx`
		try core.storeViaHelper(TestKey(RAW_native: 2), TestValue(RAW_native: 20))
		#expect(try core.fetch(TestKey(RAW_native: 2)) == TestValue(RAW_native: 20))

		// 4: two tables, one atomic boundary
		try core.storeBoth(TestKey(RAW_native: 3), TestValue(RAW_native: 30), TestValue(RAW_native: 300))

		// 5: value + audit row committed together via a child boundary
		try core.storeWithAudit(TestKey(RAW_native: 4), TestValue(RAW_native: 40))
		// 5b: and the child boundary's audit row actually landed (atomic with the parent)
		let auditTx = try Transaction(env: core.env, readOnly: true)
		let audit = try? core.secondary.loadEntry(key: TestKey(RAW_native: 4), as: TestValue.self, tx: auditTx)
		auditTx.abort()
		#expect(audit == TestValue(RAW_native: 40), "the child boundary's audit write committed atomically with its parent")

		// 6: the sibling read ran BEFORE this boundary's write existed — returns nil
		let stale = try core.validateThenStore(TestKey(RAW_native: 5), TestValue(RAW_native: 50))
		#expect(stale == nil, "sibling read sees committed state, not the uncommitted write")

		// 7: sibling write under a read: snapshot stays pre-write, write survives
		try core.store(TestKey(RAW_native: 6), TestValue(RAW_native: 60))
		let before = try core.snapshotThenBump(TestKey(RAW_native: 6), TestValue(RAW_native: 600))
		#expect(before == TestValue(RAW_native: 60), "read boundary's snapshot predates the sibling write")
		#expect(try core.fetch(TestKey(RAW_native: 6)) == TestValue(RAW_native: 600), "sibling write committed independently")

		// 8: read-inside-read is legal — .noTLS is forced by the generated open
		let pair = try core.fetchTwice(TestKey(RAW_native: 1))
		#expect(pair.0 == TestValue(RAW_native: 10) && pair.1 == TestValue(RAW_native: 10))

		// 9: cursor scan inside a read boundary sees all six keys
		let all = try core.scan()
		#expect(all.count == 6)

		// 10: the raw path still works; and the env macro forced .noTLS
		#expect(try core.readRaw(TestKey(RAW_native: 1)) == TestValue(RAW_native: 10))
		#expect(core.env.flags.contains(.noTLS))
	}
}
