import Testing
import Foundation
import Dispatch
import Synchronization
import QuickLMDB
import RAW

// the torn-read concurrency pin (DEBT item 2): a boundary read racing a
// concurrent writer on a MUTABLE key. every runtime test so far writes
// append-only/immutable keys; this one OVERWRITES the same (generation,
// payload) pair in every write transaction, while a boundary repeatedly
// reads the pair through ONE transaction and asserts the payload always
// matches the generation it was committed with. a reader that straddled two
// writes (the pricedb facade multiplexing shape) would observe a mismatch;
// the boundary's snapshot isolation must never produce one.
//
// concurrency shape: the LMDB surface is `noasync` (transactions may only be
// created and driven in synchronous contexts), so the concurrent writer and
// reader run as two synchronous `Thread`s joined by the (synchronous) test —
// no DispatchQueue, no semaphores, no actors in an async context.

@MDB_environment(file: "tornread.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct TornReadCore: Sendable {
	public let env: Environment
	public let snapshots: Database.Strict<TestKey, TestValue>
}

private enum TornKeys {
	static let generation = TestKey(RAW_native: 1)
	static let payload = TestKey(RAW_native: 2)
}

// the payload is generation * tornHash — any composite assembled from two
// DIFFERENT generations fails the consistency check
private let tornHash: UInt64 = 0x9E37_79B9_7F4A_7C15

extension TornReadCore {

	// the boundary under test: reads the (generation, payload) composite
	// through ONE transaction (one snapshot)
	@MDB_transact(.readOnly)
	func readSnapshot() throws -> (UInt64, UInt64) {
		let g = #load(TornReadCore.self, database: \.snapshots, key: TornKeys.generation)
		let p = #load(TornReadCore.self, database: \.snapshots, key: TornKeys.payload)
		return (g?.RAW_native() ?? 0, p?.RAW_native() ?? 0)
	}
}

private final class ViolationCounter: Sendable {
	private let state = Mutex<Int>(0)
	func add() { state.withLock { $0 += 1 } }
	var value: Int { state.withLock { $0 } }
}

@Suite("torn-read: a boundary read racing a concurrent writer on a MUTABLE key")
struct TornReadTests {

	@Test func noTornObservationsUnderConcurrentMutation() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-tornread-\(UUID().uuidString)", isDirectory: true)
		let core = try TornReadCore.open(at: dir.path)

		// seed the pair so the reader never observes an absent half
		let seedTX = try Transaction<Write>(env: core.env)
		try core.snapshots.store(key: TornKeys.generation, value: TestValue(RAW_native: 0), tx: seedTX)
		try core.snapshots.store(key: TornKeys.payload, value: TestValue(RAW_native: 0), tx: seedTX)
		try seedTX.commit()

		let iterations = 20_000
		let violations = ViolationCounter()
		// this is a SYNCHRONOUS test — the join semaphores below block plain
		// platform threads doing plain synchronous LMDB work, never a Swift
		// concurrency executor thread (macOS Foundation exposes no Thread.join)
		let writerDone = DispatchSemaphore(value: 0)
		let readerDone = DispatchSemaphore(value: 0)

		// the concurrent MUTATING writer: overwrites the same two keys in a
		// fresh write transaction every iteration
		let writer = Thread {
			for i in 0..<iterations {
				do {
					let tx = try Transaction<Write>(env: core.env)
					try core.snapshots.store(key: TornKeys.generation, value: TestValue(RAW_native: UInt64(i)), tx: tx)
					try core.snapshots.store(key: TornKeys.payload, value: TestValue(RAW_native: UInt64(i) &* tornHash), tx: tx)
					try tx.commit()
				} catch {
					violations.add()
				}
			}
			writerDone.signal()
		}

		// the racing boundary reader: one snapshot per observation
		let reader = Thread {
			for _ in 0..<iterations {
				do {
					let (g, p) = try core.readSnapshot()
					if p != g &* tornHash { violations.add() }
				} catch {
					violations.add()
				}
			}
			readerDone.signal()
		}

		writer.start()
		reader.start()
		writerDone.wait()
		readerDone.wait()

		#expect(violations.value == 0, "observed a torn (generation, payload) composite across \(iterations) reads — the boundary must read one snapshot")
	}
}
