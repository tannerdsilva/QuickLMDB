@testable import concord
import Testing
import Foundation
import SystemPackage
import QuickLMDB

/// creates a fresh environment in a temp directory.
func makeTestEnv() throws -> (dir:String, env:Environment) {
	let dir = NSTemporaryDirectory() + "concord-lmdb-\(UUID().uuidString)"
	try FileManager.default.createDirectory(atPath:dir, withIntermediateDirectories:true)
	let env = try Environment(path:dir + "/events.mdb", flags:[.noSubDir], mapSize:64 * 1024 * 1024, maxReaders:32, maxDBs:8, mode:[.ownerReadWriteExecute, .groupRead, .otherRead])
	return (dir, env)
}

/// seeds a strict "events" table (typed handle, Key=TestID, Value=TestValue).
func seedStrict(env:Environment, keys:[UInt64]) throws {
	let setup = try Transaction<Write>(env:env)
	let db = try Database.Strict<TestID, TestValue>(env:env, name:"events", flags:[.create], tx:setup)
	for keyValue in keys {
		try db.setEntry(key:TestID(RAW_native:keyValue), value:TestValue(RAW_native:keyValue &* 3 &+ 1), flags:[], tx:setup)
	}
	// commit after the work; any throw drops `setup`, whose deinit aborts.
	try setup.commit()
}

/// entry count via db statistics, in a throwaway write transaction
/// (LMDB requires a write transaction to open database handles).
func countEntries(env:Environment) throws -> Int {
	let txn = try Transaction<Write>(env:env)
	let db = try Database(env:env, name:"events", flags:[], tx:txn)
	return try Int(db.dbStatistics(tx:txn).ms_entries)
}

/// the stored value bytes for a key, in a throwaway write transaction.
func storedBytes(env:Environment, key:UInt64) throws -> [UInt8]? {
	let txn = try Transaction<Write>(env:env)
	let db = try Database(env:env, name:"events", flags:[], tx:txn)
	let keyBytes = TestID(RAW_native:key).RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { Array($0) }
	return try keyBytes.withUnsafeBytes { keyBuf in
		let keyVal = MDB_val(mv_size:keyBuf.count, mv_data:UnsafeMutableRawPointer(mutating:keyBuf.baseAddress!))
		do {
			let value = try db.loadEntry(key:keyVal, as:MDB_val.self, tx:txn)
			return Array(UnsafeRawBufferPointer(start:value.mv_data, count:value.mv_size))
		} catch LMDBError.notFound {
			return nil
		}
	}
}

/// builds the raw handle + cursor over the caller's write transaction and
/// returns the LMDB index. the caller owns `tx` and commits (or aborts) it.
func makeLMDBIndex<Key:ConcordKey, Value:MDB_convertible>(env:Environment, tx:borrowing Transaction<Write>, name:String = "events") throws -> ConcordLMDBIndex<Key, Value> {
	let db = try Database(env:env, name:name, flags:[], tx:tx)
	let cursor = try Cursor(db:db, tx:tx)
	return ConcordLMDBIndex<Key, Value>(database:db, cursor:cursor)
}

@Suite("concord LMDB index primitives", .serialized)
struct LMDBIndexTests {

	@Test("entryCount, firstKey, and forEachKey walk a seeded table")
	func countAndWalk() throws {
		let (dir, env) = try makeTestEnv()
		defer { try? FileManager.default.removeItem(atPath:dir) }
		try seedStrict(env:env, keys:[3, 1, 5, 2, 4])

		let txn = try Transaction<Write>(env:env)
		do {
			let index: ConcordLMDBIndex<TestID, TestValue> = try makeLMDBIndex(env:env, tx:txn)
			#expect(try index.entryCount() == 5)
			#expect(try index.firstKey() == TestID(RAW_native:1))

			var walked:[TestID] = []
			try index.forEachKey(in:nil, nil) { walked.append($0) }
			#expect(walked == [1,2,3,4,5].map { TestID(RAW_native:$0) })

			var ranged:[TestID] = []
			try index.forEachKey(in:TestID(RAW_native:2), TestID(RAW_native:5)) { ranged.append($0) }
			#expect(ranged == [2,3,4].map { TestID(RAW_native:$0) })
			#expect(try index.keyCount(in:TestID(RAW_native:2), TestID(RAW_native:5)) == 3)
		}
		// the index (and its cursor) is released before the transaction commits.
		try txn.commit()
	}

