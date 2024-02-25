import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

// get entries (by key, returns value)
// - regardless of log mode, this function will assert that a valid database pointer is being returned when compiled in DEBUG mode.
#if QUICKLMDB_SHOULDLOG
// get entry (key) [logged]
internal func MDB_db_get_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, key keyVal:consuming MDB_val, tx:borrowing T, logger:Logger? = nil) throws -> MDB_val {
	logger?.trace(">", metadata:["_":"MDB_db_get_entry_static(_:key:tx:)", "mdb_key_in":"\(String(describing:keyVal))"])
	var valueVal = MDB_val.uninitialized()
	#if DEBUG
	let trashPtr = valueVal.mv_data
	#endif
	let cursorResult = mdb_get(tx.handle, database.handle, &keyVal, &valueVal)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		logger?.error("!", metadata:["_":"MDB_db_get_entry_static(_:key:tx:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_return_code":"\(cursorResult)", "_throwing":"\(throwError)"])
		throw throwError
	}
	#if DEBUG
	assert(valueVal.mv_size != -1, "mdb_get did not modify the value size")
	assert(trashPtr != valueVal.mv_data, "mdb_get did not modify the value pointer")
	#endif
	logger?.trace("<", metadata:["_":"MDB_db_get_entry_static(_:key:tx:)", "mdb_val_out":"\(String(describing:valueVal))", "mdb_key_in":"\(String(describing:keyIn))", "mdb_val_in":"\(String(describing:valueIn))", "mdb_key_modified":"\(keyModified)", "mdb_val_modified":"\(valueModified)"])
	return copy valueVal
}
#else
// get entry (key)
internal func MDB_db_get_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, key keyVal:consuming MDB_val, tx:borrowing T) throws -> MDB_val {	
	var valueVal = MDB_val.uninitialized()
	#if DEBUG
	let trashPtr = valueVal.mv_data
	#endif
	let cursorResult = mdb_get(tx.handle, withUnsafePointer(to:database) { dbptr in dbptr.pointer(to:\D.handle)!.pointee }, &keyVal, &valueVal)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
	#if DEBUG
	assert(valueVal.mv_size != -1, "mdb_get did not modify the value size")
	assert(trashPtr != valueVal.mv_data, "mdb_get did not modify the value pointer")
	#endif
	return copy valueVal
}
#endif

// set entry (key, value)
#if QUICKLMDB_SHOULDLOG
// set entry returns value pointer [logged]
internal func MDB_db_set_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, flags:Operation.Flags, tx:borrowing T, logger:Logger? = nil) throws {
	logger?.trace(">", metadata:["_":"MDB_db_set_entry_static(_:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_op_flags_in":"\(String(describing:flags))"])
	#if DEBUG
	let inPtr = valueVal.mv_data
	assert(flags.contains(.reserve) == false, "cannot use MDB_RESERVE on non-returning MDB_db_set_entry_static")
	#endif
	let cursorResult = mdb_put(tx.handle, database.handle, &keyVal, &valueVal, flags.rawValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		logger?.error("!", metadata:["_":"MDB_db_set_entry_static(_:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)"])
		throw throwError
	}
	#if DEBUG
	assert(valueVal.mv_data != nil, "mdb_put did not rewrite the value with the pointers in the database")
	#endif
	logger?.trace("<", metadata:["_":"MDB_db_set_entry_static(_:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_op_flags_in":"\(String(describing:flags))"])
}
// set entry returns value pointer [logged] [RETURNS]
internal func MDB_db_set_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, returning:MDB_val.Type, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, flags:Operation.Flags, tx:borrowing T, logger:Logger? = nil) throws -> MDB_val {
	logger?.trace(">", metadata:["_":"MDB_db_set_entry_static(_:returning:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_op_flags_in":"\(String(describing:flags))"])
	#if DEBUG
	let inPtr = valueVal.mv_data
	#endif
	let cursorResult = mdb_put(tx.handle, database.handle, &keyVal, &valueVal, flags.rawValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		logger?.error("!", metadata:["_":"MDB_db_set_entry_static(_:returning:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)"])
		throw throwError
	}
	#if DEBUG
	assert(valueVal.mv_data != inPtr, "mdb_put did not rewrite the value with the pointers in the database")
	#endif
	logger?.trace("<", metadata:["_":"MDB_db_set_entry_static(_:returning:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_op_flags_in":"\(String(describing:flags))"])
	return valueVal
}
#else
// set entry (key, value)
internal func MDB_db_set_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, flags:Operation.Flags, tx:borrowing T) throws {
	let cursorResult = mdb_put(tx.handle, database.handle, &keyVal, &valueVal, flags.rawValue)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
}
// set entry (key, value) [RETURNS]
internal func MDB_db_set_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, returning:MDB_val.Type, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, flags:Operation.Flags, tx:borrowing T) throws -> MDB_val {
	#if DEBUG
	// make sure we aren't returning a pointer that was given as input
	let inPtr = valueVal.mv_data
	#endif
	let cursorResult = mdb_put(tx.handle, database.handle, &keyVal, &valueVal, flags.rawValue)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
	#if DEBUG
	assert(valueVal.mv_data != inPtr, "mdb_put did not rewrite the value with the pointers in the database")
	#endif
	return valueVal
}
#endif

