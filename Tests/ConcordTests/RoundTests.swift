@testable import concord
import Testing
import Foundation
import QuickLMDB

@Suite("concord full rounds", .serialized)
struct RoundTests {
	/// runs a full round between two in-memory nodes on dedicated threads and
	/// returns both nodes, propagating any round error.
	private func runRound(aliceKeys:Range<UInt64>, bobKeys:Range<UInt64>, oneWay:Bool = false, bucketCount:Int = 20) throws -> (alice:NodeIndex<TestID, TestValue>, bob:NodeIndex<TestID, TestValue>) {
		let alice = NodeIndex<TestID, TestValue>()
		let bob = NodeIndex<TestID, TestValue>()
		seedNode(alice, keyRange:aliceKeys)
		seedNode(bob, keyRange:bobKeys)

		let (alicePipe, bobPipe) = PipeTransport<TestID, TestValue>.makePair()
		let aliceError = ErrorBox()
		let bobError = ErrorBox()
		let aliceDone = DispatchSemaphore(value:0)
		let bobDone = DispatchSemaphore(value:0)

		let aliceThread = Thread {
			defer { aliceDone.signal() }
			do {
				try ConcordSession(index:alice, transport:alicePipe, role:.initiator, buckets:bucketCount, oneWaySync:oneWay).runRound()
			} catch {
				aliceError.set(error)
			}
		}
		let bobThread = Thread {
			defer { bobDone.signal() }
			do {
				try ConcordSession(index:bob, transport:bobPipe, role:.responder, buckets:bucketCount).runRound()
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
		return (alice, bob)
	}

	/// asserts union convergence plus value integrity for sampled keys.
	private func expectUnion(_ alice:NodeIndex<TestID, TestValue>, _ bob:NodeIndex<TestID, TestValue>, union:Range<UInt64>) {
		#expect(alice.count == union.count)
		#expect(bob.count == union.count)
		let step = max(1, union.count / 100)
		for offset in stride(from:0, to:union.count, by:step) {
			let sample = union.lowerBound &+ UInt64(offset)
			let key = TestID(RAW_native: sample)
			let expected = seededValueBytes(forKey: sample)
			#expect(alice.valueBytes(for:key) == expected)
			#expect(bob.valueBytes(for:key) == expected)
		}
	}

	@Test("identical 100k stores converge with no data transfer")
	func identicalStores() throws {
		let (alice, bob) = try runRound(aliceKeys:0..<100_000, bobKeys:0..<100_000)
		expectUnion(alice, bob, union:0..<100_000)
		#expect(alice.accounting.storeBytesCount == 0)
		#expect(bob.accounting.storeBytesCount == 0)
	}

	@Test("disjoint stores converge to the union")
	func disjointStores() throws {
		let (alice, bob) = try runRound(aliceKeys:0..<10_000, bobKeys:10_000..<20_000)
		expectUnion(alice, bob, union:0..<20_000)
	}

	@Test("different store sizes converge to the union")
	func differentSizes() throws {
		let (alice, bob) = try runRound(aliceKeys:0..<57_832, bobKeys:100_000..<101_974)
		// 57,832 ∪ 1,974 disjoint keys
		#expect(alice.count == 59_806)
		#expect(bob.count == 59_806)
		let keyValueList:[UInt64] = [0, 28_000, 57_831, 100_000, 101_973]
		for keyValue in keyValueList {
			let key = TestID(RAW_native: keyValue)
			let expected = seededValueBytes(forKey: keyValue)
			#expect(alice.valueBytes(for:key) == expected)
			#expect(bob.valueBytes(for:key) == expected)
		}
	}

	@Test("an empty store syncs against a full one")
	func emptyVersusFull() throws {
		let (alice, bob) = try runRound(aliceKeys:0..<0, bobKeys:0..<1_000)
		#expect(alice.count == 1_000)
		#expect(bob.count == 1_000)
		#expect(alice.valueBytes(for:TestID(RAW_native:999)) == seededValueBytes(forKey:999))
	}

	@Test("two empty stores converge")
	func bothEmpty() throws {
		let (alice, bob) = try runRound(aliceKeys:0..<0, bobKeys:0..<0)
		#expect(alice.count == 0)
		#expect(bob.count == 0)
	}

	@Test("one-way sync only fills the initiator")
	func oneWaySync() throws {
		// the initiator (alice) receives what it needs but does not push its own.
		let (alice, bob) = try runRound(aliceKeys:0..<1_000, bobKeys:1_000..<2_000, oneWay:true)
		#expect(alice.count == 2_000)
		#expect(bob.count == 1_000)
		#expect(bob.valueBytes(for:TestID(RAW_native:500)) == nil)
	}

	@Test("the data path is zero-copy out of the index and verbatim in")
	func copyAccounting() throws {
		let (alice, bob) = try runRound(aliceKeys:0..<500, bobKeys:500..<1_000)
		// alice pushes her own 500 (have) — each one a borrowed view with no copy.
		#expect(alice.accounting.loadBytesCount == 500)
		#expect(alice.accounting.borrowedViewBaseAddresses.count == 500)
		// both sides receive exactly the peer's entries, verbatim 8-byte writes.
		#expect(alice.accounting.storeBytesCount == 500)
		#expect(bob.accounting.storeBytesCount == 500)
		#expect(alice.accounting.storeSizes.allSatisfy { $0 == 8 })
		#expect(bob.accounting.storeSizes.allSatisfy { $0 == 8 })
		// value integrity across every transferred entry
		for keyValue in 0..<1_000 {
			let key = TestID(RAW_native: UInt64(keyValue))
			#expect(alice.valueBytes(for:key) == seededValueBytes(forKey: UInt64(keyValue)))
			#expect(bob.valueBytes(for:key) == seededValueBytes(forKey: UInt64(keyValue)))
		}
	}
}
