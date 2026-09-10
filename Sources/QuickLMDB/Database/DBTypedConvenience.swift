import CLMDB
import RAW

// typed-handle companions for the boundary-dialect verbs: the type-complete
// tx-bearing members the trailing verbs lower to, and the explicit-tx surface
// available directly inside a `@MDB_transact` body (cursors, dup iteration,
// raw reads) via the injected `tx_<E>` name.
//
// the boundary dialect lowers these:
//   #MDB_entry_load(   env:, db:, key:)            -> db.load(    key:, tx:)
//   #MDB_entry_store(  env:, db:, key:, value:)    -> db.store(   key:, value:, tx:)
//
// deliberately ABSENT: a DB-level `contains(key:value:)` pair check. mdb_get
// resolves by key only, so a pair form would be a silent no-op (answered true
// for any existing key); the pair check is cursor-only (real MDB_GET_BOTH).

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

// - MARK: self-scoped committed reads

// verification reads (tests, health checks) that manage their own read
// transaction — "what is the last committed state" without manual transaction
// ceremony. these are NOT verbs/boundaries: a verb's contract is boundary
// participation, the opposite of a self-scoped read. deliberately absent from
// the boundary vocabulary for that reason.

extension MDB_db {

	/// reads the last committed value for `key` through a self-scoped read-only
	/// transaction that this call creates and closes. notFound yields nil.
	/// - parameters:
	/// 	- key: the key to read.
	/// - returns: the stored value, or nil if the key does not exist.
	@available(*, noasync)
	public borrowing func readCommitted(key:borrowing MDB_db_key_type) throws -> MDB_db_val_type? {
		// only the transaction creation can throw; the typed load is non-throwing
		let tx = try Transaction(env:self.dbEnvironment(), readOnly:true)
		let result = self.load(key:key, tx:tx)
		tx.abort()
		return result
	}

	/// true when the last committed state contains `key`.
	/// - parameters:
	/// 	- key: the key to check.
	/// - returns: true if an entry exists in the committed state, false if not.
	@available(*, noasync)
	public borrowing func containsCommitted(key:borrowing MDB_db_key_type) throws -> Bool {
		let tx = try Transaction(env:self.dbEnvironment(), readOnly:true)
		do {
			let result = try self.contains(key:key, tx:tx)
			tx.abort()
			return result
		} catch {
			tx.abort()
			throw error
		}
	}
}

extension MDB_db_dupsort {

	/// reads every LAST COMMITTED duplicate value for `key` through a self-scoped
	/// read-only transaction. an absent key yields an empty array.
	/// - parameters:
	/// 	- key: the key whose duplicates to read.
	/// - returns: every duplicate stored for `key`, in key order.
	@available(*, noasync)
	public borrowing func readCommittedDups(key:borrowing MDB_db_key_type) throws -> [MDB_db_val_type] {
		let tx = try Transaction(env:self.dbEnvironment(), readOnly:true)
		do {
			var result:[MDB_db_val_type] = []
			if try self.contains(key:key, tx:tx) {
				// makeDupIterator consumes its key; an explicit copy flows out of
				// the borrowing param into the non-escaping cursor closure
				let keyCopy = copy key
				self.cursor(tx:tx) { cursor in
					for (_, dup) in cursor.makeDupIterator(key:keyCopy) {
						result.append(dup)
					}
				}
			}
			tx.abort()
			return result
		} catch {
			tx.abort()
			throw error
		}
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
