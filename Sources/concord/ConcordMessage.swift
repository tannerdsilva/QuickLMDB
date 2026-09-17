import QuickLMDB

/// a single section of a reconciliation stream.
///
/// sections are ordered by ascending bound over the key space. a bound is a
/// full `Key` value (or nil, meaning "to the end of the key space"); the
/// common-prefix bound compression of the original negentropy wire format is a
/// transport concern and lives in the developer's serializer, not here.
public enum ConcordSection<Key:ConcordKey>:Sendable {
	/// the peer's range up to `bound` matches ours — skip it.
	case skip(Key?)
	/// the peer's digest for the range up to `bound`; compare, split on mismatch.
	case fingerprint(Key?, Fingerprint)
	/// the peer's full key list for the range up to `bound`.
	case idList(Key?, [Key])
}

public extension ConcordSection {
	/// the exclusive upper bound of this section's range (nil = end of space).
	var bound:Key? {
		switch self {
		case .skip(let bound):
			return bound
		case .fingerprint(let bound, _):
			return bound
		case .idList(let bound, _):
			return bound
		}
	}
}

/// a reconciliation message: an ascending stream of sections over the key space.
public struct ConcordReconcile<Key:ConcordKey>:Sendable {
	/// the sections of this message, in ascending bound order.
	public let sections:[ConcordSection<Key>]
	/// creates a reconciliation message.
	public init(sections:[ConcordSection<Key>]) {
		self.sections = sections
	}
}

/// the full conversational vocabulary of a concord round.
///
/// messages are NOT `Sendable`: a `data` payload is a `ConcordByteView` that may
/// point into a live transaction, and the whole conversation is scoped to one
/// synchronous round on one thread. `Value` is a phantom type parameter that
/// ties the transport and the index to the same schema at compile time.
public enum ConcordMessage<Key:ConcordKey, Value:MDB_convertible> {
	/// a reconciliation stream.
	case reconcile(ConcordReconcile<Key>)
	/// "send me the value for this key".
	case dataQuery(Key)
	/// a full entry: a key and the value's bytes verbatim from the sender's store.
	case data(key:Key, bytes:any ConcordByteView)
	/// the round is complete.
	case finish
}