// check for entry (key and optional value)
#if QUICKLMDB_SHOULDLOG
// contains entry (key) [logged]
internal func MDB_db_contains_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, key keyVal:consuming MDB_val, tx:borrowing T, logger:Logger? = nil) throws -> Bool {
	logger?.trace(">", metadata:["_":"MDB_db_contains_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a"])
	let searchKey = mdb_get(tx.handle, database.handle, &keyVal, nil)
	switch searchKey {
		case MDB_SUCCESS:
			logger?.trace("<", metadata:["_":"MDB_db_contains_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"n/a", "mdb_return_code": "\(searchKey)", "_returning": "true"])
			return true
		case MDB_NOTFOUND:
			logger?.trace("<", metadata:["_":"MDB_db_contains_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"n/a", "mdb_return_code": "\(searchKey)", "_returning": "false"])
			return false
		default:
			let throwError = LMDBError(returnCode:searchKey)
			logger?.error("!", metadata:["_":"MDB_db_contains_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"n/a", "mdb_return_code": "\(searchKey)", "_throwing": "\(throwError)"])
			throw throwError
	}
}
// contains entry (key, value) [logged]
internal func MDB_db_contains_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing T, logger:Logger? = nil) throws -> Bool {
	logger?.trace(">", metadata:["_":"MDB_db_contains_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))"])
	let searchKey = mdb_get(tx.handle, database.handle, &keyVal, &valueVal)
	switch searchKey {
		case MDB_SUCCESS:
			logger?.trace("<", metadata:["_":"MDB_db_contains_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code": "\(searchKey)", "_returning": "true"])
			return true
		case MDB_NOTFOUND:
			logger?.trace("<", metadata:["_":"MDB_db_contains_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code": "\(searchKey)", "_returning": "false"])
			return false
		default:
			let throwError = LMDBError(returnCode:searchKey)
			logger?.error("!", metadata:["_":"MDB_db_contains_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code": "\(searchKey)", "_throwing": "\(throwError)"])
			throw throwError
	}
}
#else
// contains entry (key)
internal func MDB_db_contains_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, key keyVal:consuming MDB_val, tx:borrowing T) throws -> Bool {
	let searchKey = mdb_get(tx.handle, database.handle, &keyVal, nil)
	switch searchKey {
		case MDB_SUCCESS:
			return true
		case MDB_NOTFOUND:
			return false
		default:
			throw LMDBError(returnCode:searchKey)
	}
}
// contains entry (key, value)
internal func MDB_db_contains_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing T) throws -> Bool {
	let searchKey = mdb_get(tx.handle, database.handle, &keyVal, &valueVal)
	switch searchKey {
		case MDB_SUCCESS:
			return true
		case MDB_NOTFOUND:
			return false
		default:
			throw LMDBError(returnCode:searchKey)
	}
}
#endif

// delete entry (key and optional value)
#if QUICKLMDB_SHOULDLOG
// delete entry (key) [logged]
internal func MDB_db_delete_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, key keyVal:consuming MDB_val, tx:borrowing T, logger:Logger? = nil) throws {
	logger?.trace(">", metadata:["_":"MDB_db_delete_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a"])
	let deleteResult = mdb_del(tx.handle, database.handle, &keyVal, nil)
	guard deleteResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:deleteResult)
		logger?.error("!", metadata:["_":"MDB_db_delete_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a", "mdb_return_code": "\(deleteResult)", "_throwing": "\(throwError)"])
		throw throwError
	}
	logger?.trace("<", metadata:["_":"MDB_db_delete_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a"])
}
// delete entry (key, value) [logged]
internal func MDB_db_delete_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing T, logger:Logger? = nil) throws {
	logger?.trace(">", metadata:["_":"MDB_db_delete_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))"])
	let deleteResult = mdb_del(tx.handle, database.handle, &keyVal, &valueVal)
	guard deleteResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:deleteResult)
		logger?.error("!", metadata:["_":"MDB_db_delete_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_return_code": "\(deleteResult)", "_throwing": "\(throwError)"])
		throw throwError
	}
	logger?.trace("<", metadata:["_":"MDB_db_delete_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))"])
}
#else
// delete entry (key)
internal func MDB_db_delete_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, key keyVal:consuming MDB_val, tx:borrowing T) throws {
	let deleteResult = mdb_del(tx.handle, database.handle, &keyVal, nil)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}
