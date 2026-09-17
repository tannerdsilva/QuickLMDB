@testable import concord
import Foundation
import Synchronization
import QuickLMDB

/// a sendable mirror of a `ConcordMessage` — the "wire format" the in-memory
/// transports use to cross thread boundaries. value bytes are detached into
/// owned storage here, which is the developer's one sanctioned boundary copy.
enum WireMirror<Key:ConcordKey, Value:MDB_convertible>:@unchecked Sendable {
	case reconcile(ConcordReconcile<Key>)
	case dataQuery(Key)
	case data(Key, [UInt8])
	case finish

	init(_ message:ConcordMessage<Key, Value>) {
		switch message {
		case .reconcile(let reconcile):
			self = .reconcile(reconcile)
		case .dataQuery(let key):
			self = .dataQuery(key)
		case .data(key: let key, bytes: let bytes):
			self = .data(key, bytes.withUnsafeBytes { Array($0) })
		case .finish:
			self = .finish
		}
	}

	func asMessage() -> ConcordMessage<Key, Value> {
		switch self {
		case .reconcile(let reconcile):
			return .reconcile(reconcile)
		case .dataQuery(let key):
			return .dataQuery(key)
		case .data(let key, let bytes):
			return .data(key:key, bytes:ConcordOwnedBytes(bytes))
		case .finish:
			return .finish
		}
	}
}

/// a thread-safe blocking FIFO — one direction of the in-memory pipe.
final class BlockingQueue<T>:@unchecked Sendable {
	private let condition = NSCondition()
	private var buffer:[T] = []
	private var isClosed = false

	func enqueue(_ item:T) {
		condition.lock()
		defer { condition.unlock() }
		buffer.append(item)
		condition.signal()
	}

	/// blocks until an item arrives, the queue closes, or 30s elapse (nil).
	func dequeue() -> T? {
		condition.lock()
		defer { condition.unlock() }
		while buffer.isEmpty && !isClosed {
			if !condition.wait(until: Date().addingTimeInterval(30)) {
				return nil
			}
		}
		guard !buffer.isEmpty else { return nil }
		return buffer.removeFirst()
	}

	func close() {
		condition.lock()
		defer { condition.unlock() }
		isClosed = true
		condition.broadcast()
	}
}

/// an in-memory passthrough transport: sends flow into the peer's inbound
/// queue, receives block on the local queue. one side of a `makePair`.
final class PipeTransport<Key:ConcordKey, Value:MDB_convertible>:ConcordTransport {
	private let inbound:BlockingQueue<WireMirror<Key, Value>>
	private weak var peer:PipeTransport<Key, Value>?
	private let sentLock = Synchronization.Mutex(())
	private var sentMessages:[ConcordMessage<Key, Value>] = []

	private init() {
		self.inbound = BlockingQueue()
	}

	private func setPeer(_ peer:PipeTransport<Key, Value>) {
		self.peer = peer
	}

	func send(_ message:ConcordMessage<Key, Value>) throws {
		sentLock.withLock { _ in sentMessages.append(message) }
		peer?.inbound.enqueue(WireMirror(message))
	}

	func receive() throws -> ConcordMessage<Key, Value>? {
		guard let mirror = inbound.dequeue() else { return nil }
		return mirror.asMessage()
	}

	func close() throws {
		inbound.close()
	}

	/// the messages this side sent (safe to read after the round's threads join).
	func messagesSent() -> [ConcordMessage<Key, Value>] {
		sentLock.withLock { _ in sentMessages }
	}

	static func makePair() -> (PipeTransport<Key, Value>, PipeTransport<Key, Value>) {
		let first = PipeTransport<Key, Value>()
		let second = PipeTransport<Key, Value>()
		first.setPeer(second)
		second.setPeer(first)
		return (first, second)
	}
}

extension PipeTransport: @unchecked Sendable {}

/// a single-threaded scripted transport: consumes a preloaded inbound sequence,
/// records everything sent, and can inject a failure after N receives.
final class ScriptedTransport<Key:ConcordKey, Value:MDB_convertible>:ConcordTransport {
	private var inbound:[ConcordMessage<Key, Value>]
	private var receiveCounter = 0
	private let failAfter:Int?
	private let injectedError:Swift.Error?
	private(set) var sent:[ConcordMessage<Key, Value>] = []

	init(messages:[ConcordMessage<Key, Value>], failReceiveAfter:Int? = nil, error:Swift.Error? = nil) {
		self.inbound = messages
		self.failAfter = failReceiveAfter
		self.injectedError = error
	}

	func send(_ message:ConcordMessage<Key, Value>) throws {
		sent.append(message)
	}

	func receive() throws -> ConcordMessage<Key, Value>? {
		receiveCounter += 1
		if let failAfter = failAfter, receiveCounter > failAfter {
			throw injectedError ?? ConcordError.prematureClose
		}
		guard !inbound.isEmpty else { return nil }
		return inbound.removeFirst()
	}

	func close() throws {}
}

extension ScriptedTransport: @unchecked Sendable {}
