import CLMDB

// functional interop layer: cursor operations bound directly to LMDB's C
// surface by primitive handle (OpaquePointer cursor/MDB_txn, MDB_dbi). this
// module carries no QuickLMDB types; QuickLMDB cursor implementations call
// these to bridge typed values into raw LMDB calls.
//
// all functions are noasync and throw QuickLMDBFunctionalInterop.LMDBError.

// delete the current entry
@available(*, noasync)
public func MDB_cursor_delete_current_entry_static(cursor:OpaquePointer, flags:UInt32) throws(LMDBError) {
	let result = mdb_cursor_del(cursor, flags)
	guard result == MDB_SUCCESS else {
		throw LMDBError(returnCode:result)
	}
}

// check for an entry at the specified key (MDB_SET)
@available(*, noasync)
public func MDB_cursor_contains_entry_static(cursor:OpaquePointer, key:inout CLMDB.MDB_val) throws(LMDBError) -> Bool {
	let result = mdb_cursor_get(cursor, &key, nil, MDB_SET)
	switch result {
		case MDB_SUCCESS:
			return true
		case MDB_NOTFOUND:
			return false
		default:
			throw LMDBError(returnCode:result)
	}
}

// check for a key/value pair (MDB_GET_BOTH)
@available(*, noasync)
public func MDB_cursor_contains_entry_static(cursor:OpaquePointer, key:inout CLMDB.MDB_val, value:inout CLMDB.MDB_val) throws(LMDBError) -> Bool {
	let result = mdb_cursor_get(cursor, &key, &value, MDB_GET_BOTH)
	switch result {
		case MDB_SUCCESS:
			return true
		case MDB_NOTFOUND:
			return false
		default:
			throw LMDBError(returnCode:result)
	}
}

// position the cursor with the given operation and retrieve the entry
@available(*, noasync)
public func MDB_cursor_get_entry_static(cursor:OpaquePointer, op:MDB_cursor_op, key:inout CLMDB.MDB_val, value:inout CLMDB.MDB_val) throws(LMDBError) {
	let cursorResult = mdb_cursor_get(cursor, &key, &value, op)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
}

// write an entry through the cursor
@available(*, noasync)
public func MDB_cursor_set_entry_static(cursor:OpaquePointer, key:inout CLMDB.MDB_val, value:inout CLMDB.MDB_val, flags:UInt32) throws(LMDBError) {
	let result = mdb_cursor_put(cursor, &key, &value, flags)
	guard result == MDB_SUCCESS else {
		throw LMDBError(returnCode:result)
	}
}

// compare two keys using the database's key comparison function
@available(*, noasync)
public func MDB_cursor_compare_keys_static(tx:OpaquePointer, db:MDB_dbi, lhs:inout CLMDB.MDB_val, rhs:inout CLMDB.MDB_val) -> Int32 {
	return mdb_cmp(tx, db, &lhs, &rhs)
}

// compare two values using the database's value comparison function
@available(*, noasync)
public func MDB_cursor_compare_values_static(tx:OpaquePointer, db:MDB_dbi, lhs:inout CLMDB.MDB_val, rhs:inout CLMDB.MDB_val) -> Int32 {
	return mdb_dcmp(tx, db, &lhs, &rhs)
}

// return the number of duplicate entries at the current cursor position
@available(*, noasync)
public func MDB_cursor_get_dupcount_static(cursor:OpaquePointer) throws(LMDBError) -> Int {
	var count:Int = 0
	let result = mdb_cursor_count(cursor, &count)
	guard result == MDB_SUCCESS else {
		throw LMDBError(returnCode:result)
	}
	return count
}
