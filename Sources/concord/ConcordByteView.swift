/// a view over value bytes.
///
/// this is the only way a value travels through concord. values are never
/// decoded into their typed form: the bytes that already exist in the sender's
/// store are the canonical artifact, and incoming entries are written verbatim.
///
/// `ConcordByteView` is deliberately NOT `Sendable` — a borrowed view refers to
/// memory (an mmap page, a receive buffer) that must stay alive for the
/// synchronous round. transport implementations that need to detach bytes
/// materialize a `ConcordOwnedBytes` at their own boundary.
public protocol ConcordByteView {
	/// exposes the underlying bytes for synchronous consumption.
	func withUnsafeBytes<R>(_ body:(UnsafeRawBufferPointer) throws -> R) rethrows -> R
}

/// a sendable, self-owning byte view.
///
/// suitable for test doubles and for transports that must retain a frame beyond
/// the lifetime of the round.
public struct ConcordOwnedBytes:ConcordByteView, Sendable {
	internal let bytes:[UInt8]
	/// wraps an owned byte array.
	public init(_ bytes:[UInt8]) {
		self.bytes = bytes
	}
	/// copies the contents of an arbitrary view into owned storage.
	///
	/// the one place concord itself introduces a byte copy — a transport or test
	/// double explicitly requesting detached, sendable bytes.
	public init(_ view:borrowing any ConcordByteView) throws {
		self.bytes = view.withUnsafeBytes { Array($0) }
	}
	public func withUnsafeBytes<R>(_ body:(UnsafeRawBufferPointer) throws -> R) rethrows -> R {
		return try bytes.withUnsafeBytes(body)
	}
}

/// a non-owning byte view over memory that already exists (an mmap page, a
/// transport receive buffer).
///
/// valid only while the underlying memory lives; it must not escape the
/// synchronous round.
public struct ConcordBorrowedBytes:ConcordByteView {
	internal let buffer:UnsafeRawBufferPointer
	/// wraps existing memory.
	public init(_ buffer:UnsafeRawBufferPointer) {
		self.buffer = buffer
	}
	public func withUnsafeBytes<R>(_ body:(UnsafeRawBufferPointer) throws -> R) rethrows -> R {
		return try body(buffer)
	}
}
