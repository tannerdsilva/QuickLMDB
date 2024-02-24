import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

// get entries (by key, returns value)
#if QUICKLMDB_SHOULDLOG
internal func MDB_db_get_entry_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, key keyVal:consuming MDB_val, tx:borrowing T, logger:Logger? = nil) throws -> MDB_val {
	logger?.trace(">", metadata:["_":"MDB_db_get_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))"])
	
	var valueVal = MDB_val.uninitialized()

	#if DEBUG
	let trashPtr = valueVal.mv_data
	#endif

	let cursorResult = mdb_get(tx.txHandle, database.dbHandle, &keyVal, &valueVal)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		logger?.error("!", metadata:["_":"MDB_db_get_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_return_code": "\(cursorResult)", "error_thrown": "\(throwError)"])
		throw throwError
	}
	
	#if DEBUG
	assert(valueVal.mv_size != -1, "mdb_get did not modify the value size")
	assert(trashPtr != valueVal.mv_data, "mdb_get did not modify the value pointer")
	#endif

	logger?.trace("<", metadata:["_":"MDB_db_get_entry_static(_:key:tx:)", "mdb_val_out": "\(String(describing:valueVal))", "mdb_key_in": "\(String(describing:keyIn))", "mdb_val_in": "\(String(describing:valueIn))", "mdb_key_modified": "\(keyModified)", "mdb_val_modified": "\(valueModified)"])

	return valueVal
}
#else
internal func MDB_db_get_entry_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, key keyVal:consuming MDB_val, tx:borrowing T) throws -> MDB_val {	
	var valueVal = MDB_val.uninitialized()

	#if DEBUG
	let trashPtr = valueVal.mv_data
	#endif

	let cursorResult = mdb_get(tx.txHandle, database.dbHandle, &keyVal, &valueVal)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		throw throwError
	}
	
	#if DEBUG
	assert(valueVal.mv_size != -1, "mdb_get did not modify the value size")
	assert(trashPtr != valueVal.mv_data, "mdb_get did not modify the value pointer")
	#endif
	return valueVal
}
#endif

// set entry (key, value)
#if QUICKLMDB_SHOULDLOG
public func MDB_db_set_entry_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, flags:Operation.Flags, tx:borrowing T, logger:Logger? = nil) throws {
	logger?.trace(">", metadata:["_":"MDB_db_set_entry_static(_:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal.pointee))", "mdb_val_in": "\(String(describing:valueVal.pointee))"])
	
	let cursorResult = mdb_put(tx.txHandle, database.dbHandle, &keyVal, &valueVal, flags.rawValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		logger?.error("!", metadata:["_":"MDB_db_set_entry_static(_:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal.pointee))", "mdb_val_in": "\(String(describing:valueVal.pointee))", "mdb_return_code": "\(cursorResult)", "error_thrown": "\(throwError)"])
		throw throwError
	}

	logger?.trace("<", metadata:["_":"MDB_db_set_entry_static(_:key:value:flags:tx:)", "mdb_key_in": "\(String(describing:keyVal.pointee))", "mdb_val_in": "\(String(describing:valueVal.pointee))"])
}
#else
public func MDB_db_set_entry_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, flags:Operation.Flags, tx:borrowing T) throws {
	let cursorResult = mdb_put(tx.txHandle, database.dbHandle, &keyVal, &valueVal, flags.rawValue)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
}
#endif

