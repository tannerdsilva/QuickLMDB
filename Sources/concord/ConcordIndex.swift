import QuickLMDB

/// the store-facing contract a reconciliation round needs from a strict table.
///
/// a `ConcordIndex` is a sorted, fixed-size-byte-key view over one strict
/// database. every operation is synchronous and assumes a live transaction on
/// the calling thread — the round is one long-lived write transaction, so the
/// implementation is expected to hold a `Cursor` (and its transaction) for the
/// duration of the round. ranges are half-open `[lower, upper)`; a `nil` bound
/// means unbounded (start of the store / end of the store).
///
/// values never travel as their decoded type. the reconcile phase touches keys
/// only; the data phase moves value bytes through `loadBytes`/`storeBytes` — a
/// borrowed view out, a verbatim write in. `Value` is a phantom type parameter
/// that pins the schema at compile time.
public protocol ConcordIndex<Key, Value> {
	associatedtype Key:ConcordKey
	associatedtype Value:MDB_convertible

	/// the number of entries in the store.
	func entryCount() throws -> Int

	/// the first key in the store, or nil when the store is empty.
	func firstKey() throws -> Key?

	/// the number of keys in `[lower, upper)`.
	func keyCount(in lower:Key?, _ upper:Key?) throws -> Int

	/// a blake2s fingerprint over the raw bytes of every key in `[lower, upper)`,
	/// in ascending order. an empty range hashes to the digest of empty input —
	/// deterministic and identical across implementations.
	func fingerprint(of lower:Key?, _ upper:Key?) throws -> Fingerprint

	/// hashes the first `count` keys in `[begin, end)` (fewer when fewer exist)
	/// and returns the exclusive upper boundary of the hashed bucket together
	/// with its fingerprint.
	///
	/// the boundary is the next key after the hashed bucket that is still below
	/// `end`, or `end` itself when the bucket touches the range end — a bound is
	/// a key-space value, not a store entry, so `end` need not exist in the
	/// store. when `end` is nil (whole-space) and the bucket runs out of keys,
	/// the boundary is nil.
	func fingerprintAndAdvance(begin:Key?, count:Int, end:Key?) throws -> (boundary:Key?, fingerprint:Fingerprint)

	/// visits every key in `[lower, upper)` in ascending order.
	func forEachKey(in lower:Key?, _ upper:Key?, _ body:(Key) throws -> Void) throws

	/// the value bytes for `key` as a view over existing memory when possible,
	/// or nil when the key is absent. implementations must not copy: the bytes
	/// already in the environment are the canonical artifact.
	func loadBytes(_ key:Key) throws -> (any ConcordByteView)?

	/// writes the value bytes for `key` verbatim — one copy into the store.
	func storeBytes(_ key:Key, _ content:consuming any ConcordByteView) throws
}
