import CLMDB

// functional interop layer: database operations bound directly to LMDB's C
// surface by primitive handle (MDB_dbi + raw MDB_txn pointer). this module
// carries no QuickLMDB types; QuickLMDB (and macro expansions within it) call
// these to bridge typed values into raw LMDB calls.
//
// the raw handle functions (MDB_*_static) are INTERNAL — the public api surface
// of this module is the layer that takes `consuming MDB_val` arguments and
// bridges them into the internal functions with a single inout conversion.
//
// all functions are noasync and throw QuickLMDBFunctionalInterop.LMDBError.

// - MARK: shared types

/// the C compare-function shape accepted by `mdb_set_compare`/`mdb_set_dupsort`.
public typealias MDB_cmp_func_t = @convention(c) (UnsafePointer<CLMDB.MDB_val>?, UnsafePointer<CLMDB.MDB_val>?) -> Int32

// - MARK: statics (internal)

// get entries (by key, returns value)
// - regardless of log mode, this function will assert that a valid database pointer is being returned when compiled in DEBUG mode.
@available(*, noasync)
internal func MDB_db_get_entry_static(db:MDB_dbi, key:inout CLMDB.MDB_val, tx:OpaquePointer) throws(LMDBError) -> CLMDB.MDB_val {
	var valueVal = CLMDB.MDB_val()
	#if DEBUG
	let trashPtr = valueVal.mv_data
	#endif
	let cursorResult = mdb_get(tx, db, &key, &valueVal)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
	#if DEBUG
	assert(valueVal.mv_size != -1, "mdb_get did not modify the value size")
	assert(trashPtr != valueVal.mv_data, "mdb_get did not modify the value pointer")
	#endif
	return valueVal
}

// set entry (key, value)
@available(*, noasync)
internal func MDB_db_set_entry_static(db:MDB_dbi, key:inout CLMDB.MDB_val, value:inout CLMDB.MDB_val, flags:UInt32, tx:OpaquePointer) throws(LMDBError) {
	#if DEBUG
	assert(flags & UInt32(MDB_RESERVE) == 0, "cannot use MDB_RESERVE on non-returning MDB_db_set_entry_static")
	#endif
	let cursorResult = mdb_put(tx, db, &key, &value, flags)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
	#if DEBUG
	assert(value.mv_data != nil, "mdb_put did not rewrite the value with the pointers in the database")
	#endif
}

// set entry returns value pointer [RETURNS]
@available(*, noasync)
internal func MDB_db_set_entry_static(db:MDB_dbi, returning:CLMDB.MDB_val.Type, key:inout CLMDB.MDB_val, value:inout CLMDB.MDB_val, flags:UInt32, tx:OpaquePointer) throws(LMDBError) -> CLMDB.MDB_val {
	#if DEBUG
	let inPtr = value.mv_data
	#endif
	let cursorResult = mdb_put(tx, db, &key, &value, flags)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
	#if DEBUG
	assert(value.mv_data != inPtr, "mdb_put did not rewrite the value with the pointers in the database")
	#endif
	return value
}

// check for entry (key only)
@available(*, noasync)
internal func MDB_db_contains_entry_static(db:MDB_dbi, key:inout CLMDB.MDB_val, tx:OpaquePointer) throws(LMDBError) -> Bool {
	var valueVal = CLMDB.MDB_val()
	let searchKey = mdb_get(tx, db, &key, &valueVal)
	switch searchKey {
		case MDB_SUCCESS:
			return true
		case MDB_NOTFOUND:
			return false
		default:
			throw LMDBError(returnCode:searchKey)
	}
}

// check for entry (key and value)
@available(*, noasync)
internal func MDB_db_contains_entry_static(db:MDB_dbi, key:inout CLMDB.MDB_val, value:inout CLMDB.MDB_val, tx:OpaquePointer) throws(LMDBError) -> Bool {
	let searchKey = mdb_get(tx, db, &key, &value)
	switch searchKey {
		case MDB_SUCCESS:
			return true
		case MDB_NOTFOUND:
			return false
		default:
			throw LMDBError(returnCode:searchKey)
	}
}

// delete entry (key)
@available(*, noasync)
internal func MDB_db_delete_entry_static(db:MDB_dbi, key:inout CLMDB.MDB_val, tx:OpaquePointer) throws(LMDBError) {
	let deleteResult = mdb_del(tx, db, &key, nil)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}

// delete entry (key, value)
@available(*, noasync)
internal func MDB_db_delete_entry_static(db:MDB_dbi, key:inout CLMDB.MDB_val, value:inout CLMDB.MDB_val, tx:OpaquePointer) throws(LMDBError) {
	let deleteResult = mdb_del(tx, db, &key, &value)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}

// delete all entries
@available(*, noasync)
internal func MDB_db_delete_all_entries_static(db:MDB_dbi, tx:OpaquePointer) throws(LMDBError) {
	let deleteResult = mdb_drop(tx, db, 0)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}

// delete the database
@available(*, noasync)
internal func MDB_db_delete_database_static(db:MDB_dbi, tx:OpaquePointer) throws(LMDBError) {
	let deleteResult = mdb_drop(tx, db, 1)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}

// statistics
@available(*, noasync)
internal func MDB_db_get_statistics_static(db:MDB_dbi, tx:OpaquePointer) throws(LMDBError) -> MDB_stat {
	var statObj = MDB_stat()
	let getStatTry = mdb_stat(tx, db, &statObj)
	guard getStatTry == MDB_SUCCESS else {
		throw LMDBError(returnCode:getStatTry)
	}
	return statObj
}

