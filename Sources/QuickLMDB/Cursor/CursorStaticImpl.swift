import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

// get entries from a cursor
#if QUICKLMDB_SHOULDLOG
// get entry (op) [logged]
internal func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:Operation, logger:Logger? = nil) {
	logger?.trace(">", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:)", "mdb_op_in": "\(operation)", "mdb_key_in": "n/a", "mdb_val_in": "n/a"])
	let cursorResult = mdb_cursor_get(cursor.handle(), nil, nil, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		logger?.error("!", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:)", "mdb_op_in": "\(operation)", "mdb_key_in": "n/a", "mdb_val_in": "n/a", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)"])
		throw throwError
	}
	logger?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:)", "mdb_op_in":"\(operation)", "mdb_key_out": "n/a", "mdb_val_out": "n/a"])
}
// get entry (key) [logged]
internal func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:Operation, key keyVal:inout MDB_val, logger:Logger? = nil) {

	#if DEBUG
	// do pointer modification tracking when in debug mode. this is helpful for debugging but not something we can actually assert against, since there are some LMDB operations that do not return pointers.
	let keyIn = keyVal
	#endif

	logger?.trace(">", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:)", "mdb_op_in": "\(operation)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "n/a"])

	let cursorResult = mdb_cursor_get(cursor.handle(), &keyVal, &valueVal, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		logger?.error("!", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:)", "mdb_op_in": "\(operation)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)"])
		throw throwError
	}
	
	#if DEBUG
	let keyModified = keyIn != keyVal
	logger?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:)", "mdb_op_in":"\(operation)", "mdb_key_out": "\(String(describing:keyVal))", "mdb_val_out": "n/a", "mdb_key_in": "\(String(describing:keyIn))", "mdb_val_in": "n/a", "mdb_key_modified": "\(keyModified)", "mdb_val_modified": "n/a"])
	#else
	logger?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:)", "mdb_op_in":"\(operation)", "mdb_key_out": "\(String(describing:keyVal))", "mdb_val_out": "n/a"])
	#endif
}
// get entry (value) [logged]
internal func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:Operation, value valueVal:inout MDB_val, logger:Logger? = nil) throws {
	#if DEBUG
	// do pointer modification tracking when in debug mode. this is helpful for debugging but not something we can actually assert against, since there are some LMDB operations that do not return pointers.
	let valueIn = valueVal
	#endif
	
	logger?.trace(">", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:value:)", "mdb_op_in": "\(operation)", "mdb_key_in":"n/a", "mdb_val_in": "\(String(describing:valueVal))"])
	
	let cursorResult = mdb_cursor_get(cursor.handle(), nil, &valueVal, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		logger?.error("!", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:value:)", "mdb_op_in": "\(operation)", "mdb_val_in": "\(String(describing:valueVal))", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)"])
		throw throwError
	}
	#if DEBUG
	let valueModified = valueIn != valueVal
	logger?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:value:)", "mdb_key_out": "n/a", "mdb_val_out": "\(String(describing:valueVal))", "mdb_key_in": "n/a", "mdb_val_in": "\(String(describing:valueIn))", "mdb_key_modified": "\(keyModified)", "mdb_val_modified": "\(valueModified)"])
	#else
	logger?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:value:)", "mdb_key_out": "n/a", "mdb_val_out": "\(String(describing:valueVal))"])
	#endif
}
// get entry (key, value) [logged]
internal func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:Operation, key keyVal:inout MDB_val, value valueVal:inout MDB_val, logger:Logger? = nil) throws {
	
	#if DEBUG
	// do pointer modification tracking when in debug mode. this is helpful for debugging but not something we can actually assert against, since there are some LMDB operations that do not return pointers.
	let keyIn = keyVal
	let valueIn = valueVal
	#endif

	logger?.trace(">", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:value:)", "mdb_op_in": "\(operation)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))"])

	let cursorResult = mdb_cursor_get(cursor.handle, &keyVal, &valueVal, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		logger?.error("!", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:value:)", "mdb_op_in": "\(operation)", "mdb_key_in": "\(String(describing:keyVal))", "mdb_val_in": "\(String(describing:valueVal))", "mdb_return_code": "\(cursorResult)", "_throwing": "\(throwError)"])
		throw throwError
	}
	
	#if DEBUG
	let keyModified = keyIn != keyVal
	let valueModified = valueIn != valueVal
	logger?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:value:)", "mdb_op_in": "\(operation)", "mdb_key_out": "\(String(describing:keyVal))", "mdb_val_out": "\(String(describing:valueVal))", "mdb_key_in": "\(String(describing:keyIn))", "mdb_val_in": "\(String(describing:valueIn))", "mdb_key_modified": "\(keyModified)", "mdb_val_modified": "\(valueModified)"])
	#else
	logger?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(cursor:_:key:value:)", "mdb_op_in": "\(operation)", "mdb_key_out": "\(String(describing:keyVal))", "mdb_val_out": "\(String(describing:valueVal))"])
	#endif
}
#else
// get entry (op)
internal func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:Operation) throws {
	let cursorResult = mdb_cursor_get(cursor.handle(), nil, nil, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
}
// get entry (key)
public func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:Operation, key keyVal:inout MDB_val) throws {
	let cursorResult = mdb_cursor_get(cursor.handle(), &keyVal, nil, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
}
// get entry (value)
public func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:Operation, value valueVal:inout MDB_val) throws {
	let cursorResult = mdb_cursor_get(cursor.handle(), nil, &valueVal, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
}
// get entry (key, value)
public func MDB_cursor_get_entry_static<C:MDB_cursor>(cursor:borrowing C, _ operation:Operation, key keyVal:inout MDB_val, value valueVal:inout MDB_val) throws {
	let cursorResult = mdb_cursor_get(cursor.handle(), &keyVal, &valueVal, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
}
#endif

// set entries from a cursor
#if QUICKLMDB_SHOULDLOG
public func MDB_cursor_set_entry_static<C:MDB_cursor>(cursor:borrowing C, key keyVal:inout MDB_val, value valueVal:inout MDB_val, flags:Operation.Flags, logger:Logger? = nil) throws {
	logger?.trace(">", metadata:["_":"MDB_cursor_set_entry_static(_:key:value:flags:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))"])
	
	let result = mdb_cursor_put(cursor.handle(), &keyVal, &valueVal, flags.rawValue)
	guard result == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:result)
		logger?.error("!", metadata:["_":"MDB_cursor_set_entry_static(_:key:value:flags:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))", "mdb_return_code":"\(result)", "_throwing":"\(throwError)"])
		throw throwError
	}

	logger?.trace("<", metadata:["_":"MDB_cursor_set_entry_static(_:key:value:flags:)", "mdb_key_in":"\(String(describing:keyVal))", "mdb_val_in":"\(String(describing:valueVal))"])
}
#else
public func MDB_cursor_set_entry_static<C:MDB_cursor>(cursor:borrowing C, key keyVal:inout MDB_val, value valueVal:inout MDB_val, flags:Operation.Flags) throws {
	let result = mdb_cursor_put(cursor.handle(), &keyVal, &valueVal, flags.rawValue)
	guard result == MDB_SUCCESS else {
		throw LMDBError(returnCode:result)
	}
}
#endif

