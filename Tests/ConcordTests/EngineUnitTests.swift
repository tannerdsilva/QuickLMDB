@testable import concord
import Testing
import RAW
import QuickLMDB
import RAW_blake2

enum TestError:Swift.Error, Equatable {
	case boom
}

@Suite("concord engine internals", .serialized)
struct EngineUnitTests {
	private func node(_ keys:[UInt64] = [1,2,3,4,5]) -> NodeIndex<TestID, TestValue> {
		let n = NodeIndex<TestID, TestValue>()
		for keyValue in keys {
			let bytes = seededValueBytes(forKey: keyValue)
			n.seed(key:TestID(RAW_native: keyValue), value:bytes)
		}
		return n
	}

	private func session(_ index:NodeIndex<TestID, TestValue>, role:ConcordRole = .initiator, buckets:Int = 20) -> ConcordSession<NodeIndex<TestID, TestValue>, ScriptedTransport<TestID, TestValue>> {
		return ConcordSession(index:index, transport:ScriptedTransport(messages:[]), role:role, buckets:buckets)
	}

	// MARK: initiate / splitRange section streams

	@Test("initiate on a small store emits a whole-space idList")
	func initiateSmallStore() throws {
		let s = session(node([1,2,3,4,5]))
		let sections = try s.initiate()
		#expect(sections.count == 1)
		guard case .idList(let bound, let ids) = sections[0] else {
			Issue.record("expected idList section")
			return
		}
		#expect(bound == nil)
		#expect(ids == [TestID(RAW_native:1), TestID(RAW_native:2), TestID(RAW_native:3), TestID(RAW_native:4), TestID(RAW_native:5)])
	}

	@Test("initiate on an empty store emits an empty idList")
	func initiateEmptyStore() throws {
		let s = session(node([]))
		let sections = try s.initiate()
		guard case .idList(let bound, let ids) = sections[0] else {
			Issue.record("expected idList section")
			return
		}
		#expect(bound == nil)
		#expect(ids.isEmpty)
	}

	@Test("splitRange on a large store emits one fingerprint per bucket")
	func splitLargeStore() throws {
		let n = node([])
		for keyValue in 0..<200 {
			n.seed(key:TestID(RAW_native: UInt64(keyValue)), value:seededValueBytes(forKey: UInt64(keyValue)))
		}
		let s = session(n, buckets:10)
		let sections = try s.splitRange(begin:nil, end:nil, emittedBound:nil)
		#expect(sections.count == 10)
		var previousBound:TestID? = nil
		var seenNilBound = false
		for (i, section) in sections.enumerated() {
			guard case .fingerprint(let bound, let fp) = section else {
				Issue.record("expected fingerprint section at \(i)")
				return
			}
			// boundaries strictly increase and only the last one may be nil
			if let bound = bound {
				if let previousBound = previousBound {
					#expect(bound > previousBound)
				}
			} else {
				#expect(i == sections.count - 1)
				seenNilBound = true
			}
			previousBound = bound
			fp.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { ptr in
				#expect(ptr.count == 24)
			}
		}
		#expect(seenNilBound)
		// adjacent bucket fingerprints must differ
		if case .fingerprint(_, let fpa) = sections[0], case .fingerprint(_, let fpb) = sections[1] {
			#expect(fpa != fpb)
		}
	}

	// MARK: fingerprint semantics

	@Test("fingerprints are deterministic and range-sensitive")
	func fingerprintSemantics() throws {
		let n = node([1,2,3,4,5])
		let whole = try n.fingerprint(of:nil, nil)
		let wholeAgain = try n.fingerprint(of:nil, nil)
		#expect(whole == wholeAgain)
		let prefix = try n.fingerprint(of:TestID(RAW_native:1), TestID(RAW_native:5))
		#expect(prefix != whole)
	}

	@Test("empty range fingerprint equals the digest of empty input")
	func emptyFingerprint() throws {
		let n = node([1,2,3,4,5])
		let emptyRange = try n.fingerprint(of:TestID(RAW_native:9), TestID(RAW_native:9))
		var hasher = try RAW_blake2.Hasher<RAW_blake2.S, [UInt8]>(outputLength: 24)
		let direct = try hasher.finish().withUnsafeBytes { Fingerprint(RAW_decode:$0)! }
		#expect(emptyRange == direct)
	}