// flags
@available(*, noasync)
internal func MDB_db_get_flags_static(db:MDB_dbi, tx:OpaquePointer) throws(LMDBError) -> UInt32 {
	var flagsOut:UInt32 = 0
	let returnCode = mdb_dbi_flags(tx, db, &flagsOut)
	guard returnCode == MDB_SUCCESS else {
		throw LMDBError(returnCode:returnCode)
	}
	return flagsOut
}

// compare key set
@available(*, noasync)
internal func MDB_db_assign_compare_key_static(db:MDB_dbi, compare:MDB_cmp_func_t, tx:OpaquePointer) {
	let setCmpResult = mdb_set_compare(tx, db, compare)
	guard setCmpResult == MDB_SUCCESS else {
		fatalError("failed to assign compare function to database")
	}
}

// compare data set
@available(*, noasync)
internal func MDB_db_assign_compare_val_static(db:MDB_dbi, compare:MDB_cmp_func_t, tx:OpaquePointer) {
	let setCmpResult = mdb_set_dupsort(tx, db, compare)
	guard setCmpResult == MDB_SUCCESS else {
		fatalError("failed to assign compare function to database")
	}
}

// - MARK: public functional surface (consuming MDB_val)

// retrieve the value for a key.
@available(*, noasync)
public func MDB_db_get_entry(db:MDB_dbi, key:consuming CLMDB.MDB_val, tx:OpaquePointer) throws(LMDBError) -> CLMDB.MDB_val {
	return try MDB_db_get_entry_static(db:db, key:&key, tx:tx)
}

// assign an entry. flags carry the LMDB write-flags bitmask (e.g. MDB_NOOVERWRITE).
@available(*, noasync)
public func MDB_db_set_entry(db:MDB_dbi, key:consuming CLMDB.MDB_val, value:consuming CLMDB.MDB_val, flags:UInt32, tx:OpaquePointer) throws(LMDBError) {
	try MDB_db_set_entry_static(db:db, key:&key, value:&value, flags:flags, tx:tx)
}

// assign an entry and return the value pointer as rewritten by LMDB (MDB_RESERVE).
@available(*, noasync)
public func MDB_db_set_entry(db:MDB_dbi, returning:CLMDB.MDB_val.Type, key:consuming CLMDB.MDB_val, value:consuming CLMDB.MDB_val, flags:UInt32, tx:OpaquePointer) throws(LMDBError) -> CLMDB.MDB_val {
	return try MDB_db_set_entry_static(db:db, returning:returning, key:&key, value:&value, flags:flags, tx:tx)
}

// check whether an entry exists for the key.
@available(*, noasync)
public func MDB_db_contains_entry(db:MDB_dbi, key:consuming CLMDB.MDB_val, tx:OpaquePointer) throws(LMDBError) -> Bool {
	return try MDB_db_contains_entry_static(db:db, key:&key, tx:tx)
}

// check whether the key exists. matching is by key only (mdb_get semantics).
@available(*, noasync)
public func MDB_db_contains_entry(db:MDB_dbi, key:consuming CLMDB.MDB_val, value:consuming CLMDB.MDB_val, tx:OpaquePointer) throws(LMDBError) -> Bool {
	return try MDB_db_contains_entry_static(db:db, key:&key, value:&value, tx:tx)
}

// delete all entries matching the key.
@available(*, noasync)
public func MDB_db_delete_entry(db:MDB_dbi, key:consuming CLMDB.MDB_val, tx:OpaquePointer) throws(LMDBError) {
	try MDB_db_delete_entry_static(db:db, key:&key, tx:tx)
}

// delete an exact key/value pairing.
@available(*, noasync)
public func MDB_db_delete_entry(db:MDB_dbi, key:consuming CLMDB.MDB_val, value:consuming CLMDB.MDB_val, tx:OpaquePointer) throws(LMDBError) {
	try MDB_db_delete_entry_static(db:db, key:&key, value:&value, tx:tx)
}

// empty the database.
@available(*, noasync)
public func MDB_db_delete_all_entries(db:MDB_dbi, tx:OpaquePointer) throws(LMDBError) {
	try MDB_db_delete_all_entries_static(db:db, tx:tx)
}

// delete the database itself from the environment.
@available(*, noasync)
public func MDB_db_delete_database(db:MDB_dbi, tx:OpaquePointer) throws(LMDBError) {
	try MDB_db_delete_database_static(db:db, tx:tx)
}

// return the database statistics (entry count, depth, page counts).
@available(*, noasync)
public func MDB_db_get_statistics(db:MDB_dbi, tx:OpaquePointer) throws(LMDBError) -> MDB_stat {
	try MDB_db_get_statistics_static(db:db, tx:tx)
}

// return the database flags as a raw bitmask.
@available(*, noasync)
public func MDB_db_get_flags(db:MDB_dbi, tx:OpaquePointer) throws(LMDBError) -> UInt32 {
	try MDB_db_get_flags_static(db:db, tx:tx)
}

// assign the database's key comparison function.
@available(*, noasync)
public func MDB_db_assign_compare_key(db:MDB_dbi, compare:MDB_cmp_func_t, tx:OpaquePointer) {
	MDB_db_assign_compare_key_static(db:db, compare:compare, tx:tx)
}

// assign the database's duplicate-value comparison function.
@available(*, noasync)
public func MDB_db_assign_compare_val(db:MDB_dbi, compare:MDB_cmp_func_t, tx:OpaquePointer) {
	MDB_db_assign_compare_val_static(db:db, compare:compare, tx:tx)
}
