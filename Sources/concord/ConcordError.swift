/// errors raised by the concord engine and protocol validation.
public enum ConcordError:Swift.Error, Sendable, Equatable {
	/// a reconcile message arrived with no sections.
	case emptyReconcile
	/// section bounds must be strictly increasing over the key space.
	case nonIncreasingBounds
	/// a referenced key has no entry in the local store.
	case missingKey
	/// a finish arrived before the round reached its terminal state.
	case unexpectedFinish
	/// the transport closed while the round was still expecting a message.
	case prematureClose
	/// the initiator received a dataQuery — only the responder serves them.
	case unexpectedDataQuery
}