// check for entry (key and optional value)
#if QUICKLMDB_SHOULDLOG
public func MDB_db_contains_entry_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, key keyVal:consuming MDB_val, tx:borrowing T, logger:Logger? = nil) throws -> Bool {
	logger?.trace(">", metadata:["_":"MDB_db_contains_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal.pointee))", "mdb_val_in": "n/a"])
	
	let searchKey = mdb_get(tx.txHandle, database.dbHandle, &keyVal, nil)
	switch searchKey {
		case MDB_SUCCESS:
			logger?.trace("<", metadata:["_":"MDB_db_contains_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal.pointee))", "mdb_val_in":"n/a", "mdb_return_code": "\(searchKey)", "_returning": "true"])
			return true
		case MDB_NOTFOUND:
			logger?.trace("<", metadata:["_":"MDB_db_contains_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal.pointee))", "mdb_val_in":"n/a", "mdb_return_code": "\(searchKey)", "_returning": "false"])
			return false
		default:
			let throwError = LMDBError(returnCode:searchKey)
			logger?.error("!", metadata:["_":"MDB_db_contains_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal.pointee))", "mdb_val_in":"n/a", "mdb_return_code": "\(searchKey)", "error_thrown": "\(throwError)"])
			throw throwError
	}
}
public func MDB_db_contains_entry_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing T, logger:Logger? = nil) throws -> Bool {
	logger?.trace(">", metadata:["_":"MDB_db_contains_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))"])
	
	let searchKey = mdb_get(tx.txHandle, database.dbHandle, keyVal, valueVal)
	switch searchKey {
		case MDB_SUCCESS:
			logger?.trace("<", metadata:["_":"MDB_db_contains_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code": "\(searchKey)", "_returning": "true"])
			return true
		case MDB_NOTFOUND:
			logger?.trace("<", metadata:["_":"MDB_db_contains_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code": "\(searchKey)", "_returning": "false"])
			return false
		default:
			let throwError = LMDBError(returnCode:searchKey)
			logger?.error("!", metadata:["_":"MDB_db_contains_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code": "\(searchKey)", "error_thrown": "\(throwError)"])
			throw throwError
	}
}
#else
public func MDB_db_contains_entry_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, key keyVal:consuming MDB_val, tx:borrowing T) throws -> Bool {
	let searchKey = mdb_get(tx.txHandle, database.dbHandle, &keyVal, nil)
	switch searchKey {
		case MDB_SUCCESS:
			return true
		case MDB_NOTFOUND:
			return false
		default:
			throw LMDBError(returnCode:searchKey)
	}
}
public func MDB_db_contains_entry_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing T) throws -> Bool {
	let searchKey = mdb_get(tx.txHandle, database.dbHandle, &keyVal, &valueVal)
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
public func MDB_db_delete_entry_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, key keyVal:consuming MDB_val, tx:borrowing T, logger:Logger? = nil) throws {
	logger?.trace(">", metadata:["_":"MDB_db_delete_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a"])
	
	let deleteResult = mdb_del(tx.txHandle, database.dbHandle, &keyVal, nil)
	guard deleteResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:deleteResult)
		logger?.error("!", metadata:["_":"MDB_db_delete_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a", "mdb_return_code": "\(deleteResult)", "error_thrown": "\(throwError)"])
		throw throwError
	}

	logger?.trace("<", metadata:["_":"MDB_db_delete_entry_static(_:key:tx:)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a"])
}
public func MDB_db_delete_entry_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing T, logger:Logger? = nil) throws {
	logger?.trace(">", metadata:["_":"MDB_db_delete_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal.pointee))", "mdb_val_in": "\(String(describing:valueVal?.pointee))"])
	
	let deleteResult = mdb_del(tx.txHandle, database.dbHandle, &keyVal, &valueVal)
	guard deleteResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:deleteResult)
		logger?.error("!", metadata:["_":"MDB_db_delete_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal.pointee))", "mdb_val_in": "\(String(describing:valueVal?.pointee))", "mdb_return_code": "\(deleteResult)", "error_thrown": "\(throwError)"])
		throw throwError
	}

	logger?.trace("<", metadata:["_":"MDB_db_delete_entry_static(_:key:value:tx:)", "mdb_key_in": "\(String(describing:keyVal.pointee))", "mdb_val_in": "\(String(describing:valueVal?.pointee))"])
}
#else
public func MDB_db_delete_entry_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, key keyVal:consuming MDB_val, tx:borrowing T) throws {
	let deleteResult = mdb_del(tx.txHandle, database.dbHandle, &keyVal, nil)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}
