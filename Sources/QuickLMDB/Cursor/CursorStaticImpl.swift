// (c) 
import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

// delete entry
internal func MDB_cursor_delete_current_entry_static<C:MDB_cursor>(cursor:borrowing C, flags:Operation.Flags) throws {
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_delete_current_entry_static(cursor:_:)", "mdb_flags":"\(flags)"])
	#endif
	let result = mdb_cursor_del(cursor.cursorHandle(), flags.rawValue)
	guard result == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:result)
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.error("!", metadata:["_":"MDB_cursor_delete_current_entry_static(cursor:_:)", "mdb_flags":"\(flags)", "mdb_return_code":"\(result)", "_throwing":"\(throwError)"])
		#endif
		throw throwError
	}
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_delete_current_entry_static(cursor:_:)", "mdb_flags":"\(flags)"])
	#endif
}

// contains entry
internal func MDB_cursor_contains_entry_static<C:MDB_cursor>(cursor:borrowing C, key keyVal:inout MDB_val) throws -> Bool {
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

internal func MDB_cursor_contains_entry_static<C:MDB_cursor>(cursor:borrowing C, key keyVal:inout MDB_val, value valueVal:inout MDB_val) throws -> Bool {
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

// get entries from a cursor
internal func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:Operation) throws {
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:)", "mdb_op_in": "\(operation)", "mdb_key_in": "n/a", "mdb_val_in": "n/a"])
	#endif
	let cursorResult = mdb_cursor_get(cursor.cursorHandle(), nil, nil, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.error("!", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:)", "mdb_op_in": "\(operation)", "mdb_key_in": "n/a", "mdb_val_in": "n/a", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)"])
		#endif
		throw throwError
	}
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:)", "mdb_op_in":"\(operation)", "mdb_key_out": "n/a", "mdb_val_out": "n/a"])
	#endif
}

