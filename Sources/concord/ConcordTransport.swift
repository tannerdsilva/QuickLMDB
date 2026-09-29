import QuickLMDB

/// the networking contract for a concord round.
///
/// this is the ONLY networking surface concord defines, and concord ships no
/// implementation of it. messages are typed Swift values; a transport
/// implementation owns the entire wire format on top of them (framing,
/// serialization, reliability) and routes frames wherever it wants — a
/// wireguard userspace channel, a TCP stream, an in-memory pipe, anything.
///
/// the transport is `Sendable` because it is the one object that crosses into
/// the round's dedicated thread from the caller's world. messages themselves
/// are deliberately NOT sendable — a `data` payload may be a borrowed byte view
/// into a live transaction — so a transport that must cross threads with a
/// message detaches owned bytes at its own boundary (the developer's one
/// sanctioned copy).
public protocol ConcordTransport<Key, Value>:Sendable {
	associatedtype Key:ConcordKey
	associatedtype Value:MDB_convertible

	/// delivers one message to the peer. blocking semantics are the
	/// implementation's; returns when the message is handed off.
	func send(_ message:ConcordMessage<Key, Value>) throws

	/// awaits the next message from the peer, or nil on orderly close.
	func receive() throws -> ConcordMessage<Key, Value>?

	/// tears down the transport.
	func close() throws
}