#if QUICKLMDB_SHOULDLOG
public func MDB_cursor_compare_keys_static<C:MDB_cursor>(cursor:borrowing C, lhs dataL:consuming MDB_val, rhs dataR:consuming MDB_val, logger:Logger? = nil) -> Int32 {
	logger?.trace(">", metadata:["_":"MDB_cursor_compare_keys_static(_:lhs:rhs:)", "mdb_val_l":"\(String(describing:dataL))", "mdb_val_r":"\(String(describing:dataR))"])
	
	let result = mdb_cmp(cursor.txHandle(), cursor.dbHandle(), &dataL, &dataR)
	
	logger?.trace("<", metadata:["_":"MDB_cursor_compare_keys_static(_:lhs:rhs:)", "mdb_return_code":"\(result)"])
	return result
}
#else
public func MDB_cursor_compare_keys_static<C:MDB_cursor>(cursor:borrowing C, lhs dataL:consuming MDB_val, rhs dataR:consuming MDB_val) -> Int32 {
	return mdb_cmp(cursor.txHandle(), cursor.dbHandle(), &dataL, &dataR)
}
#endif

#if QUICKLMDB_SHOULDLOG
public func MDB_cursor_compare_values_static<C:MDB_cursor>(cursor:borrowing C, lhs dataL:consuming MDB_val, rhs dataR:consuming MDB_val, logger:Logger? = nil) -> Int32 {
	logger?.trace(">", metadata:["_":"MDB_cursor_compare_values_static(_:lhs:rhs:)", "mdb_val_l":"\(String(describing:dataL))", "mdb_val_r":"\(String(describing:dataR))"])
	
	let result = mdb_dcmp(cursor.txHandle(), cursor.dbHandle(), &dataL, &dataR)
	
	logger?.trace("<", metadata:["_":"MDB_cursor_compare_values_static(_:lhs:rhs:)", "mdb_return_code":"\(result)"])
	return result
}
#else
public func MDB_cursor_compare_values_static<C:MDB_cursor>(cursor:borrowing C, _ dataL:consuming MDB_val, _ dataR:consuming MDB_val) -> Int32 {
	return mdb_dcmp(cursor.txHandle(), cursor.dbHandle(), &dataL, &dataR)
}
#endif

