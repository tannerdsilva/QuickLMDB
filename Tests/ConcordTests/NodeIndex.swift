@testable import concord
import Testing
import RAW
import QuickLMDB
import RAW_blake2
import Synchronization

/// an in-memory `ConcordIndex` double: a sorted key set over byte-valued
/// entries.
///
/// thread-confined: each instance is owned by exactly one thread for the
/// duration of a round, mirroring how a live transaction-bound index is used
/// in production, so the class is `@unchecked Sendable`.
final class NodeIndex<Key:ConcordKey, Value:MDB_convertible>:ConcordIndex, @unchecked Sendable {
	typealias Key = Key
	typealias Value = Value

	private var values:[Key:[UInt8]] = [:]
	private var keys:[Key] = []

	/// copy-accounting counters. `loadBytes` hands out borrowed views (zero
	/// copies out of the store); `storeBytes` performs exactly one verbatim
	/// write per entry.
	struct Accounting {
		var loadBytesCount = 0
		var borrowedViewBaseAddresses:[UnsafeRawPointer?] = []
		var storeBytesCount = 0
		var storeSizes:[Int] = []
	}
	private(set) var accounting = Accounting()

	// MARK: seeding (pre-round population, not counted as round stores)

	func seed(key:Key, value:[UInt8]) {
		if values[key] == nil {
			insertSorted(key)
		}
		values[key] = value
	}

	// MARK: inspection

	var count:Int { keys.count }
	var allKeys:[Key] { keys }
	func contains(_ key:Key) -> Bool { values[key] != nil }
	func valueBytes(for key:Key) -> [UInt8]? { values[key] }

	// MARK: ConcordIndex

	func entryCount() throws -> Int { keys.count }

	func firstKey() throws -> Key? { keys.first }

	func keyCount(in lower:Key?, _ upper:Key?) throws -> Int {
		var i = lower.map { firstIndex(atOrAfter:$0) } ?? 0
		var count = 0
		while i < keys.count {
			if let upper = upper, keys[i] >= upper { break }
			count += 1
			i += 1
		}
		return count
	}

	func fingerprint(of lower:Key?, _ upper:Key?) throws -> Fingerprint {
		var hasher = try RAW_blake2.Hasher<RAW_blake2.S, [UInt8]>(outputLength: 24)
		try forEachKey(in: lower, upper) { key in
			try hashKey(key, into: &hasher)
		}
		return try finishFingerprint(&hasher)
	}

	func fingerprintAndAdvance(begin:Key?, count:Int, end:Key?) throws -> (boundary:Key?, fingerprint:Fingerprint) {
		var hasher = try RAW_blake2.Hasher<RAW_blake2.S, [UInt8]>(outputLength: 24)
		var i = begin.map { firstIndex(atOrAfter:$0) } ?? 0
		var hashed = 0
		while i < keys.count && hashed < count {
			if let end = end, keys[i] >= end { break }
			try hashKey(keys[i], into: &hasher)
			i += 1
			hashed += 1
		}
		let fingerprint = try finishFingerprint(&hasher)
		// the exclusive upper of the bucket: the next store key below `end`, or
		// `end` itself when the bucket touches the range end, or nil for an
		// unbounded tail.
		let boundary:Key?
		if i < keys.count {
			boundary = (end != nil && keys[i] >= end!) ? end : keys[i]
		} else {
			boundary = end
		}
		return (boundary, fingerprint)
	}

	func forEachKey(in lower:Key?, _ upper:Key?, _ body:(Key) throws -> Void) throws {
		var i = lower.map { firstIndex(atOrAfter:$0) } ?? 0
		while i < keys.count {
			let key = keys[i]
			if let upper = upper, key >= upper { break }
			try body(key)
			i += 1
		}
	}

	func loadBytes(_ key:Key) throws -> (any ConcordByteView)? {
		guard let byteArray = values[key] else { return nil }
		accounting.loadBytesCount += 1
		let view = byteArray.withUnsafeBytes { ConcordBorrowedBytes($0) }
		view.withUnsafeBytes { accounting.borrowedViewBaseAddresses.append($0.baseAddress) }
		return view
	}

	func storeBytes(_ key:Key, _ content:consuming any ConcordByteView) throws {
		let bytes = content.withUnsafeBytes { Array($0) }
		if values[key] == nil {
			insertSorted(key)
		}
		values[key] = bytes
		accounting.storeBytesCount += 1
		accounting.storeSizes.append(bytes.count)
	}

	// MARK: internals

	private func firstIndex(atOrAfter bound:Key) -> Int {
		var lo = 0
		var hi = keys.count
		while lo < hi {
			let mid = (lo + hi) / 2
			if keys[mid] < bound {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		return lo
	}

	private func insertSorted(_ key:Key) {
		let i = firstIndex(atOrAfter: key)
		if i < keys.count && keys[i] == key { return }
		keys.insert(key, at: i)
	}

	private func hashKey(_ key:Key, into hasher:inout RAW_blake2.Hasher<RAW_blake2.S, [UInt8]>) throws {
		try key.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { ptr in
			try hasher.update(UnsafeRawBufferPointer(ptr))
		}
	}

	private func finishFingerprint(_ hasher:inout RAW_blake2.Hasher<RAW_blake2.S, [UInt8]>) throws -> Fingerprint {
		let digest = try hasher.finish()
		return digest.withUnsafeBytes { Fingerprint(RAW_decode:$0)! }
	}
}

/// seeds a node with `key → (key * 3 + 1)` as an 8-byte big-endian value.
func seedNode(_ node:NodeIndex<TestID, TestValue>, keyRange:Range<UInt64>) {
	for keyValue in keyRange {
		let key = TestID(RAW_native: keyValue)
		let value = TestID(RAW_native: keyValue &* 3 &+ 1)
		let bytes = value.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { Array($0) }
		node.seed(key:key, value:bytes)
	}
}

/// the expected value bytes for a seeded key.
func seededValueBytes(forKey keyValue:UInt64) -> [UInt8] {
	let value = TestID(RAW_native: keyValue &* 3 &+ 1)
	return value.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { Array($0) }
}

/// a box for collecting errors from test threads.
final class ErrorBox:@unchecked Sendable {
	private let mutex = Synchronization.Mutex(())
	private var error:Swift.Error?
	func set(_ error:Swift.Error) {
		mutex.withLock { _ in
			self.error = error
		}
	}
	var value:Swift.Error? {
		mutex.withLock { _ in error }
	}
}
