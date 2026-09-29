import Testing
import RAW
import QuickLMDB
import concord

@Suite("concord message model + byte views", .serialized)
struct ConcordShapeTests {
	// builds a fingerprint from a repeating seed byte.
	private func fingerprint(seed:UInt8) -> Fingerprint {
		let bytes = [UInt8](repeating: seed, count: 24)
		return bytes.withUnsafeBytes { Fingerprint(RAW_decode:$0)! }
	}

	@Test("keys are 8-byte big-endian and totally ordered")
	func keyShape() throws {
		let id = TestID(RAW_native: 0xDEADBEEF)
		id.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { ptr in
			#expect(ptr.count == 8)
			#expect(ptr[0] == 0x00)
			#expect(ptr[4] == 0xDE)
			#expect(ptr[7] == 0xEF)
		}
		#expect(TestID(RAW_native: 1) < TestID(RAW_native: 2))
		#expect(TestID(RAW_native: 2) > TestID(RAW_native: 1))
		#expect(TestID(RAW_native: 5) == TestID(RAW_native: 5))
	}

	@Test("fingerprints are 24 bytes and value-distinct")
	func fingerprintShape() throws {
		let a = fingerprint(seed: 1)
		let b = fingerprint(seed: 2)
		#expect(a == a)
		#expect(a != b)
		a.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { ptr in
			#expect(ptr.count == 24)
		}
	}

	@Test("owned bytes read back their bytes and are sendable")
	func ownedBytes() async throws {
		let owned = ConcordOwnedBytes([0x01, 0x02, 0x03, 0x04])
		owned.withUnsafeBytes { ptr in
			#expect(ptr.count == 4)
			#expect(Array(ptr) == [0x01, 0x02, 0x03, 0x04])
		}
		// sendable — crossing a task boundary is legal for owned bytes.
		let roundTripped = await Task.detached { () -> [UInt8] in
			return owned.withUnsafeBytes { Array($0) }
		}.value
		#expect(roundTripped == [0x01, 0x02, 0x03, 0x04])
	}

	@Test("borrowed bytes view existing memory without copying")
	func borrowedBytes() throws {
		let backing = [UInt8](repeating: 0xAB, count: 8)
		backing.withUnsafeBytes { backingPtr in
			let view = ConcordBorrowedBytes(backingPtr)
			view.withUnsafeBytes { ptr in
				#expect(ptr.count == 8)
				#expect(ptr.baseAddress == backingPtr.baseAddress) // same memory, no copy
			}
		}
	}

	@Test("owned bytes can be materialized from any view")
	func ownedFromView() throws {
		let backing = [UInt8]([9, 8, 7])
		let owned = try backing.withUnsafeBytes { ptr in
			try ConcordOwnedBytes(ConcordBorrowedBytes(ptr))
		}
		owned.withUnsafeBytes { ptr in
			#expect(Array(ptr) == [9, 8, 7])
		}
	}

	@Test("the message model carries every section and message shape")
	func messageShape() throws {
		let k0 = TestID(RAW_native: 0)
		let k1 = TestID(RAW_native: 1)
		let k2 = TestID(RAW_native: 2)
		let fp = fingerprint(seed: 7)

		let reconcile = ConcordReconcile(sections: [
			.skip(k0),
			.fingerprint(k1, fp),
			.idList(k2, [k1, k0]),
		])
		#expect(reconcile.sections.count == 3)

		let messages: [ConcordMessage<TestID, TestValue>] = [
			.reconcile(reconcile),
			.dataQuery(k1),
			.data(key: k2, bytes: ConcordOwnedBytes([0x01, 0x02])),
			.finish,
		]
		#expect(messages.count == 4)
	}

	@Test("messages pattern-match back to their payloads")
	func messageMatching() throws {
		let key = TestID(RAW_native: 42)
		let payload: [UInt8] = [0xCA, 0xFE]

		var reconcileSeen = false
		var dataQuerySeen = false
		var dataSeen = false
		var finishSeen = false

		let messages:[ConcordMessage<TestID, TestValue>] = [
			.reconcile(ConcordReconcile(sections: [.skip(key)])),
			.dataQuery(key),
			.data(key: key, bytes: ConcordOwnedBytes(payload)),
			.finish,
		]
		for message in messages {
			switch message {
			case .reconcile(let r):
				reconcileSeen = true
				if case .skip(let bound) = r.sections[0] {
					#expect(bound == key)
				}
			case .dataQuery(let k):
				dataQuerySeen = true
				#expect(k == key)
			case .data(key: let k, bytes: let bytes):
				dataSeen = true
				#expect(k == key)
				bytes.withUnsafeBytes { ptr in
					#expect(Array(ptr) == payload)
				}
			case .finish:
				finishSeen = true
			}
		}
		#expect(reconcileSeen)
		#expect(dataQuerySeen)
		#expect(dataSeen)
		#expect(finishSeen)
	}

	@Test("errors are distinct and compose as Swift.Error")
	func errorShape() throws {
		#expect(ConcordError.emptyReconcile != ConcordError.missingKey)
		#expect(ConcordError.nonIncreasingBounds == ConcordError.nonIncreasingBounds)
		let boxed: any Error = ConcordError.unexpectedFinish
		#expect(boxed is ConcordError)
	}
}