// get entry (key)
internal func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:Operation, key keyVal:inout MDB_val) throws {

	#if DEBUG
	// do pointer modification tracking when in debug mode. this is helpful for debugging but not something we can actually assert against, since there are some LMDB operations that do not return pointers.
	let keyIn = keyVal
	#endif

	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:)", "mdb_op_in": "\(operation)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a"])
	#endif

	let cursorResult = mdb_cursor_get(cursor.cursorHandle(), &keyVal, nil, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.error("!", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:)", "mdb_op_in": "\(operation)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)"])
		#endif
		throw throwError
	}
	
	#if DEBUG
	let keyModified = keyIn != keyVal
	assert(keyModified == true, "key value was not modified so it cannot be returned")
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:)", "mdb_op_in":"\(operation)", "mdb_key_out": "\(String(describing:keyVal))", "mdb_val_out": "n/a", "mdb_key_in": "\(String(describing:keyIn))", "mdb_val_in": "n/a", "mdb_key_modified": "\(keyModified)", "mdb_val_modified": "n/a"])
	#endif
	#else
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:)", "mdb_op_in":"\(operation)", "mdb_key_out": "\(String(describing:keyVal))", "mdb_val_out": "n/a"])
	#endif
	#endif
}
// get entry (value) [logged]
internal func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:Operation, value valueVal:inout MDB_val) throws {
	#if DEBUG
	// do pointer modification tracking when in debug mode. this is helpful for debugging but not something we can actually assert against, since there are some LMDB operations that do not return pointers.
	let valueIn = valueVal
	#endif
	
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:value:)", "mdb_op_in": "\(operation)", "mdb_key_in":"n/a", "mdb_val_in": "\(String(describing:valueVal))"])
	#endif

	let cursorResult = mdb_cursor_get(cursor.cursorHandle(), nil, &valueVal, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.error("!", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:value:)", "mdb_op_in": "\(operation)", "mdb_key_in":"n/a", "mdb_val_in": "\(String(describing:valueVal))", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)"])
		#endif
		throw throwError
	}
	#if DEBUG
	let valueModified = valueIn != valueVal
	assert(valueModified == true, "value value was not modified so it cannot be returned")
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:value:)", "mdb_key_out": "n/a", "mdb_val_out": "\(String(describing:valueVal))", "mdb_key_in": "n/a", "mdb_val_in": "\(String(describing:valueIn))", "mdb_key_modified": "n/a", "mdb_val_modified": "\(valueModified)"])
	#endif
	#else
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:value:)", "mdb_key_out": "n/a", "mdb_val_out": "\(String(describing:valueVal))"])
	#endif
	#endif
}
// get entry (key, value)
internal func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:Operation, key keyVal:inout MDB_val, value valueVal:inout MDB_val) throws {
	
	#if DEBUG
	// do pointer modification tracking when in debug mode. this is helpful for debugging but not something we can actually assert against, since there are some LMDB operations that do not return pointers.
	let keyIn = keyVal
	let valueIn = valueVal
	#endif

	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:value:)", "mdb_op_in": "\(operation)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))"])
	#endif

	let cursorResult = mdb_cursor_get(cursor.cursorHandle(), &keyVal, &valueVal, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		#if QUICKLMDB_SHOULDLOG
		cursor.logger()?.error("!", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:value:)", "mdb_op_in": "\(operation)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)"])
		#endif
		throw throwError
	}
	
	#if DEBUG
	let keyModified = keyIn != keyVal
	let valueModified = valueIn != valueVal
	assert(keyModified == true, "key value was not modified so it cannot be returned")
	assert(valueModified == true, "value value was not modified so it cannot be returned")
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:value:)", "mdb_op_in": "\(operation)", "mdb_key_out": "\(String(describing:keyVal))", "mdb_val_out": "\(String(describing:valueVal))", "mdb_key_in": "\(String(describing:keyIn))", "mdb_val_in": "\(String(describing:valueIn))", "mdb_key_modified": "\(keyModified)", "mdb_val_modified": "\(valueModified)"])
	#endif
	#else
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:value:)", "mdb_op_in": "\(operation)", "mdb_key_out": "\(String(describing:keyVal))", "mdb_val_out": "\(String(describing:valueVal))"])
	#endif
	#endif
}

// set entries from a cursor
public func MDB_cursor_set_entry_static<C:MDB_cursor>(cursor:borrowing C, key keyVal:inout MDB_val, value valueVal:inout MDB_val, flags:Operation.Flags) throws {
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

public func MDB_cursor_compare_keys_static<C:MDB_cursor>(cursor:borrowing C, lhs dataL:inout MDB_val, rhs dataR:inout MDB_val) -> Int32 {
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_compare_keys_static(_:lhs:rhs:)", "mdb_val_l":"\(String(describing:dataL))", "mdb_val_r":"\(String(describing:dataR))"])
	#endif

	let result = mdb_cmp(cursor.txHandle(), cursor.dbHandle(), &dataL, &dataR)
	
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_compare_keys_static(_:lhs:rhs:)", "mdb_return_code":"\(result)"])
	#endif

	return result
}

public func MDB_cursor_compare_values_static<C:MDB_cursor>(cursor:borrowing C, lhs dataL:inout MDB_val, rhs dataR:inout MDB_val) -> Int32 {
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace(">", metadata:["_":"MDB_cursor_compare_values_static(_:lhs:rhs:)", "mdb_val_l":"\(String(describing:dataL))", "mdb_val_r":"\(String(describing:dataR))"])
	#endif

	let result = mdb_dcmp(cursor.txHandle(), cursor.dbHandle(), &dataL, &dataR)
	
	#if QUICKLMDB_SHOULDLOG
	cursor.logger()?.trace("<", metadata:["_":"MDB_cursor_compare_values_static(_:lhs:rhs:)", "mdb_return_code":"\(result)"])
	#endif

	return result
}

public func MDB_cursor_get_dupcount_static<C:MDB_cursor>(cursor:borrowing C) throws -> size_t {
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
