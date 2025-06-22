import CLMDB
import RAW

// get entries (by key, returns value)
// - regardless of log mode, this function will assert that a valid database pointer is being returned when compiled in DEBUG mode.
internal func MDB_db_get_entry_static<D:MDB_db>(db database:borrowing D, key keyVal:inout MDB_val, tx:borrowing Transaction) throws(LMDBError) -> MDB_val {
	var valueVal = MDB_val.uninitialized()
	#if DEBUG
	let trashPtr = valueVal.mv_data
	#endif
	let cursorResult = mdb_get(tx.txHandle(), database.dbHandle(), &keyVal, &valueVal)
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
internal func MDB_db_set_entry_static<D:MDB_db>(db database:borrowing D, key keyVal:inout MDB_val, value valueVal:inout MDB_val, flags:consuming Operation.Flags, tx:borrowing Transaction) throws(LMDBError) {
	#if DEBUG
	assert(flags.contains(.reserve) == false, "cannot use MDB_RESERVE on non-returning MDB_db_set_entry_static")
	#endif
	let cursorResult = mdb_put(tx.txHandle(), database.dbHandle(), &keyVal, &valueVal, flags.rawValue)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
	#if DEBUG
	assert(valueVal.mv_data != nil, "mdb_put did not rewrite the value with the pointers in the database")
	#endif
}

// set entry returns value pointer [RETURNS]
internal func MDB_db_set_entry_static<D:MDB_db>(db database:borrowing D, returning:MDB_val.Type, key keyVal:inout MDB_val, value valueVal:inout MDB_val, flags:consuming Operation.Flags, tx:borrowing Transaction) throws(LMDBError) -> MDB_val {
	#if DEBUG
	let inPtr = valueVal.mv_data
	#endif
	let cursorResult = mdb_put(tx.txHandle(), database.dbHandle(), &keyVal, &valueVal, flags.rawValue)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
	#if DEBUG
	assert(valueVal.mv_data != inPtr, "mdb_put did not rewrite the value with the pointers in the database")
	#endif
	return valueVal
}


// check for entry (key and optional value)
internal func MDB_db_contains_entry_static<D:MDB_db>(db database:borrowing D, key keyVal:inout MDB_val, tx:borrowing Transaction) throws(LMDBError) -> Bool {
	let searchKey = mdb_get(tx.txHandle(), database.dbHandle(), &keyVal, nil)
	switch searchKey {
		case MDB_SUCCESS:
			return true
		case MDB_NOTFOUND:
			return false
		default:
			throw LMDBError(returnCode:searchKey)
	}
}
// contains entry (key, value) [logged]
internal func MDB_db_contains_entry_static<D:MDB_db>(db database:borrowing D, key keyVal:inout MDB_val, value valueVal:inout MDB_val, tx:borrowing Transaction) throws(LMDBError) -> Bool {
	let searchKey = mdb_get(tx.txHandle(), database.dbHandle(), &keyVal, &valueVal)
	switch searchKey {
		case MDB_SUCCESS:
			return true
		case MDB_NOTFOUND:
			return false
		default:
			throw LMDBError(returnCode:searchKey)
	}
}

// delete entry (key) [logged]
internal func MDB_db_delete_entry_static<D:MDB_db>(db database:borrowing D, key keyVal:inout MDB_val, tx:borrowing Transaction) throws(LMDBError) {
	let deleteResult = mdb_del(tx.txHandle(), database.dbHandle(), &keyVal, nil)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}

// delete entry (key, value) [logged]
internal func MDB_db_delete_entry_static<D:MDB_db>(db database:borrowing D, key keyVal:inout MDB_val, value valueVal:inout MDB_val, tx:borrowing Transaction) throws(LMDBError) {
	let deleteResult = mdb_del(tx.txHandle(), database.dbHandle(), &keyVal, &valueVal)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}

// delete all entries
internal func MDB_db_delete_all_entries_static<D:MDB_db>(db database:borrowing D, tx:borrowing Transaction) throws(LMDBError) {
	let deleteResult = mdb_drop(tx.txHandle(), database.dbHandle(), 0)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}

// statistics
internal func MDB_db_get_statistics_static<D:MDB_db>(db database:borrowing D, tx:borrowing Transaction) throws(LMDBError) -> MDB_stat {
	var statObj = MDB_stat()
	let getStatTry = mdb_stat(tx.txHandle(), database.dbHandle(), &statObj)
	guard getStatTry == MDB_SUCCESS else {
		throw LMDBError(returnCode:getStatTry)
	}
	return statObj
}

// flags
internal func MDB_db_get_flags_static<D:MDB_db>(db database:borrowing D, tx:borrowing Transaction) throws(LMDBError) -> UInt32 {
	var flagsOut:UInt32 = 0
	let returnCode = mdb_dbi_flags(tx.txHandle(), database.dbHandle(), &flagsOut)
	guard returnCode == MDB_SUCCESS else {
		throw LMDBError(returnCode:returnCode)
	}
	return flagsOut
}

// compare key set
internal func MDB_db_assign_compare_key_f<D:MDB_db>(db database:borrowing D, type assignType:MDB_comparable.Type, tx:borrowing Transaction) {
	let setCmpResult = mdb_set_compare(tx.txHandle(), database.dbHandle(), assignType.MDB_compare_f)
	guard setCmpResult == MDB_SUCCESS else {
		fatalError("failed to assign compare function to database")
	}
}

// compare data set
internal func MDB_db_assign_compare_val_f<D:MDB_db>(db database:borrowing D, type assignType:MDB_comparable.Type, tx:borrowing Transaction) {
	let setCmpResult = mdb_set_dupsort(tx.txHandle(), database.dbHandle(), assignType.MDB_compare_f)
	guard setCmpResult == MDB_SUCCESS else {
		fatalError("failed to assign compare function to database")
	}
}