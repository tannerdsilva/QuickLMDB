import CLMDB
import RAW

// typed-handle companions for the verb-macro vocabulary. each member is the
// type-complete form of the tx-bearing requirement it calls — the value type
// rides on the handle itself, so call sites need no `as:` and no `flags: []`.
//
// these are the exact surfaces the boundary macros lower verbs to:
//   #store(db, key:, value:)        -> db.store(    key:, value:, tx:)
//   #load(db, key:)                 -> db.load(     key:, tx:)
//   #delete(db, key:)               -> db.delete(   key:, tx:)
//   #delete(db, key:, value:)       -> db.delete(   key:, value:, tx:)   (dupsort)
//   #contains(db, key:)             -> db.contains( key:, tx:)
//   #clear(db)                      -> db.deleteAllEntries(tx:)
//   #cursor(db) { c in ... }        -> db.cursor(tx:) { c in ... }
//
// deliberately ABSENT: a DB-level `contains(key:value:)` pair check. mdb_get
// resolves by key only, so a pair form would be a silent no-op (answered true
// for any existing key); the pair check is cursor-only (real MDB_GET_BOTH),
// which is what `#contains(db, key:, value:)` lowers to.

extension MDB_db {

	/// typed load — the value type rides on the handle; a missing key returns nil.
	/// - parameters:
	/// 	- key: the key to look up.
	/// 	- tx: the transaction to read through.
	/// - returns: the stored value, or nil if the key does not exist (or any
	///   other error occurs — see ``loadEntry(key:as:tx:)`` for the typed form).
	@available(*, noasync)
	public borrowing func load(key:borrowing MDB_db_key_type, tx:borrowing Transaction) -> MDB_db_val_type? {
		return try? loadEntry(key:key, as:MDB_db_val_type.self, tx:tx)
	}

	/// typed store — writes the value under the key.
	/// - parameters:
	/// 	- key: the key to write.
	/// 	- value: the value to write.
	/// 	- flags: operation flags (defaults to none).
	/// 	- tx: the transaction to write through.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be set.
	@available(*, noasync)
	public borrowing func store(key:borrowing MDB_db_key_type, value:consuming MDB_db_val_type, flags:Operation.Flags = [], tx:borrowing Transaction) throws {
		try setEntry(key:key, value:value, flags:flags, tx:tx)
	}

	/// typed delete — removes every entry matching the key.
	/// - parameters:
	/// 	- key: the key to remove.
	/// 	- tx: the transaction to write through.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be removed.
	@available(*, noasync)
	public borrowing func delete(key:borrowing MDB_db_key_type, tx:borrowing Transaction) throws {
		try deleteEntry(key:key, tx:tx)
	}

	/// typed containment — true when at least one entry exists for the key.
	/// - parameters:
	/// 	- key: the key to check.
	/// 	- tx: the transaction to read through.
	/// - returns: true if an entry exists, false if not.
	@available(*, noasync)
	public borrowing func contains(key:borrowing MDB_db_key_type, tx:borrowing Transaction) throws -> Bool {
		return try containsEntry(key:key, tx:tx)
	}
}

extension MDB_db_dupsort {

	/// typed pair delete — removes exactly the key/value pairing. only meaningful
	/// on duplicate-bearing databases, so it lives here rather than on `MDB_db`.
	/// - parameters:
	/// 	- key: the key of the pairing to remove.
	/// 	- value: the value of the pairing to remove.
	/// 	- tx: the transaction to write through.
	/// - throws: a corresponding ``LMDBError`` if the pairing could not be removed.
	@available(*, noasync)
	public borrowing func delete(key:borrowing MDB_db_key_type, value:consuming MDB_db_val_type, tx:borrowing Transaction) throws {
		try deleteEntry(key:key, value:value, tx:tx)
	}
}
