// (c) 
import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

// delete entry
internal func MDB_cursor_delete_current_entry_static<C:MDB_cursor>(cursor:borrowing C, flags:consuming Operation.Flags) throws(LMDBError) {
	#if QUICKLMDB_SHOULDLOG
	let flagsCopy = flags
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_delete_current_entry_static(cursor:_:)", "mdb_flags":"\(flagsCopy)"])
	let result = mdb_cursor_del(cursor.cursorHandle(), flagsCopy.rawValue)
	#else
	let result = mdb_cursor_del(cursor.cursorHandle(), flags.rawValue)
	#endif
	guard result == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:result)
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.error("!", metadata:["_":"MDB_cursor_delete_current_entry_static(cursor:_:)", "mdb_flags":"\(flagsCopy)", "mdb_return_code":"\(result)", "_throwing":"\(throwError)"])
		#endif
		throw throwError
	}
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_delete_current_entry_static(cursor:_:)", "mdb_flags":"\(flagsCopy)"])
	#endif
}

// contains entry
internal func MDB_cursor_contains_entry_static<C:MDB_cursor>(cursor:borrowing C, key keyVal:inout CLMDB.MDB_val) throws(LMDBError) -> Bool {
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_contains_entry_static(cursor:_:key:)", "mdb_key_in":"\(String(describing:keyVal))"])
	#endif
	let result = mdb_cursor_get(cursor.cursorHandle(), &keyVal, nil, Operation.set.mdbValue)
	switch result {
	case MDB_SUCCESS:
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_contains_entry_static(cursor:_:key:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_return_code":"\(result)"])
		#endif
		return true
	case MDB_NOTFOUND:
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_contains_entry_static(cursor:_:key:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_return_code":"\(result)"])
		#endif
		return false
	default:
		let throwError = LMDBError(returnCode:result)
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.error("!", metadata:["_":"MDB_cursor_contains_entry_static(cursor:_:key:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_return_code":"\(result)", "_throwing":"\(throwError)"])
		#endif
		throw throwError
	}
}

// check for the existence of an entry.
internal func MDB_cursor_contains_entry_static<C:MDB_cursor>(cursor:borrowing C, key keyVal:inout CLMDB.MDB_val, value valueVal:inout CLMDB.MDB_val) throws(LMDBError) -> Bool {
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_contains_entry_static(cursor:_:key:value:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))"])
	#endif
	let result = mdb_cursor_get(cursor.cursorHandle(), &keyVal, &valueVal, Operation.getBoth.mdbValue)
	switch result {
	case MDB_SUCCESS:
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_contains_entry_static(cursor:_:key:value:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code":"\(result)"])
		#endif
		return true
	case MDB_NOTFOUND:
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_contains_entry_static(cursor:_:key:value:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code":"\(result)"])
		#endif
		return false
	default:
		let throwError = LMDBError(returnCode:result)
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.error("!", metadata:["_":"MDB_cursor_contains_entry_static(cursor:_:key:value:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code":"\(result)", "_throwing":"\(throwError)"])
		#endif
		throw throwError
	}
}

// get entry (key, value)
internal func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:consuming Operation, key keyVal:inout CLMDB.MDB_val, value valueVal:inout CLMDB.MDB_val) throws(LMDBError) {
	
	#if QUICKLMDB_SHOULDLOG
	let copyOp = operation
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:value:)", "mdb_op_in": "\(copyOp)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))"])
	let cursorResult = mdb_cursor_get(cursor.cursorHandle(), &keyVal, &valueVal, copyOp.mdbValue)
	#else
	let cursorResult = mdb_cursor_get(cursor.cursorHandle(), &keyVal, &valueVal, operation.mdbValue)
	#endif

	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.error("!", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:value:)", "mdb_op_in": "\(copyOp)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)"])
		#endif
		throw throwError
	}
	
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:value:)", "mdb_op_in": "\(copyOp)", "mdb_key_out": "\(String(describing:keyVal))", "mdb_val_out": "\(String(describing:valueVal))"])
	#endif
}

// set entries from a cursor
internal func MDB_cursor_set_entry_static<C:MDB_cursor>(cursor:borrowing C, key keyVal:inout CLMDB.MDB_val, value valueVal:inout CLMDB.MDB_val, flags:consuming Operation.Flags) throws(LMDBError) {
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_set_entry_static(_:key:value:flags:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))"])
	#endif
	let result = mdb_cursor_put(cursor.cursorHandle(), &keyVal, &valueVal, flags.rawValue)
	guard result == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:result)
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.error("!", metadata:["_":"MDB_cursor_set_entry_static(_:key:value:flags:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code":"\(result)", "_throwing":"\(throwError)"])
		#endif
		throw throwError
	}
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_set_entry_static(_:key:value:flags:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))"])
	#endif
}

internal func MDB_cursor_compare_keys_static<C:MDB_cursor>(cursor:borrowing C, lhs dataL:inout CLMDB.MDB_val, rhs dataR:inout CLMDB.MDB_val) -> Int32 {
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_compare_keys_static(_:lhs:rhs:)", "mdb_val_l":"\(String(describing:dataL))", "mdb_val_r":"\(String(describing:dataR))"])
	#endif

	let result = mdb_cmp(cursor.txHandle(), cursor.dbHandle(), &dataL, &dataR)
	
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_compare_keys_static(_:lhs:rhs:)", "mdb_return_code":"\(result)"])
	#endif

	return result
}

internal func MDB_cursor_compare_values_static<C:MDB_cursor>(cursor:borrowing C, lhs dataL:inout CLMDB.MDB_val, rhs dataR:inout CLMDB.MDB_val) -> Int32 {
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_compare_values_static(_:lhs:rhs:)", "mdb_val_l":"\(String(describing:dataL))", "mdb_val_r":"\(String(describing:dataR))"])
	#endif

	let result = mdb_dcmp(cursor.txHandle(), cursor.dbHandle(), &dataL, &dataR)
	
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_compare_values_static(_:lhs:rhs:)", "mdb_return_code":"\(result)"])
	#endif

	return result
}

internal func MDB_cursor_get_dupcount_static<C:MDB_cursor>(cursor:borrowing C) throws(LMDBError) -> size_t {
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_get_dupcount_static(cursor:_:)"])
	#endif
	var count:size_t = 0
	let result = mdb_cursor_count(cursor.cursorHandle(), &count)
	guard result == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:result)
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.error("!", metadata:["_":"MDB_cursor_get_dupcount_static(cursor:_:)", "mdb_return_code":"\(result)", "_throwing":"\(throwError)"])
		#endif
		throw throwError
	}
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_get_dupcount_static(cursor:_:)", "mdb_return_code":"\(result)", "mdb_dupcount":"\(count)"])
	#endif
	return count
}
