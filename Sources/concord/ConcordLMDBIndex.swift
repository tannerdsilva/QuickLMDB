import QuickLMDB
import RAW
import RAW_blake2

/// a `ConcordIndex` over a real LMDB strict table, on the v22-rewrite dialect.
///
/// the implementation drives raw (`MDB_val`) operations through a single
/// stored `Cursor` (a class) plus the `Database` handle: every range walk and
/// fingerprint hashes the key bytes directly from the mmap (zero copies out of
/// the environment), `loadBytes` returns a borrowed view over the stored
/// value's own page (zero copies out), and `storeBytes` writes the incoming
/// bytes verbatim (one copy in).
///
/// the round's `Transaction<Write>` is deliberately NOT stored here: the
/// driver binds it, opens the database and cursor with it, and commits (or
/// aborts) it after `runRound` returns — durability is the driver's, exactly as
/// the dialect's own transaction pattern prescribes.
///
/// lifecycle rule: this index (and the cursor it holds) must be released
/// BEFORE the round's transaction commits or aborts — closing an LMDB cursor
/// after its transaction has closed reads freed memory and can trap (SIGTRAP).
/// scope the index so it deinitializes first, then commit. the class is NOT
/// `Sendable` — it is confined to the round's thread.
public final class ConcordLMDBIndex<Key:ConcordKey, Value:MDB_convertible>:ConcordIndex {
	public typealias Key = Key
	public typealias Value = Value

	/// the raw database handle over the synced table.
	private let database:Database
	/// the cursor the driver opened against the round's write transaction; the
	/// single access point for reads, writes, and the transaction handle.
	private let cursor:Cursor

	/// binds the raw database handle and a cursor opened in the round's write
	/// transaction. the caller must open both synchronously with its
	/// `Transaction<Write>` before constructing this index, and keep the
	/// transaction alive (borrowing it) until after the round completes.
	public init(database:Database, cursor:Cursor) {
		self.database = database
		self.cursor = cursor
	}

	// MARK: ConcordIndex

	public func entryCount() throws -> Int {
		return try Int(MDB_db_get_statistics(db: database.dbHandle(), tx: cursor.txHandle()).ms_entries)
	}

	public func firstKey() throws -> Key? {
		do {
			let (key, _) = try cursor.opFirst(returning:(key:MDB_val, value:MDB_val).self)
			return decode(key)
		} catch LMDBError.notFound {
			return nil
		}
	}

	public func keyCount(in lower:Key?, _ upper:Key?) throws -> Int {
		var count = 0
		try forEachKey(in: lower, upper) { _ in
			count += 1
		}
		return count
	}

	public func fingerprint(of lower:Key?, _ upper:Key?) throws -> Fingerprint {
		var hasher = try RAW_blake2.Hasher<RAW_blake2.S, [UInt8]>(outputLength: MemoryLayout<Fingerprint>.size)
		let upperBytes = upper.map { bytes($0) }
		try walk(lower: lower, upperBytes: upperBytes) { keyVal in
			try hasher.update(rawView(keyVal))
		}
		let digest = try hasher.finish()
		return digest.withUnsafeBytes { Fingerprint(RAW_decode:$0)! }
	}

	public func fingerprintAndAdvance(begin:Key?, count:Int, end:Key?) throws -> (boundary:Key?, fingerprint:Fingerprint) {
		var hasher = try RAW_blake2.Hasher<RAW_blake2.S, [UInt8]>(outputLength: MemoryLayout<Fingerprint>.size)
		let endBytes = end.map { bytes($0) }
		var current = try seekTo(begin)
		var hashed = 0
		while let (key, _) = current {
			if let endBytes = endBytes, keyIsGEQ(key, endBytes) { break }
			if hashed >= count { break }
			try hasher.update(rawView(key))
			hashed += 1
			current = try next()
		}
		let fingerprint = try hasher.finish().withUnsafeBytes { Fingerprint(RAW_decode:$0)! }
		// the exclusive upper of the bucket: the next key below `end`, or `end`
		// itself when the bucket touches the range end, or nil for an unbounded
		// tail.
		let boundary:Key?
		if let (key, _) = current {
			if let endBytes = endBytes, keyIsGEQ(key, endBytes) {
				boundary = end
			} else {
				boundary = decode(key)
			}
		} else {
			boundary = end
		}
		return (boundary, fingerprint)
	}

	public func forEachKey(in lower:Key?, _ upper:Key?, _ body:(Key) throws -> Void) throws {
		let upperBytes = upper.map { bytes($0) }
		try walk(lower: lower, upperBytes: upperBytes) { keyVal in
			guard let key = decode(keyVal) else { return }
			try body(key)
		}
	}

