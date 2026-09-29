import CLMDB
import RAW

// type-safe operations for the RAW (heterogeneous) `Database` surface.
//
// a raw `Database` exchanges `MDB_val` — a zero-copy view whose bytes are only
// valid while its transaction is open, and which, when built from a value via
// `MDB_access`, points into a SCOPED temporary that dies the moment the closure
// returns. consuming such a view later writes/reads garbage (silently corrupts
// on store). these conveniences remove the `MDB_val` from the caller's hands
// entirely: they materialize the typed key/value bytes into owned storage for
// the duration of the operation and (on load) decode before returning, so no
// view ever escapes this call.
//
// rationale for existence: heterogeneous key/value stores (a `metadata` table
// holding a few distinct value types) cannot be a typed `Database.Strict<…>` —
// one handle, one value type. the verbs lower to typed companions for typed
// handles; for the raw handle the typed companions below are the smooth path.

extension Database {

	/// typed raw write. the key and value bytes are materialized inside this
	/// call, so the caller never constructs (or relapses into the scoped
	/// lifetime of) an `MDB_val`.
	/// - parameters:
	/// 	- key: the key to write (any `RAW_accessible`).
	/// 	- value: the value to write (any `RAW_accessible`).
	/// 	- flags: operation flags (defaults to none).
	/// 	- tx: the transaction to write through (WRITE transactions only).
	/// - throws: a corresponding ``LMDBError`` if the entry could not be set.
	@available(*, noasync)
	public borrowing func setEntry<K: RAW_accessible, V: RAW_accessible>(key: K, value: V, flags: Operation.Flags = [], tx: borrowing Transaction<Write>) throws {
		let keyBytes: [UInt8] = key.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self, { Array($0) })
		let valueBytes: [UInt8] = value.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self, { Array($0) })
		try keyBytes.withUnsafeBytes { keyBuf in
			try valueBytes.withUnsafeBytes { valueBuf in
				let keyVal = MDB_val(mv_size: keyBuf.count, mv_data: UnsafeMutableRawPointer(mutating: keyBuf.baseAddress!))
				let valueVal = MDB_val(mv_size: valueBuf.count, mv_data: UnsafeMutableRawPointer(mutating: valueBuf.baseAddress!))
				try setEntry(key: keyVal, value: valueVal, flags: flags, tx: tx)
			}
		}
	}

	/// typed raw read — reads, decodes, and returns in one call. a missing
	/// key (or a stored value that fails to decode) throws
	/// ``LMDBError/notFound``.
	/// - parameters:
	/// 	- key: the key to look up (any `RAW_accessible`).
	/// 	- as: the type to decode the stored value into (`RAW_decodable`).
	/// 	- tx: the transaction to read through (any mode).
	/// - returns: the decoded value.
	@available(*, noasync)
	public borrowing func loadEntry<K: RAW_accessible, V: RAW_decodable, M: TransactionMode>(key: K, as: V.Type, tx: borrowing Transaction<M>) throws -> V {
		let keyBytes: [UInt8] = key.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self, { Array($0) })
		return try keyBytes.withUnsafeBytes { keyBuf in
			let keyVal = MDB_val(mv_size: keyBuf.count, mv_data: UnsafeMutableRawPointer(mutating: keyBuf.baseAddress!))
			let stored = try loadEntry(key: keyVal, as: MDB_val.self, tx: tx)
			guard let decoded = V(RAW_decode: UnsafeRawBufferPointer(start: stored.mv_data, count: stored.mv_size)) else {
				throw LMDBError.notFound
			}
			return decoded
		}
	}
}