public func MDB_db_delete_entry_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing T) throws {
	let deleteResult = mdb_del(tx.txHandle, database.dbHandle, &keyVal, &valueVal)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}
#endif

// delete all entries
#if QUICKLMDB_SHOULDLOG
public func MDB_db_delete_all_entries_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, tx:borrowing T, logger:Logger? = nil) throws {
	logger?.trace(">", metadata:["_":"MDB_db_delete_all_entries_static(_:tx:)"])
	
	let deleteResult = mdb_drop(tx.txHandle, database.dbHandle, 0)
	guard deleteResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:deleteResult)
		logger?.error("!", metadata:["_":"MDB_db_delete_all_entries_static(_:tx:)", "mdb_return_code": "\(deleteResult)", "error_thrown": "\(throwError)"])
		throw throwError
	}

	logger?.trace("<", metadata:["_":"MDB_db_delete_all_entries_static(_:tx:)"])
}
#else
public func MDB_db_delete_all_entries_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, tx:borrowing T) throws {
	let deleteResult = mdb_drop(tx.txHandle, database.dbHandle, 0)
	guard deleteResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:deleteResult)
	}
}
#endif

// statistics
#if QUICKLMDB_SHOULDLOG
public func MDB_db_get_statistics_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, tx:borrowing T, logger:Logger? = nil) throws -> MDB_stat {
	logger?.trace(">", metadata:["_":"MDB_db_get_statistics_static(_:tx:)"])
	
	var statObj = MDB_stat()
	let getStatTry = mdb_stat(tx.txHandle, database.dbHandle, &statObj)
	guard getStatTry == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:getStatTry)
		logger?.error("!", metadata:["_":"MDB_db_get_statistics_static(_:tx:)", "mdb_return_code": "\(getStatTry)", "error_thrown": "\(throwError)"])
		throw throwError
	}

	logger?.trace("<", metadata:["_":"MDB_db_get_statistics_static(_:tx:)", "mdb_stat_out": "\(String(describing:statObj))"])
	return statObj
}
#else
public func MDB_db_get_statistics_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, tx:borrowing T) throws -> MDB_stat {
	var statObj = MDB_stat()
	let getStatTry = mdb_stat(tx.txHandle, database.dbHandle, &statObj)
	guard getStatTry == MDB_SUCCESS else {
		throw LMDBError(returnCode:getStatTry)
	}
	return statObj
}
#endif

// flags
#if QUICKLMDB_SHOULDLOG
public func MDB_db_get_flags_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, tx:borrowing T, logger:Logger? = nil) throws -> UInt32 {
	logger?.trace(">", metadata:["_":"MDB_db_get_flags_static(_:tx:)"])
	var flagsOut:UInt32 = 0
	let returnCode = mdb_dbi_flags(tx.txHandle, database.dbHandle, &flagsOut)
	guard returnCode == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:returnCode)
		logger?.error("!", metadata:["_":"MDB_db_get_flags_static(_:tx:)", "mdb_return_code": "\(returnCode)", "error_thrown": "\(throwError)"])
		throw throwError
	}
	logger?.trace("<", metadata:["_":"MDB_db_get_flags_static(_:tx:)", "mdb_flags_out_raw-uint32":"\(String(describing:flagsOut))"])
}
#else
public func MDB_db_get_flags_static<D:MDB_db, T:MDB_tx>(_ database:borrowing D, tx:borrowing T) throws -> UInt32 {
	var flagsOut:UInt32 = 0
	let returnCode = mdb_dbi_flags(tx.txHandle, database.dbHandle, &flagsOut)
	guard returnCode == MDB_SUCCESS else {
		throw LMDBError(returnCode:returnCode)
	}
	return flagsOut
}
#endif