	public func loadBytes(_ key:Key) throws -> (any ConcordByteView)? {
		let keyBytes = bytes(key)
		return try keyBytes.withUnsafeBytes { keyBuf in
			let keyVal = MDB_val(mv_size: keyBuf.count, mv_data: self.ptr(keyBuf.baseAddress))
			do {
				// `opSet` returns the stored value's mmap page directly.
				let stored = try cursor.opSet(returning:MDB_val.self, key: keyVal)
				return ConcordBorrowedBytes(rawView(stored))
			} catch LMDBError.notFound {
				return nil
			}
		}
	}

	public func storeBytes(_ key:Key, _ content:consuming any ConcordByteView) throws {
		let valueBytes = content.withUnsafeBytes { Array($0) }
		let keyBytes = bytes(key)
		try keyBytes.withUnsafeBytes { keyBuf in
			try valueBytes.withUnsafeBytes { valueBuf in
				let keyVal = MDB_val(mv_size: keyBuf.count, mv_data: self.ptr(keyBuf.baseAddress))
				let valueVal = MDB_val(mv_size: valueBuf.count, mv_data: self.ptr(valueBuf.baseAddress))
				// raw cursor put: the cursor already carries its transaction.
				try MDB_cursor_set_entry(cursor: cursor.cursorHandle(), key: keyVal, value: valueVal, flags: 0)
			}
		}
	}

	// MARK: internals

	/// the raw byte encoding of a typed key or bound.
	private func bytes<S:RAW_accessible>(_ value:S) -> [UInt8] {
		return value.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { Array($0) }
	}

	/// a mutable raw pointer view of a buffer base, nil-safe (LMDB reads zero
	/// bytes when the size is zero, so a nil data pointer is legal then).
	private func ptr(_ base:UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
		return base.map { UnsafeMutableRawPointer(mutating:$0) }
	}

	/// a raw buffer view over `MDB_val` bytes.
	private func rawView(_ val:MDB_val) -> UnsafeRawBufferPointer {
		guard let base = val.mv_data else {
			return UnsafeRawBufferPointer(start:nil, count:0)
		}
		return UnsafeRawBufferPointer(start: UnsafeRawPointer(base), count: val.mv_size)
	}

	/// decodes a stored key view back into the typed key.
	private func decode(_ val:MDB_val) -> Key? {
		guard let base = val.mv_data else { return nil }
		var ptr = UnsafeRawPointer(base)
		return Key(RAW_staticbuff_seeking: &ptr)
	}

	/// compares a raw key view to encoded bytes, lexicographically.
	private func keyIsGEQ(_ key:MDB_val, _ reference:[UInt8]) -> Bool {
		let lhs = rawView(key)
		let result = reference.withUnsafeBytes { (refPtr:UnsafeRawBufferPointer) -> Int32 in
			let n = min(lhs.count, refPtr.count)
			if n == 0 {
				return lhs.count == refPtr.count ? 0 : (lhs.count < refPtr.count ? -1 : 1)
			}
			let cmp = memcmp(lhs.baseAddress, refPtr.baseAddress, n)
			if cmp != 0 { return cmp }
			return lhs.count == refPtr.count ? 0 : (lhs.count < refPtr.count ? -1 : 1)
		}
		return result >= 0
	}

	/// seeks the stored cursor to the first entry at or after `lower` (or the
	/// first entry when lower is nil), returning nil when none exists.
	private func seekTo(_ lower:Key?) throws -> (key:MDB_val, value:MDB_val)? {
		if let lower = lower {
			return try lower.MDB_access { keyVal in
				do {
					return try cursor.opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:keyVal)
				} catch LMDBError.notFound {
					return nil
				}
			}
		} else {
			do {
				return try cursor.opFirst(returning:(key:MDB_val, value:MDB_val).self)
			} catch LMDBError.notFound {
				return nil
			}
		}
	}

	private func next() throws -> (key:MDB_val, value:MDB_val)? {
		do {
			return try cursor.opNext(returning:(key:MDB_val, value:MDB_val).self)
		} catch LMDBError.notFound {
			return nil
		}
	}

	/// walks every entry in `[lower, upperBytes)` (unbounded where nil) and
	/// invokes `body` with each raw key view. key bytes are never copied.
	private func walk(lower:Key?, upperBytes:[UInt8]?, _ body:(MDB_val) throws -> Void) throws {
		var current = try seekTo(lower)
		while let (key, _) = current {
			if let upperBytes = upperBytes, keyIsGEQ(key, upperBytes) { break }
			try body(key)
			current = try next()
		}
	}
}