	// MARK: processReconcile

	@Test("a matching fingerprint produces no reply (range in sync)")
	func fingerprintMatchSkips() throws {
		let n = node([1,2,3,4,5])
		let s = session(n, role:.responder)
		let query:ConcordReconcile<TestID> = ConcordReconcile(sections:[.fingerprint(nil, try n.fingerprint(of:nil, nil))])
		let outcome = try s.processReconcile(query, isInitiator:false)
		#expect(outcome.reply == nil)
		#expect(outcome.have.isEmpty)
		#expect(outcome.need.isEmpty)
	}

	@Test("a mismatching fingerprint splits into an idList for small ranges")
	func fingerprintMismatchSplits() throws {
		let n = node([1,2,3,4,5])
		let s = session(n, role:.responder)
		let wrong = try n.fingerprint(of:TestID(RAW_native: 11), TestID(RAW_native: 22))
		let query:ConcordReconcile<TestID> = ConcordReconcile(sections:[.fingerprint(nil, wrong)])
		let outcome = try s.processReconcile(query, isInitiator:false)
		guard let reply = outcome.reply, reply.count == 1, case .idList(let bound, let ids) = reply[0] else {
			Issue.record("expected a single idList reply")
			return
		}
		#expect(bound == nil)
		#expect(ids == [TestID(RAW_native:1), TestID(RAW_native:2), TestID(RAW_native:3), TestID(RAW_native:4), TestID(RAW_native:5)])
	}

	@Test("the responder answers an idList with its own keys in range")
	func responderIdListReply() throws {
		let n = node([1,2,3,4,5])
		let s = session(n, role:.responder)
		let query = ConcordReconcile(sections:[.idList(TestID(RAW_native:3), [])])
		let outcome = try s.processReconcile(query, isInitiator:false)
		guard let reply = outcome.reply, reply.count == 1, case .idList(let bound, let ids) = reply[0] else {
			Issue.record("expected a single idList reply")
			return
		}
		#expect(bound == TestID(RAW_native:3))
		#expect(ids == [TestID(RAW_native:1), TestID(RAW_native:2)])
	}

	@Test("the initiator diffs an idList into have and need")
	func initiatorDiff() throws {
		let n = node([1,2,3,4,5])
		let s = session(n)
		let query = ConcordReconcile(sections:[.idList(nil, [TestID(RAW_native:2), TestID(RAW_native:9)])])
		let outcome = try s.processReconcile(query, isInitiator:true)
		#expect(outcome.reply == nil)
		#expect(outcome.have == [TestID(RAW_native:1), TestID(RAW_native:3), TestID(RAW_native:4), TestID(RAW_native:5)])
		#expect(outcome.need == [TestID(RAW_native:9)])
	}

	@Test("a skip followed by a mismatch flushes the skip first")
	func skipFlush() throws {
		let n = node([1,2,3,4,5])
		let s = session(n, role:.responder)
		// first range [start, 3) matches (fingerprint over keys 1,2), then the
		// remaining range [3, end) mismatches.
		let firstFP = try n.fingerprint(of:nil, TestID(RAW_native:3))
		let wrong = try n.fingerprint(of:TestID(RAW_native: 11), TestID(RAW_native: 22))
		let query = ConcordReconcile(sections:[
			.fingerprint(TestID(RAW_native:3), firstFP),
			.fingerprint(nil, wrong),
		])
		let outcome = try s.processReconcile(query, isInitiator:false)
		guard let reply = outcome.reply, reply.count == 2 else {
			Issue.record("expected skip + split reply")
			return
		}
		guard case .skip(let skipBound) = reply[0], case .idList(let listBound, _) = reply[1] else {
			Issue.record("expected skip then idList")
			return
		}
		#expect(skipBound == TestID(RAW_native:3))
		#expect(listBound == nil)
	}

	// MARK: validation

