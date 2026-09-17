@testable import concord
import Testing
import Foundation
import QuickLMDB

@Suite("concord LMDB full rounds", .serialized)
struct LMDBRoundTests {

	/// runs a full round between two LMDB environments on dedicated threads.
	///
	/// each side opens its own write transaction on its thread; the database,
	/// cursor, and index are scoped to end BEFORE the transaction commits so
	/// the cursor is closed while its transaction is still open, and the driver
	/// commits (or aborts) the transaction after the round — the dialect's own
	/// transaction pattern.
	private func runLMDBRound(aliceEnv:Environment, bobEnv:Environment, oneWay:Bool = false, buckets:Int = 20) throws {
		let (alicePipe, bobPipe) = PipeTransport<TestID, TestValue>.makePair()
		let aliceError = ErrorBox()
		let bobError = ErrorBox()
		let aliceDone = DispatchSemaphore(value:0)
		let bobDone = DispatchSemaphore(value:0)

		let aliceThread = Thread {
			defer { aliceDone.signal() }
			do {
				let txn = try Transaction<Write>(env:aliceEnv)
				do {
					let db = try Database(env:aliceEnv, name:"events", flags:[], tx:txn)
					let cursor = try Cursor(db:db, tx:txn)
					let index = ConcordLMDBIndex<TestID, TestValue>(database:db, cursor:cursor)
					do {
						try ConcordSession(index:index, transport:alicePipe, role:.initiator, buckets:buckets, oneWaySync:oneWay).runRound()
					} catch {
						txn.abort()
						throw error
					}
				}
				// db/cursor/index released here — before the commit.
				try txn.commit()
			} catch {
				aliceError.set(error)
			}
		}
		let bobThread = Thread {
			defer { bobDone.signal() }
			do {
				let txn = try Transaction<Write>(env:bobEnv)
				do {
					let db = try Database(env:bobEnv, name:"events", flags:[], tx:txn)
					let cursor = try Cursor(db:db, tx:txn)
					let index = ConcordLMDBIndex<TestID, TestValue>(database:db, cursor:cursor)
					do {
						try ConcordSession(index:index, transport:bobPipe, role:.responder, buckets:buckets).runRound()
					} catch {
						txn.abort()
						throw error
					}
				}
				try txn.commit()
			} catch {
				bobError.set(error)
			}
		}

		aliceThread.start()
		bobThread.start()
		_ = aliceDone.wait(timeout:.distantFuture)
		_ = bobDone.wait(timeout:.distantFuture)
		if let error = aliceError.value { throw error }
		if let error = bobError.value { throw error }
	}

	@Test("disjoint LMDB stores converge to the union")
	func disjointRound() throws {
		let (aDir, aEnv) = try makeTestEnv()
		let (bDir, bEnv) = try makeTestEnv()
		defer {
			try? FileManager.default.removeItem(atPath:aDir)
			try? FileManager.default.removeItem(atPath:bDir)
		}
		try seedStrict(env:aEnv, keys:Array(0..<1_000).map { UInt64($0) })
		try seedStrict(env:bEnv, keys:Array(1_000..<2_000).map { UInt64($0) })

		try runLMDBRound(aliceEnv:aEnv, bobEnv:bEnv)

		#expect(try countEntries(env:aEnv) == 2_000)
		#expect(try countEntries(env:bEnv) == 2_000)
		#expect(try storedBytes(env:aEnv, key:1_500) == seededValueBytes(forKey:1_500))
		#expect(try storedBytes(env:bEnv, key:500) == seededValueBytes(forKey:500))
	}