// delete entry (key, value)
internal func MDB_db_delete_entry_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing T) throws {
	let deleteResult = mdb_del(tx.handle, database.handle, &keyVal, &valueVal)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}
#endif

// delete all entries
#if QUICKLMDB_SHOULDLOG
// delete all entries [logged]
internal func MDB_db_delete_all_entries_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, tx:borrowing T, logger:Logger? = nil) throws {
	logger?.trace(">", metadata:["_":"MDB_db_delete_all_entries_static(_:tx:)"])
	let deleteResult = mdb_drop(tx.handle, database.handle, 0)
	guard deleteResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:deleteResult)
		logger?.error("!", metadata:["_":"MDB_db_delete_all_entries_static(_:tx:)", "mdb_return_code": "\(deleteResult)", "_throwing": "\(throwError)"])
		throw throwError
	}
	logger?.trace("<", metadata:["_":"MDB_db_delete_all_entries_static(_:tx:)"])
}
#else
// delete all entries
internal func MDB_db_delete_all_entries_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, tx:borrowing T) throws {
	let deleteResult = mdb_drop(tx.handle, database.handle, 0)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}
#endif

// statistics
#if QUICKLMDB_SHOULDLOG
internal func MDB_db_get_statistics_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, tx:borrowing T, logger:Logger? = nil) throws -> MDB_stat {
	logger?.trace(">", metadata:["_":"MDB_db_get_statistics_static(_:tx:)"])
	
	var statObj = MDB_stat()
	let getStatTry = mdb_stat(tx.handle, database.handle, &statObj)
	guard getStatTry == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:getStatTry)
		logger?.error("!", metadata:["_":"MDB_db_get_statistics_static(_:tx:)", "mdb_return_code": "\(getStatTry)", "_throwing": "\(throwError)"])
		throw throwError
	}

	logger?.trace("<", metadata:["_":"MDB_db_get_statistics_static(_:tx:)", "mdb_stat_out": "\(String(describing:statObj))"])
	return statObj
}
#else
internal func MDB_db_get_statistics_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, tx:borrowing T) throws -> MDB_stat {
	var statObj = MDB_stat()
	let getStatTry = mdb_stat(tx.handle, database.handle, &statObj)
	guard getStatTry == MDB_SUCCESS else {
		throw LMDBError(returnCode:getStatTry)
	}
	return statObj
}
#endif

// flags
#if QUICKLMDB_SHOULDLOG
internal func MDB_db_get_flags_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, tx:borrowing T, logger:Logger? = nil) throws -> UInt32 {
	logger?.trace(">", metadata:["_":"MDB_db_get_flags_static(_:tx:)"])
	var flagsOut:UInt32 = 0
	let returnCode = mdb_dbi_flags(tx.handle, database.handle, &flagsOut)
	guard returnCode == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:returnCode)
		logger?.error("!", metadata:["_":"MDB_db_get_flags_static(_:tx:)", "mdb_return_code": "\(returnCode)", "_throwing": "\(throwError)"])
		throw throwError
	}
	logger?.trace("<", metadata:["_":"MDB_db_get_flags_static(_:tx:)", "mdb_flags_out_raw-uint32":"\(String(describing:flagsOut))"])
	return flagsOut
}
#else
internal func MDB_db_get_flags_static<D:MDB_db, T:MDB_tx>(db database:borrowing D, tx:borrowing T) throws -> UInt32 {
	var flagsOut:UInt32 = 0
	let returnCode = mdb_dbi_flags(tx.handle, database.handle, &flagsOut)
	guard returnCode == MDB_SUCCESS else {
		throw LMDBError(returnCode:returnCode)
	}
	return flagsOut
}
#endif