	@Test("an empty reconcile message is rejected")
	func emptyReconcileRejected() throws {
		let s = session(node(), role:.responder)
		#expect(throws:ConcordError.emptyReconcile) {
			_ = try s.processReconcile(ConcordReconcile(sections:[]), isInitiator:false)
		}
	}

	@Test("non-increasing bounds are rejected")
	func nonIncreasingRejected() throws {
		let s = session(node(), role:.responder)
		let query = ConcordReconcile(sections:[
			.skip(TestID(RAW_native:5)),
			.skip(TestID(RAW_native:3)),
		])
		#expect(throws:ConcordError.nonIncreasingBounds) {
			_ = try s.processReconcile(query, isInitiator:false)
		}
	}

	@Test("a nil bound in a non-final section is rejected")
	func nilBoundNotLastRejected() throws {
		let s = session(node(), role:.responder)
		let query = ConcordReconcile(sections:[
			.fingerprint(nil, try node([1]).fingerprint(of:nil, nil)),
			.skip(TestID(RAW_native:1)),
		])
		#expect(throws:ConcordError.nonIncreasingBounds) {
			_ = try s.processReconcile(query, isInitiator:false)
		}
	}

	// MARK: scripted session robustness

	@Test("the responder terminates on a leading finish")
	func responderFinishFirst() throws {
		let t = ScriptedTransport<TestID, TestValue>(messages:[.finish])
		let s = ConcordSession(index:node(), transport:t, role:.responder)
		try s.runRound()
	}

	@Test("the responder rejects an empty reconcile")
	func responderEmptyReconcileThrows() throws {
		let t = ScriptedTransport<TestID, TestValue>(messages:[.reconcile(ConcordReconcile(sections:[]))])
		let s = ConcordSession(index:node(), transport:t, role:.responder)
		#expect(throws:ConcordError.emptyReconcile) {
			try s.runRound()
		}
	}

	@Test("the responder raises missingKey for an absent key")
	func responderMissingKey() throws {
		let t = ScriptedTransport<TestID, TestValue>(messages:[.dataQuery(TestID(RAW_native:99))])
		let s = ConcordSession(index:node(), transport:t, role:.responder)
		#expect(throws:ConcordError.missingKey) {
			try s.runRound()
		}
	}

	@Test("the responder stores pushed data verbatim")
	func responderStoresData() throws {
		let n = node([1,2,3])
		let t = ScriptedTransport<TestID, TestValue>(messages:[
			.data(key:TestID(RAW_native:7), bytes:ConcordOwnedBytes(seededValueBytes(forKey:7))),
			.finish,
		])
		let s = ConcordSession(index:n, transport:t, role:.responder)
		try s.runRound()
		#expect(n.contains(TestID(RAW_native:7)))
		#expect(n.valueBytes(for:TestID(RAW_native:7)) == seededValueBytes(forKey:7))
		#expect(n.accounting.storeBytesCount == 1)
	}

	@Test("the initiator rejects an unexpected finish")
	func initiatorUnexpectedFinish() throws {
		let t = ScriptedTransport<TestID, TestValue>(messages:[.finish])
		let s = ConcordSession(index:node(), transport:t, role:.initiator)
		#expect(throws:ConcordError.unexpectedFinish) {
			try s.runRound()
		}
	}

	@Test("the initiator rejects an unexpected dataQuery")
	func initiatorUnexpectedDataQuery() throws {
		let t = ScriptedTransport<TestID, TestValue>(messages:[.dataQuery(TestID(RAW_native:1))])
		let s = ConcordSession(index:node(), transport:t, role:.initiator)
		#expect(throws:ConcordError.unexpectedDataQuery) {
			try s.runRound()
		}
	}

	@Test("a closed transport before the round completes is prematureClose")
	func prematureClose() throws {
		let initiator = ScriptedTransport<TestID, TestValue>(messages:[])
		let s1 = ConcordSession(index:node(), transport:initiator, role:.initiator)
		#expect(throws:ConcordError.prematureClose) {
			try s1.runRound()
		}
		let responder = ScriptedTransport<TestID, TestValue>(messages:[])
		let s2 = ConcordSession(index:node(), transport:responder, role:.responder)
		#expect(throws:ConcordError.prematureClose) {
			try s2.runRound()
		}
	}

	@Test("transport errors propagate untouched")
	func transportErrorPropagates() throws {
		let t = ScriptedTransport<TestID, TestValue>(messages:[.finish], failReceiveAfter:0, error:TestError.boom)
		let s = ConcordSession(index:node(), transport:t, role:.initiator)
		#expect(throws:TestError.boom) {
			try s.runRound()
		}
	}
}