	@Test("LMDB stores of different sizes converge")
	func differentSizesRound() throws {
		let (aDir, aEnv) = try makeTestEnv()
		let (bDir, bEnv) = try makeTestEnv()
		defer {
			try? FileManager.default.removeItem(atPath:aDir)
			try? FileManager.default.removeItem(atPath:bDir)
		}
		try seedStrict(env:aEnv, keys:Array(0..<1_000).map { UInt64($0) })
		try seedStrict(env:bEnv, keys:Array(100_000..<100_200).map { UInt64($0) })

		try runLMDBRound(aliceEnv:aEnv, bobEnv:bEnv)

		#expect(try countEntries(env:aEnv) == 1_200)
		#expect(try countEntries(env:bEnv) == 1_200)
		#expect(try storedBytes(env:aEnv, key:100_050) == seededValueBytes(forKey:100_050))
		#expect(try storedBytes(env:bEnv, key:999) == seededValueBytes(forKey:999))
	}

	@Test("one-way LMDB sync only fills the initiator")
	func oneWayRound() throws {
		let (aDir, aEnv) = try makeTestEnv()
		let (bDir, bEnv) = try makeTestEnv()
		defer {
			try? FileManager.default.removeItem(atPath:aDir)
			try? FileManager.default.removeItem(atPath:bDir)
		}
		try seedStrict(env:aEnv, keys:Array(0..<500).map { UInt64($0) })
		try seedStrict(env:bEnv, keys:Array(500..<1_000).map { UInt64($0) })

		try runLMDBRound(aliceEnv:aEnv, bobEnv:bEnv, oneWay:true)

		#expect(try countEntries(env:aEnv) == 1_000)
		#expect(try countEntries(env:bEnv) == 500)
		#expect(try storedBytes(env:bEnv, key:499) == nil)
		#expect(try storedBytes(env:aEnv, key:999) == seededValueBytes(forKey:999))
	}

	@Test("an in-memory node reconciles against an LMDB node (cross-impl fingerprints)")
	func crossImplRound() throws {
		let (dir, env) = try makeTestEnv()
		defer { try? FileManager.default.removeItem(atPath:dir) }
		try seedStrict(env:env, keys:Array(500..<1_000).map { UInt64($0) })

		let memory = NodeIndex<TestID, TestValue>()
		for keyValue in 0..<500 {
			memory.seed(key:TestID(RAW_native:UInt64(keyValue)), value:seededValueBytes(forKey:UInt64(keyValue)))
		}

		let (alicePipe, bobPipe) = PipeTransport<TestID, TestValue>.makePair()
		let aliceError = ErrorBox()
		let bobError = ErrorBox()
		let aliceDone = DispatchSemaphore(value:0)
		let bobDone = DispatchSemaphore(value:0)

		let aliceThread = Thread {
			defer { aliceDone.signal() }
			do {
				try ConcordSession(index:memory, transport:alicePipe, role:.initiator).runRound()
			} catch {
				aliceError.set(error)
			}
		}
		let bobThread = Thread {
			defer { bobDone.signal() }
			do {
				let txn = try Transaction<Write>(env:env)
				do {
					let db = try Database(env:env, name:"events", flags:[], tx:txn)
					let cursor = try Cursor(db:db, tx:txn)
					let index = ConcordLMDBIndex<TestID, TestValue>(database:db, cursor:cursor)
					do {
						try ConcordSession(index:index, transport:bobPipe, role:.responder).runRound()
					} catch {
						txn.abort()
						throw error
					}
				}
				try txn.commit()
			} catch {
				bobError.set(error)
			}
		}

		aliceThread.start()
		bobThread.start()
		_ = aliceDone.wait(timeout:.distantFuture)
		_ = bobDone.wait(timeout:.distantFuture)
		if let error = aliceError.value { throw error }
		if let error = bobError.value { throw error }

		// the reconciliation converged across implementations: the LMDB side
		// received the in-memory node's entries and vice versa.
		#expect(memory.count == 1_000)
		#expect(try countEntries(env:env) == 1_000)
		#expect(memory.valueBytes(for:TestID(RAW_native:750)) == seededValueBytes(forKey:750))
		#expect(try storedBytes(env:env, key:250) == seededValueBytes(forKey:250))
	}
}
