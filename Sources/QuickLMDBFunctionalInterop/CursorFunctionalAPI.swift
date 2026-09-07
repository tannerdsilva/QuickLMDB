import CLMDB

// functional interop layer: cursor operations bound directly to LMDB's C
// surface by primitive handle (OpaquePointer cursor/MDB_txn, MDB_dbi). this
// module carries no QuickLMDB types; QuickLMDB cursor implementations call
// these to bridge typed values into raw LMDB calls.
//
// the raw handle functions (MDB_*_static) are INTERNAL — the public api surface
// of this module is the layer that takes `consuming MDB_val` arguments and
// bridges them into the internal functions with a single inout conversion.
//
// all functions are noasync and throw QuickLMDBFunctionalInterop.LMDBError.

// - MARK: statics (internal)

// write an entry through the cursor
@available(*, noasync)
internal func MDB_cursor_set_entry_static(cursor:OpaquePointer, key:inout CLMDB.MDB_val, value:inout CLMDB.MDB_val, flags:UInt32) throws(LMDBError) {
	let result = mdb_cursor_put(cursor, &key, &value, flags)
	guard result == MDB_SUCCESS else {
		throw LMDBError(returnCode:result)
	}
}

// delete the current entry
@available(*, noasync)
internal func MDB_cursor_delete_current_entry_static(cursor:OpaquePointer, flags:UInt32) throws(LMDBError) {
	let result = mdb_cursor_del(cursor, flags)
	guard result == MDB_SUCCESS else {
		throw LMDBError(returnCode:result)
	}
}

// check for an entry at the specified key (MDB_SET)
@available(*, noasync)
internal func MDB_cursor_contains_entry_static(cursor:OpaquePointer, key:inout CLMDB.MDB_val) throws(LMDBError) -> Bool {
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
internal func MDB_cursor_contains_entry_static(cursor:OpaquePointer, key:inout CLMDB.MDB_val, value:inout CLMDB.MDB_val) throws(LMDBError) -> Bool {
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
internal func MDB_cursor_get_entry_static(cursor:OpaquePointer, op:MDB_cursor_op, key:inout CLMDB.MDB_val, value:inout CLMDB.MDB_val) throws(LMDBError) {
	let cursorResult = mdb_cursor_get(cursor, &key, &value, op)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
}

// return the number of duplicate entries at the current cursor position
@available(*, noasync)
internal func MDB_cursor_get_dupcount_static(cursor:OpaquePointer) throws(LMDBError) -> Int {
	var count:Int = 0
	let result = mdb_cursor_count(cursor, &count)
	guard result == MDB_SUCCESS else {
		throw LMDBError(returnCode:result)
	}
	return count
}

// compare two keys using the database's key comparison function
@available(*, noasync)
internal func MDB_cursor_compare_keys_static(tx:OpaquePointer, db:MDB_dbi, lhs:inout CLMDB.MDB_val, rhs:inout CLMDB.MDB_val) -> Int32 {
	return mdb_cmp(tx, db, &lhs, &rhs)
}

// compare two values using the database's value comparison function
@available(*, noasync)
internal func MDB_cursor_compare_values_static(tx:OpaquePointer, db:MDB_dbi, lhs:inout CLMDB.MDB_val, rhs:inout CLMDB.MDB_val) -> Int32 {
	return mdb_dcmp(tx, db, &lhs, &rhs)
}

// - MARK: public functional surface (consuming MDB_val)

// write an entry through the cursor.
@available(*, noasync)
public func MDB_cursor_set_entry(cursor:OpaquePointer, key:consuming CLMDB.MDB_val, value:consuming CLMDB.MDB_val, flags:UInt32) throws(LMDBError) {
	var key = key
	var value = value
	try MDB_cursor_set_entry_static(cursor:cursor, key:&key, value:&value, flags:flags)
}

// delete the current entry.
@available(*, noasync)
public func MDB_cursor_delete_current_entry(cursor:OpaquePointer, flags:UInt32) throws(LMDBError) {
	try MDB_cursor_delete_current_entry_static(cursor:cursor, flags:flags)
}

// check whether an entry exists at the specified key (MDB_SET).
@available(*, noasync)
public func MDB_cursor_contains_entry(cursor:OpaquePointer, key:consuming CLMDB.MDB_val) throws(LMDBError) -> Bool {
	var key = key
	return try MDB_cursor_contains_entry_static(cursor:cursor, key:&key)
}

// check whether a key/value pair exists (MDB_GET_BOTH).
@available(*, noasync)
public func MDB_cursor_contains_entry(cursor:OpaquePointer, key:consuming CLMDB.MDB_val, value:consuming CLMDB.MDB_val) throws(LMDBError) -> Bool {
	var key = key
	var value = value
	return try MDB_cursor_contains_entry_static(cursor:cursor, key:&key, value:&value)
}

// position the cursor with the given operation and return the retrieved entry.
@available(*, noasync)
public func MDB_cursor_get_entry(cursor:OpaquePointer, op:MDB_cursor_op, key:consuming CLMDB.MDB_val, value:consuming CLMDB.MDB_val) throws(LMDBError) -> (key:CLMDB.MDB_val, value:CLMDB.MDB_val) {
	var key = key
	var value = value
	try MDB_cursor_get_entry_static(cursor:cursor, op:op, key:&key, value:&value)
	return (key:key, value:value)
}

// return the number of duplicate entries at the current cursor position.
@available(*, noasync)
public func MDB_cursor_get_dupcount(cursor:OpaquePointer) throws(LMDBError) -> Int {
	try MDB_cursor_get_dupcount_static(cursor:cursor)
}

// compare two keys using the database's key comparison function.
@available(*, noasync)
public func MDB_cursor_compare_keys(tx:OpaquePointer, db:MDB_dbi, lhs:consuming CLMDB.MDB_val, rhs:consuming CLMDB.MDB_val) -> Int32 {
	var lhs = lhs
	var rhs = rhs
	return MDB_cursor_compare_keys_static(tx:tx, db:db, lhs:&lhs, rhs:&rhs)
}

// compare two values using the database's value comparison function.
@available(*, noasync)
public func MDB_cursor_compare_values(tx:OpaquePointer, db:MDB_dbi, lhs:consuming CLMDB.MDB_val, rhs:consuming CLMDB.MDB_val) -> Int32 {
	var lhs = lhs
	var rhs = rhs
	return MDB_cursor_compare_values_static(tx:tx, db:db, lhs:&lhs, rhs:&rhs)
}
