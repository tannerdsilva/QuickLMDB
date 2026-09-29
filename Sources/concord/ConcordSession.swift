import QuickLMDB

/// the role a side plays in a reconciliation round.
///
/// the role is chosen by the caller (e.g. a lexicographic public key
/// comparison) — concord never decides it. the initiator opens the round and
/// orchestrates the data transfer in both directions; the responder answers
/// queries and serves data. only the initiator accumulates the have/need diff;
/// the responder's role is to answer.
public enum ConcordRole:Sendable {
	case initiator
	case responder
}

/// runs one full reconciliation round between this side and a peer.
///
/// `index` and `transport` must be bound to the same schema. the round is
/// synchronous and blocking: `runRound` does not return until the round is
/// complete or an error is raised. per the concord design, the index is backed
/// by one long-lived write transaction for the entire round, so `runRound` is
/// invoked from the round's own dedicated thread.
public struct ConcordSession<Index:ConcordIndex, Transport:ConcordTransport>
	where Index.Key == Transport.Key, Index.Value == Transport.Value
{
	public let index:Index
	public let transport:Transport
	public let role:ConcordRole
	public let buckets:Int
	public let oneWaySync:Bool

	public init(index:Index, transport:Transport, role:ConcordRole, buckets:Int = 20, oneWaySync:Bool = false) {
		self.index = index
		self.transport = transport
		self.role = role
		self.buckets = buckets
		self.oneWaySync = oneWaySync
	}

	public func runRound() throws {
		switch role {
		case .initiator:
			try runInitiator()
		case .responder:
			try runResponder()
		}
	}

	// MARK: engine core

	/// processes one incoming reconciliation message into reply sections plus
	/// (initiator only) the have/need diff for the covered ranges.
	internal func processReconcile(_ query:ConcordReconcile<Index.Key>, isInitiator:Bool) throws -> (reply:[ConcordSection<Index.Key>]?, have:Set<Index.Key>, need:Set<Index.Key>) {
		guard !query.sections.isEmpty else {
			throw ConcordError.emptyReconcile
		}

		var have = Set<Index.Key>()
		var need = Set<Index.Key>()
		var reply:[ConcordSection<Index.Key>] = []
		var skipPending = false
		var lastBound:Index.Key? = nil

		for (sectionIndex, section) in query.sections.enumerated() {
			let bound:Index.Key? = section.bound

			if let bound = bound {
				if let lastBound = lastBound {
					guard bound > lastBound else {
						throw ConcordError.nonIncreasingBounds
					}
				}
			} else {
				// a nil bound means "to the end of the key space" — it can only
				// close the section stream.
				guard sectionIndex == query.sections.count - 1 else {
					throw ConcordError.nonIncreasingBounds
				}
			}

			// ranges are key-space terms: this section covers the local keys in
			// `[lastBound, bound)`. no seek is involved — a bound beyond the
			// local keyspace simply yields an empty range, and the index's
			// declarative range operations report the empty fingerprint.
			switch section {
			case .skip:
				skipPending = true
			case .fingerprint(_, let theirFingerprint):
				let ourFingerprint = try index.fingerprint(of: lastBound, bound)
				if ourFingerprint != theirFingerprint {
					if skipPending {
						reply.append(.skip(lastBound))
						skipPending = false
					}
					reply.append(contentsOf: try splitRange(begin: lastBound, end: bound, emittedBound: bound))
				} else {
					skipPending = true
				}
			case .idList(_, let theirIDs):
				if isInitiator {
					var theirSet = Set(theirIDs)
					try index.forEachKey(in: lastBound, bound) { ourKey in
						if theirSet.remove(ourKey) == nil {
							have.insert(ourKey)
						}
					}
					need.formUnion(theirSet)
					skipPending = true
				} else {
					var ourIDs:[Index.Key] = []
					try index.forEachKey(in: lastBound, bound) { ourKey in
						ourIDs.append(ourKey)
					}
					reply.append(.idList(bound, ourIDs))
				}
			}

			lastBound = bound
		}

		return (reply.isEmpty ? nil : reply, have, need)
	}

	/// splits `[begin, end)` of the local store into a section stream: either a
	/// single idList (small ranges) or a fingerprint per bucket (large ranges).
	///
	/// `emittedBound` is the bound stamped onto the emitted sections — the peer's
	/// original range bound for a response, or the range's own end for an
	/// initiate. it is decoupled from the computational `end` because a receiver
	/// may seek to a different key than the peer's bound when its store differs.
	internal func splitRange(begin:Index.Key?, end:Index.Key?, emittedBound:Index.Key?) throws -> [ConcordSection<Index.Key>] {
		let count = try index.keyCount(in: begin, end)
		if count < buckets * 2 {
			var ids:[Index.Key] = []
			try index.forEachKey(in: begin, end) { ids.append($0) }
			return [.idList(emittedBound, ids)]
		}

		let idsPerBucket = count / buckets
		let extra = count % buckets
		var sections:[ConcordSection<Index.Key>] = []
		var position:Index.Key? = begin
		for i in 0..<buckets {
			let bucketSize = idsPerBucket + (i < extra ? 1 : 0)
			let (boundary, fp) = try index.fingerprintAndAdvance(begin: position, count: bucketSize, end: end)
			sections.append(.fingerprint(boundary, fp))
			position = boundary
		}
		return sections
	}

	/// the initiator's opening message: a split of the whole key space, or an
	/// empty idList when the store is empty.
	internal func initiate() throws -> [ConcordSection<Index.Key>] {
		guard try index.firstKey() != nil else {
			return [.idList(nil, [])]
		}
		return try splitRange(begin: nil, end: nil, emittedBound: nil)
	}

	// MARK: roles

	/// the initiator's post-convergence data transfer: pushes its have entries
	/// (unless one-way), requests its need entries, and arms the receive budget.
	private func transferData(allHave:Set<Index.Key>, allNeed:Set<Index.Key>) throws -> Int {
		if !oneWaySync {
			for key in allHave {
				guard let value = try index.loadBytes(key) else {
					throw ConcordError.missingKey
				}
				try transport.send(.data(key: key, bytes: value))
			}
		}
		for key in allNeed {
			try transport.send(.dataQuery(key))
		}
		return allNeed.count
	}

	private func runInitiator() throws {
		var allHave = Set<Index.Key>()
		var allNeed = Set<Index.Key>()
		var breakCount = Int.max

		try transport.send(.reconcile(ConcordReconcile(sections: try initiate())))

		syncLoop: while true {
			if breakCount <= 0 {
				try transport.send(.finish)
				break syncLoop
			}
			guard let message = try transport.receive() else {
				throw ConcordError.prematureClose
			}
			switch message {
			case .reconcile(let query):
				if !query.sections.isEmpty {
					let outcome = try processReconcile(query, isInitiator: true)
					allHave.formUnion(outcome.have)
					allNeed.formUnion(outcome.need)
					if let reply = outcome.reply {
						try transport.send(.reconcile(ConcordReconcile(sections: reply)))
						continue
					}
				}
				// an empty incoming reply — or an empty own reply after
				// processing — means the key space is classified: transfer.
				breakCount = try transferData(allHave: allHave, allNeed: allNeed)
				if breakCount == 0 {
					try transport.send(.finish)
					break syncLoop
				}
				continue
			case .data(key: let key, bytes: let bytes):
				try index.storeBytes(key, bytes)
				breakCount -= 1
			case .dataQuery:
				throw ConcordError.unexpectedDataQuery
			case .finish:
				throw ConcordError.unexpectedFinish
			}
		}
	}

	private func runResponder() throws {
		listenLoop: while true {
			guard let message = try transport.receive() else {
				throw ConcordError.prematureClose
			}
			switch message {
			case .reconcile(let query):
				let outcome = try processReconcile(query, isInitiator: false)
				// the empty reply is a real message: it is the convergence
				// signal the initiator waits for.
				try transport.send(.reconcile(ConcordReconcile(sections: outcome.reply ?? [])))
			case .dataQuery(let key):
				guard let value = try index.loadBytes(key) else {
					throw ConcordError.missingKey
				}
				try transport.send(.data(key: key, bytes: value))
			case .data(key: let key, bytes: let bytes):
				try index.storeBytes(key, bytes)
			case .finish:
				break listenLoop
			}
		}
	}
}