	@Test("fingerprints match the in-memory double byte-for-byte")
	func fingerprintCrossImpl() throws {
		let keys:[UInt64] = [1, 7, 12, 99, 250, 4096]
		let (dir, env) = try makeTestEnv()
		defer { try? FileManager.default.removeItem(atPath:dir) }
		try seedStrict(env:env, keys:keys)

		let memory = NodeIndex<TestID, TestValue>()
		for keyValue in keys {
			memory.seed(key:TestID(RAW_native:keyValue), value:seededValueBytes(forKey:keyValue))
		}

		let txn = try Transaction<Write>(env:env)
		do {
			let index: ConcordLMDBIndex<TestID, TestValue> = try makeLMDBIndex(env:env, tx:txn)
			// whole space
			let wholeLMDB = try index.fingerprint(of:nil, nil)
			let wholeMemory = try memory.fingerprint(of:nil, nil)
			#expect(wholeLMDB == wholeMemory)
			// a bounded subrange
			let rangeLMDB = try index.fingerprint(of:TestID(RAW_native:2), TestID(RAW_native:100))
			let rangeMemory = try memory.fingerprint(of:TestID(RAW_native:2), TestID(RAW_native:100))
			#expect(rangeLMDB == rangeMemory)
			// empty ranges hash to the digest of empty input on both impls
			let emptyLMDB = try index.fingerprint(of:TestID(RAW_native:9000), TestID(RAW_native:9001))
			let emptyMemory = try memory.fingerprint(of:TestID(RAW_native:9000), TestID(RAW_native:9001))
			#expect(emptyLMDB == emptyMemory)
		}
		try txn.commit()
	}

	@Test("loadBytes is a borrowed mmap view over stored bytes")
	func loadBytesBorrowed() throws {
		let (dir, env) = try makeTestEnv()
		defer { try? FileManager.default.removeItem(atPath:dir) }
		try seedStrict(env:env, keys:[10, 20, 30])

		let txn = try Transaction<Write>(env:env)
		do {
			let index: ConcordLMDBIndex<TestID, TestValue> = try makeLMDBIndex(env:env, tx:txn)
			guard let view = try index.loadBytes(TestID(RAW_native:10)) else {
				Issue.record("expected a value view")
				return
			}
			#expect(view is ConcordBorrowedBytes)
			let bytes = view.withUnsafeBytes { Array($0) }
			#expect(bytes == seededValueBytes(forKey:10))
			#expect(try index.loadBytes(TestID(RAW_native:999)) == nil)
		}
		try txn.commit()
	}

	@Test("storeBytes writes a received value verbatim")
	func storeVerbatim() throws {
		let (dir, env) = try makeTestEnv()
		defer { try? FileManager.default.removeItem(atPath:dir) }
		try seedStrict(env:env, keys:[10, 20])

		let txn = try Transaction<Write>(env:env)
		do {
			let index: ConcordLMDBIndex<TestID, TestValue> = try makeLMDBIndex(env:env, tx:txn)
			try index.storeBytes(TestID(RAW_native:7), ConcordOwnedBytes(seededValueBytes(forKey:7)))
		}
		try txn.commit()

		#expect(try countEntries(env:env) == 3)
		#expect(try storedBytes(env:env, key:7) == seededValueBytes(forKey:7))
	}

	@Test("a concurrent second writer blocks until the round txn closes")
	func concurrentWriterBlocks() throws {
		let (dir, env) = try makeTestEnv()
		defer { try? FileManager.default.removeItem(atPath:dir) }
		try seedStrict(env:env, keys:[1,2,3])

		// holds the environment's single writer lock (the round's transaction).
		let main = try Transaction<Write>(env:env)

		// a second write transaction from another thread cannot acquire the
		// writer lock while the round's transaction is open — under
		// `MDB_NOTLS` this BLOCKS (it does not return `MDB_BUSY`), so the test
		// asserts the block, then proves the writer is admitted after commit.
		let admitted = DispatchSemaphore(value:0)
		let secondWriter = Thread {
			defer { admitted.signal() }
			do {
				let txn = try Transaction<Write>(env:env)
				_ = txn // dropped, aborts (deinit)
			} catch {
				// must not fail — it is merely waiting.
			}
		}
		secondWriter.start()

		// still blocked while the round transaction is open (1s probe).
		#expect(admitted.wait(timeout:.now() + .seconds(1)) == .timedOut)

		// close the round transaction; the waiting writer is admitted.
		try main.commit()
		#expect(admitted.wait(timeout:.now() + .seconds(10)) == .success)
	}

	@Test("fingerprintAndAdvance is bounded by the range end")
	func advanceBounded() throws {
		let (dir, env) = try makeTestEnv()
		defer { try? FileManager.default.removeItem(atPath:dir) }
		try seedStrict(env:env, keys:Array((1..<11).map { UInt64($0) }))

		let txn = try Transaction<Write>(env:env)
		// the index (and its cursor) is released before the transaction commits.
		do {
			let index: ConcordLMDBIndex<TestID, TestValue> = try makeLMDBIndex(env:env, tx:txn)

			// range [2, 9): keys 2...8 hashed; the boundary must clamp to 9, not nil.
			let (boundary, fingerprint) = try index.fingerprintAndAdvance(begin:TestID(RAW_native:2), count:100, end:TestID(RAW_native:9))
			#expect(boundary == TestID(RAW_native:9))
			let directFP = try index.fingerprint(of:TestID(RAW_native:2), TestID(RAW_native:9))
			#expect(fingerprint == directFP)

			// count-limited bucket from the start: 3 keys hashed, boundary 4.
			let (b2, fp2) = try index.fingerprintAndAdvance(begin:TestID(RAW_native:1), count:3, end:nil)
			#expect(b2 == TestID(RAW_native:4))
			let direct2 = try index.fingerprint(of:TestID(RAW_native:1), TestID(RAW_native:4))
			#expect(fp2 == direct2)
		}

		try txn.commit()
	}
}
