import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

// get entries (by key, returns value)
// - regardless of log mode, this function will assert that a valid database pointer is being returned when compiled in DEBUG mode.
internal func MDB_db_get_entry_static<D:MDB_db>(db database:borrowing D, key keyVal:inout MDB_val, tx:borrowing Transaction) throws -> MDB_val {
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace(">", metadata:["_":"MDB_db_get_entry_static(_:key:tx:)", "mdb_key_in":"\(String(describing:keyVal))", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif
	var valueVal = MDB_val.uninitialized()
	#if DEBUG
	let trashPtr = valueVal.mv_data
	#endif
	let cursorResult = mdb_get(tx.txHandle(), database.dbHandle(), &keyVal, &valueVal)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		#if QUICKLMDB_SHOULDLOG
		database.logger()?.error("!", metadata:["_":"MDB_db_get_entry_static(_:key:tx:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_return_code":"\(cursorResult)", "_throwing":"\(throwError)", "tx_id":"\(tx.txHandle().hashValue)"])
		#endif
		throw throwError
	}
	#if DEBUG
	assert(valueVal.mv_size != -1, "mdb_get did not modify the value size")
	assert(trashPtr != valueVal.mv_data, "mdb_get did not modify the value pointer")
	#endif
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace("<", metadata:["_":"MDB_db_get_entry_static(_:key:tx:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_val_out":"\(String(describing:valueVal))", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif
	return valueVal
}

// set entry (key, value)
internal func MDB_db_set_entry_static<D:MDB_db>(db database:borrowing D, key keyVal:inout MDB_val, value valueVal:inout MDB_val, flags:consuming Operation.Flags, tx:borrowing Transaction) throws {
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace(">", metadata:["_":"MDB_db_set_entry_static(_:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_op_flags_in":"\(String(describing:copy flags))", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif
	#if DEBUG
	assert(flags.contains(.reserve) == false, "cannot use MDB_RESERVE on non-returning MDB_db_set_entry_static")
	#endif
	let cursorResult = mdb_put(tx.txHandle(), database.dbHandle(), &keyVal, &valueVal, flags.rawValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		#if QUICKLMDB_SHOULDLOG
		database.logger()?.error("!", metadata:["_":"MDB_db_set_entry_static(_:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)", "tx_id":"\(tx.txHandle().hashValue)"])
		#endif
		throw throwError
	}
	#if DEBUG
	assert(valueVal.mv_data != nil, "mdb_put did not rewrite the value with the pointers in the database")
	#endif

	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace("<", metadata:["_":"MDB_db_set_entry_static(_:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", /*"mdb_op_flags_in":"\(String(describing:copy flags))",*/"tx_id":"\(tx.txHandle().hashValue)"])
	#endif
}
// set entry returns value pointer [RETURNS]
internal func MDB_db_set_entry_static<D:MDB_db>(db database:borrowing D, returning:MDB_val.Type, key keyVal:inout MDB_val, value valueVal:inout MDB_val, flags:consuming Operation.Flags, tx:borrowing Transaction) throws -> MDB_val {
	
	#if QUICKLMDB_SHOULDLOG
	let consumeFlags = flags
	database.logger()?.trace(">", metadata:["_":"MDB_db_set_entry_static(_:returning:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_op_flags_in":"\(String(describing:consumeFlags))", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif

	#if DEBUG
	let inPtr = valueVal.mv_data
	#endif

	#if QUICKLMDB_SHOULDLOG
	let cursorResult = mdb_put(tx.txHandle(), database.dbHandle(), &keyVal, &valueVal, consumeFlags.rawValue)
	#else
	let cursorResult = mdb_put(tx.txHandle(), database.dbHandle(), &keyVal, &valueVal, flags.rawValue)
	#endif
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		#if QUICKLMDB_SHOULDLOG
		database.logger()?.error("!", metadata:["_":"MDB_db_set_entry_static(_:returning:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)", "tx_id":"\(tx.txHandle().hashValue)"])
		#endif
		throw throwError
	}
	#if DEBUG
	assert(valueVal.mv_data != inPtr, "mdb_put did not rewrite the value with the pointers in the database")
	#endif
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace("<", metadata:["_":"MDB_db_set_entry_static(_:returning:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_op_flags_in":"\(String(describing:consumeFlags))", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif
	return valueVal
}


// check for entry (key and optional value)
internal func MDB_db_contains_entry_static<D:MDB_db>(db database:borrowing D, key keyVal:inout MDB_val, tx:borrowing Transaction) throws -> Bool {
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace(">", metadata:["_":"MDB_db_contains_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif
	let searchKey = mdb_get(tx.txHandle(), database.dbHandle(), &keyVal, nil)
	switch searchKey {
		case MDB_SUCCESS:
			#if QUICKLMDB_SHOULDLOG
			database.logger()?.trace("<", metadata:["_":"MDB_db_contains_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"n/a", "mdb_return_code": "\(searchKey)", "_returning": "true", "tx_id":"\(tx.txHandle().hashValue)"])
			#endif
			return true
		case MDB_NOTFOUND:
			#if QUICKLMDB_SHOULDLOG
			database.logger()?.trace("<", metadata:["_":"MDB_db_contains_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"n/a", "mdb_return_code": "\(searchKey)", "_returning": "false", "tx_id":"\(tx.txHandle().hashValue)"])
			#endif
			return false
		default:
			let throwError = LMDBError(returnCode:searchKey)
			#if QUICKLMDB_SHOULDLOG
			database.logger()?.error("!", metadata:["_":"MDB_db_contains_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"n/a", "mdb_return_code": "\(searchKey)", "_throwing": "\(throwError)", "tx_id":"\(tx.txHandle().hashValue)"])
			#endif
			throw throwError
	}
}
// contains entry (key, value) [logged]
internal func MDB_db_contains_entry_static<D:MDB_db>(db database:borrowing D, key keyVal:inout MDB_val, value valueVal:inout MDB_val, tx:borrowing Transaction) throws -> Bool {
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace(">", metadata:["_":"MDB_db_contains_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif
	let searchKey = mdb_get(tx.txHandle(), database.dbHandle(), &keyVal, &valueVal)
	switch searchKey {
		case MDB_SUCCESS:
			#if QUICKLMDB_SHOULDLOG
			database.logger()?.trace("<", metadata:["_":"MDB_db_contains_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code": "\(searchKey)", "_returning": "true", "tx_id":"\(tx.txHandle().hashValue)"])
			#endif
			return true
		case MDB_NOTFOUND:
			#if QUICKLMDB_SHOULDLOG
			database.logger()?.trace("<", metadata:["_":"MDB_db_contains_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code": "\(searchKey)", "_returning": "false", "tx_id":"\(tx.txHandle().hashValue)"])
			#endif
			return false
		default:
			let throwError = LMDBError(returnCode:searchKey)
			#if QUICKLMDB_SHOULDLOG
			database.logger()?.error("!", metadata:["_":"MDB_db_contains_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code": "\(searchKey)", "_throwing": "\(throwError)", "tx_id":"\(tx.txHandle().hashValue)"])
			#endif
			throw throwError
	}
}

// delete entry (key) [logged]
internal func MDB_db_delete_entry_static<D:MDB_db>(db database:borrowing D, key keyVal:inout MDB_val, tx:borrowing Transaction) throws {
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace(">", metadata:["_":"MDB_db_delete_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif
	let deleteResult = mdb_del(tx.txHandle(), database.dbHandle(), &keyVal, nil)
	guard deleteResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:deleteResult)
		#if QUICKLMDB_SHOULDLOG
		database.logger()?.error("!", metadata:["_":"MDB_db_delete_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a", "mdb_return_code": "\(deleteResult)", "_throwing": "\(throwError)", "tx_id":"\(tx.txHandle().hashValue)"])
		#endif
		throw throwError
	}
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace("<", metadata:["_":"MDB_db_delete_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif
}
// delete entry (key, value) [logged]
internal func MDB_db_delete_entry_static<D:MDB_db>(db database:borrowing D, key keyVal:inout MDB_val, value valueVal:inout MDB_val, tx:borrowing Transaction) throws {
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace(">", metadata:["_":"MDB_db_delete_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif
	let deleteResult = mdb_del(tx.txHandle(), database.dbHandle(), &keyVal, &valueVal)
	guard deleteResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:deleteResult)
		#if QUICKLMDB_SHOULDLOG
		database.logger()?.error("!", metadata:["_":"MDB_db_delete_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_return_code": "\(deleteResult)", "_throwing": "\(throwError)", "tx_id":"\(tx.txHandle().hashValue)"])
		#endif
		throw throwError
	}
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace("<", metadata:["_":"MDB_db_delete_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif
}

// delete all entries
internal func MDB_db_delete_all_entries_static<D:MDB_db>(db database:borrowing D, tx:borrowing Transaction) throws {
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace(">", metadata:["_":"MDB_db_delete_all_entries_static(_:tx:)", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif
	let deleteResult = mdb_drop(tx.txHandle(), database.dbHandle(), 0)
	guard deleteResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:deleteResult)
		#if QUICKLMDB_SHOULDLOG
		database.logger()?.error("!", metadata:["_":"MDB_db_delete_all_entries_static(_:tx:)", "mdb_return_code": "\(deleteResult)", "_throwing": "\(throwError)", "tx_id":"\(tx.txHandle().hashValue)"])
		#endif
		throw throwError
	}
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace("<", metadata:["_":"MDB_db_delete_all_entries_static(_:tx:)", "tx_id":"\(tx.txHandle().hashValue)"])
	#endif
}

// statistics
internal func MDB_db_get_statistics_static<D:MDB_db>(db database:borrowing D, tx:borrowing Transaction) throws -> MDB_stat {
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace(">", metadata:["_":"MDB_db_get_statistics_static(_:tx:)"])
	#endif

	var statObj = MDB_stat()
	let getStatTry = mdb_stat(tx.txHandle(), database.dbHandle(), &statObj)
	guard getStatTry == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:getStatTry)
		#if QUICKLMDB_SHOULDLOG
		database.logger()?.error("!", metadata:["_":"MDB_db_get_statistics_static(_:tx:)", "mdb_return_code": "\(getStatTry)", "_throwing": "\(throwError)"])
		#endif
		throw throwError
	}
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace("<", metadata:["_":"MDB_db_get_statistics_static(_:tx:)", "mdb_stat_out": "\(String(describing:statObj))"])
	#endif
	return statObj
}

// flags
internal func MDB_db_get_flags_static<D:MDB_db>(db database:borrowing D, tx:borrowing Transaction) throws -> UInt32 {
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace(">", metadata:["_":"MDB_db_get_flags_static(_:tx:)"])
	#endif
	var flagsOut:UInt32 = 0
	let returnCode = mdb_dbi_flags(tx.txHandle(), database.dbHandle(), &flagsOut)
	guard returnCode == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:returnCode)
		#if QUICKLMDB_SHOULDLOG
		database.logger()?.error("!", metadata:["_":"MDB_db_get_flags_static(_:tx:)", "mdb_return_code": "\(returnCode)", "_throwing": "\(throwError)"])
		#endif
		throw throwError
	}
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace("<", metadata:["_":"MDB_db_get_flags_static(_:tx:)", "mdb_flags_out_raw-uint32":"\(String(describing:copy flagsOut))"])
	#endif
	return flagsOut
}

// compare key set
internal func MDB_db_assign_compare_key_f<D:MDB_db>(db database:borrowing D, type assignType:MDB_comparable.Type, tx:borrowing Transaction) {
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace(">", metadata:["_":"MDB_db_assign_compare_key_f(_:tx:)"])
	#endif

	let setCmpResult = mdb_set_compare(tx.txHandle(), database.dbHandle(), assignType.MDB_compare_f)
	guard setCmpResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:setCmpResult)
		#if QUICKLMDB_SHOULDLOG
		database.logger()?.error("!", metadata:["_":"MDB_db_assign_compare_key_f(_:tx:)", "mdb_return_code": "\(setCmpResult)", "_throwing": "\(throwError)"])
		#endif
		fatalError("failed to assign compare function to database")
	}

	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace("<", metadata:["_":"MDB_db_assign_compare_key_f(_:tx:)"])
	#endif
}

// compare data set
internal func MDB_db_assign_compare_val_f<D:MDB_db>(db database:borrowing D, type assignType:MDB_comparable.Type, tx:borrowing Transaction) {
	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace(">", metadata:["_":"MDB_db_assign_compare_data_f(_:tx:)"])
	#endif

	let setCmpResult = mdb_set_dupsort(tx.txHandle(), database.dbHandle(), assignType.MDB_compare_f)
	guard setCmpResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:setCmpResult)
		#if QUICKLMDB_SHOULDLOG
		database.logger()?.error("!", metadata:["_":"MDB_db_assign_compare_data_f(_:tx:)", "mdb_return_code": "\(setCmpResult)", "_throwing": "\(throwError)"])
		#endif
		fatalError("failed to assign compare function to database")
	}

	#if QUICKLMDB_SHOULDLOG
	database.logger()?.trace("<", metadata:["_":"MDB_db_assign_compare_data_f(_:tx:)"])
	#endif
}