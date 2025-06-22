import CLMDB
import RAW

// delete entry
internal func MDB_cursor_delete_current_entry_static<C:MDB_cursor>(cursor:borrowing C, flags:consuming Operation.Flags) throws(LMDBError) {
	let result = mdb_cursor_del(cursor.cursorHandle(), flags.rawValue)
	guard result == MDB_SUCCESS else {
		throw LMDBError(returnCode:result)
	}
}

// contains entry
internal func MDB_cursor_contains_entry_static<C:MDB_cursor>(cursor:borrowing C, key keyVal:inout CLMDB.MDB_val) throws(LMDBError) -> Bool {
	let result = mdb_cursor_get(cursor.cursorHandle(), &keyVal, nil, Operation.set.mdbValue)
	switch result {
	case MDB_SUCCESS:
		return true
	case MDB_NOTFOUND:
		return false
	default:
		throw LMDBError(returnCode:result)
	}
}

// check for the existence of an entry.
internal func MDB_cursor_contains_entry_static<C:MDB_cursor>(cursor:borrowing C, key keyVal:inout CLMDB.MDB_val, value valueVal:inout CLMDB.MDB_val) throws(LMDBError) -> Bool {
	let result = mdb_cursor_get(cursor.cursorHandle(), &keyVal, &valueVal, Operation.getBoth.mdbValue)
	switch result {
	case MDB_SUCCESS:
		return true
	case MDB_NOTFOUND:
		return false
	default:
		throw LMDBError(returnCode:result)
	}
}

// get entry (key, value)
internal func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:consuming Operation, key keyVal:inout CLMDB.MDB_val, value valueVal:inout CLMDB.MDB_val) throws(LMDBError) {
	let cursorResult = mdb_cursor_get(cursor.cursorHandle(), &keyVal, &valueVal, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
}

// set entries from a cursor
internal func MDB_cursor_set_entry_static<C:MDB_cursor>(cursor:borrowing C, key keyVal:inout CLMDB.MDB_val, value valueVal:inout CLMDB.MDB_val, flags:consuming Operation.Flags) throws(LMDBError) {
	let result = mdb_cursor_put(cursor.cursorHandle(), &keyVal, &valueVal, flags.rawValue)
	guard result == MDB_SUCCESS else {
		throw LMDBError(returnCode:result)
	}
}

internal func MDB_cursor_compare_keys_static<C:MDB_cursor>(cursor:borrowing C, lhs dataL:inout CLMDB.MDB_val, rhs dataR:inout CLMDB.MDB_val) -> Int32 {
	let result = mdb_cmp(cursor.txHandle(), cursor.dbHandle(), &dataL, &dataR)
	return result
}

internal func MDB_cursor_compare_values_static<C:MDB_cursor>(cursor:borrowing C, lhs dataL:inout CLMDB.MDB_val, rhs dataR:inout CLMDB.MDB_val) -> Int32 {
	let result = mdb_dcmp(cursor.txHandle(), cursor.dbHandle(), &dataL, &dataR)
	return result
}

internal func MDB_cursor_get_dupcount_static<C:MDB_cursor>(cursor:borrowing C) throws(LMDBError) -> size_t {
	var count:size_t = 0
	let result = mdb_cursor_count(cursor.cursorHandle(), &count)
	guard result == MDB_SUCCESS else {
		throw LMDBError(returnCode:result)
	}
	return count
}
