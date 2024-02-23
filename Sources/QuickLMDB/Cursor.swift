import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

// get entries from a cursor
#if QUICKLMDB_SHOULDLOG
public func MDB_cursor_get_entry_static<C:MDB_cursor>(_ cursor:UnsafePointer<C>, _ operation:Operation, key keyVal:UnsafeMutablePointer<MDB_val>?, value valueVal:UnsafeMutablePointer<MDB_val>?, logger:Logger? = nil) throws {
	#if DEBUG
	// do pointer modification tracking when in debug mode
	let keyIn = keyVal?.pointee
	let valueIn = valueVal?.pointee
	#endif

	logger?.trace(">", metadata:["_":"MDB_cursor_get_entry_static(_:_:key:value:)", "mdb_op_in": "\(operation)", "mdb_key_in": "\(String(describing:keyVal?.pointee))", "mdb_val_in": "\(String(describing:valueVal?.pointee))"])

	let cursorResult = mdb_cursor_get(cursor.pointer(to:\.cursorHandle)!.pointee, keyVal, valueVal, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:cursorResult)
		logger?.error("!", metadata:["_":"MDB_cursor_get_entry_static(_:_:key:value:)", "mdb_op_in": "\(operation)", "mdb_key_in": "\(String(describing:keyVal?.pointee))", "mdb_val_in": "\(String(describing:valueVal?.pointee))", "mdb_return_code": "\(cursorResult)", "error_thrown": "\(throwError)"])
		throw throwError
	}
	
	#if DEBUG
	let keyModified = keyIn != keyVal?.pointee
	let valueModified = valueIn != valueVal?.pointee
	logger?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(_:_:key:value:)", "mdb_key_out": "\(String(describing:keyVal?.pointee))", "mdb_val_out": "\(String(describing:valueVal?.pointee))", "mdb_key_in": "\(String(describing:keyIn))", "mdb_val_in": "\(String(describing:valueIn))", "mdb_key_modified": "\(keyModified)", "mdb_val_modified": "\(valueModified)"])
	#else
	logger?.trace("<", metadata:["_":"MDB_cursor_get_entry_static(_:_:key:value:)", "mdb_key_out": "\(String(describing:keyVal?.pointee))", "mdb_val_out": "\(String(describing:valueVal?.poitnee))"])
	#endif
}
#else
public func MDB_cursor_get_entry_static<C:MDB_cursor>(_ cursor:UnsafePointer<C>, _ operation:Operation, key keyVal:UnsafeMutablePointer<MDB_val>?, value valueVal:UnsafeMutablePointer<MDB_val>?) throws {
	let cursorResult = mdb_cursor_get(cursor.pointer(to:\.cursorHandle)!.pointee, keyVal, valueVal, operation.mdbValue)
	guard cursorResult == MDB_SUCCESS else {
		throw LMDBError(returnCode:cursorResult)
	}
}
#endif

// set entries from a cursor
#if QUICKLMDB_SHOULDLOG
public func MDB_cursor_set_entry_static<C:MDB_cursor>(_ cursor:UnsafePointer<C>, key keyVal:UnsafeMutablePointer<MDB_val>, value valueVal:UnsafeMutablePointer<MDB_val>, flags:Operation.Flags, logger:Logger? = nil) throws {
	logger?.trace(">", metadata:["_":"MDB_cursor_set_entry_static(_:key:value:flags:)", "mdb_key_in":"\(String(describing:keyVal.pointee))", "mdb_val_in":"\(String(describing:valueVal.pointee))"])
	
	let result = mdb_cursor_put(cursor.pointer(to:\.cursorHandle)!.pointee, keyVal, valueVal, flags.rawValue)
	guard result == MDB_SUCCESS else {
		let throwError = LMDBError(returnCode:result)
		logger?.error("!", metadata:["_":"MDB_cursor_set_entry_static(_:key:value:flags:)", "mdb_key_in":"\(String(describing:keyVal.pointee))", "mdb_val_in":"\(String(describing:valueVal.pointee))", "mdb_return_code":"\(result)", "error_thrown":"\(throwError)"])
		throw throwError
	}

	logger?.trace("<", metadata:["_":"MDB_cursor_set_entry_static(_:key:value:flags:)", "mdb_key_in":"\(String(describing:keyVal.pointee))", "mdb_val_in":"\(String(describing:valueVal.pointee))"])
}
#else
public func MDB_cursor_set_entry_static<C:MDB_cursor>(_ cursor:UnsafePointer<C>, key keyVal:UnsafeMutablePointer<MDB_val>, value valueVal:UnsafeMutablePointer<MDB_val>, flags:Operation.Flags) throws {
	let result = mdb_cursor_put(cursor.pointer(to:\.cursorHandle)!.pointee, keyVal, valueVal, flags.rawValue)
	guard result == MDB_SUCCESS else {
		throw LMDBError(returnCode:result)
	}
}
#endif

#if QUICKLMDB_SHOULDLOG
public func MDB_cursor_compare_keys_static<C:MDB_cursor>(_ cursor:UnsafePointer<C>, lhs dataL:UnsafePointer<MDB_val>, rhs dataR:UnsafePointer<MDB_val>, logger:Logger? = nil) -> Int32 {
	logger?.trace(">", metadata:["_":"MDB_cursor_compare_keys_static(_:lhs:rhs:)", "mdb_val_l":"\(String(describing:dataL))", "mdb_val_r":"\(String(describing:dataR))"])
	
	let result = mdb_cmp(cursor.pointer(to:\.txHandle)!.pointee, cursor.pointer(to:\.dbHandle)!.pointee, dataL, dataR)
	
	logger?.trace("<", metadata:["_":"MDB_cursor_compare_keys_static(_:lhs:rhs:)", "mdb_return_code":"\(result)"])
	return result
}
#else
public func MDB_cursor_compare_keys_static<C:MDB_cursor>(_ cursor:UnsafePointer<C>, _ dataL:UnsafePointer<MDB_val>, _ dataR:UnsafePointer<MDB_val>) -> Int32 {
	return mdb_cmp(cursor.pointer(to:\.txHandle)!.pointee, cursor.pointer(to:\.dbHandle)!.pointee, dataL, dataR)
}
#endif

#if QUICKLMDB_SHOULDLOG
public func MDB_cursor_compare_values_static<C:MDB_cursor>(_ cursor:UnsafePointer<C>, lhs dataL:UnsafePointer<MDB_val>, rhs dataR:UnsafePointer<MDB_val>, logger:Logger? = nil) -> Int32 {
	logger?.trace(">", metadata:["_":"MDB_cursor_compare_values_static(_:lhs:rhs:)", "mdb_val_l":"\(String(describing:dataL))", "mdb_val_r":"\(String(describing:dataR))"])
	
	let result = mdb_dcmp(cursor.pointer(to:\.txHandle)!.pointee, cursor.pointer(to:\.dbHandle)!.pointee, dataL, dataR)
	
	logger?.trace("<", metadata:["_":"MDB_cursor_compare_values_static(_:lhs:rhs:)", "mdb_return_code":"\(result)"])
	return result
}
#else
public func MDB_cursor_compare_values_static<C:MDB_cursor>(_ cursor:UnsafePointer<C>, _ dataL:UnsafePointer<MDB_val>, _ dataR:UnsafePointer<MDB_val>) -> Int32 {
	return mdb_dcmp(cursor.pointer(to:\.txHandle)!.pointee, cursor.pointer(to:\.dbHandle)!.pointee, dataL, dataR)
}
#endif


/// the protocol for type-strict cursors
public protocol MDB_cursor_strict:MDB_cursor where MDB_cursor_dbtype:MDB_db_strict {
	// /// get entry with strict key and value types
	// @discardableResult func MDB_cursor_get_entry(_ operation:Operation, key:UnsafePointer<MDB_val>, value:UnsafePointer<MDB_val>) throws -> (MDB_val, MDB_val)
	// /// get entry with strict key type
	// @discardableResult func MDB_cursor_get_entry(_ operation:Operation, key:UnsafePointer<MDB_cursor_dbtype.MDB_db_key_type>) throws -> (MDB_val, MDB_val)
	// /// get entry with strict value type
	// @discardableResult func MDB_cursor_get_entry(_ operation:Operation, value:UnsafePointer<MDB_cursor_dbtype.MDB_db_val_type>) throws -> (MDB_val, MDB_val)

	// /// set entry with strict key and value types
	// func MDB_cursor_set_entry(key:UnsafePointer<MDB_cursor_dbtype.MDB_db_key_type>, value:UnsafePointer<MDB_cursor_dbtype.MDB_db_val_type>, flags:Operation.Flags) throws

	// /// check for entries with strict key type
	// func MDB_cursor_contains_entry(key:UnsafePointer<MDB_cursor_dbtype.MDB_db_key_type>) throws -> Bool
	// /// check for entries with strict key and value types
	// func MDB_cursor_contains_entry(key:UnsafePointer<MDB_cursor_dbtype.MDB_db_key_type>, value:UnsafePointer<MDB_cursor_dbtype.MDB_db_val_type>) throws -> Bool
	
	func MDB_cursor_compare_keys<L:RAW_accessible, R:RAW_accessible>(_ dataL:UnsafePointer<L>, _ dataR:UnsafePointer<R>) -> Int32
	func MDB_cursor_compare_values<L:RAW_accessible, R:RAW_accessible>(_ dataL:UnsafePointer<L>, _ dataR:UnsafePointer<R>) -> Int32
}

/// the protocol for open ended data storage type
public protocol MDB_cursor:Sequence {
	typealias MDB_val_pairtype = (MDB_val, MDB_val)

	/// the database type backing this cursor
	associatedtype MDB_cursor_dbtype:MDB_db

	/// the cursor handle for the specific instance
	var cursorHandle:OpaquePointer { get }
	/// the database handle for the specific instance
	var dbHandle:MDB_dbi { get }
	/// the transaction that this instance is operating within
	var txHandle:OpaquePointer { get }

	/// initialize a new cursor from a valid transaction and database handle
	#if QUICKLMDB_SHOULDLOG
	var logger:Logger? { get }
	init<T:MDB_tx, D:MDB_db>(db:UnsafePointer<D>, tx:UnsafePointer<T>, logger:Logger?) throws
	#else
	init<T:MDB_tx, D:MDB_db>(db:UnsafePointer<D>, tx:UnsafePointer<T>) throws
	#endif

	// cursor operator functions
	// first variants - are you looking for the first? you're in the right place
	@discardableResult mutating func opFirst(as:MDB_val_pairtype.Type) throws -> MDB_val_pairtype
	@discardableResult mutating func opFirstDup(as:MDB_val_pairtype.Type) throws -> MDB_val_pairtype
	// last variants - skip the line and go straight to the end
	@discardableResult mutating func opLast(as:MDB_val_pairtype.Type) throws -> MDB_val_pairtype
	@discardableResult mutating func opLastDup(as:MDB_val_pairtype.Type) throws -> MDB_val_pairtype
	// next variants - move forward
	@discardableResult mutating func opNext(as:MDB_val_pairtype.Type) throws -> MDB_val_pairtype
	@discardableResult mutating func opNextDup(as:MDB_val_pairtype.Type) throws -> MDB_val_pairtype
	@discardableResult mutating func opNextNoDup(as:MDB_val_pairtype.Type) throws -> MDB_val_pairtype
	// previous variants - take it back
	@discardableResult mutating func opPrevious(as:MDB_val_pairtype.Type) throws -> MDB_val_pairtype
	@discardableResult mutating func opPreviousDup(as:MDB_val_pairtype.Type) throws -> MDB_val_pairtype
	@discardableResult mutating func opPreviousNoDup(as:MDB_val_pairtype.Type) throws -> MDB_val_pairtype
	// get variants - find your footing
	@discardableResult mutating func opGetBoth(as:MDB_val_pairtype.Type, _:UnsafeMutablePointer<MDB_val>, _:UnsafeMutablePointer<MDB_val>) throws -> MDB_val_pairtype
	@discardableResult mutating func opGetBothRange(as:MDB_val_pairtype.Type, _:UnsafeMutablePointer<MDB_val>, _:UnsafeMutablePointer<MDB_val>) throws -> MDB_val_pairtype
	@discardableResult mutating func opGetCurrent(as:MDB_val_pairtype.Type) throws -> MDB_val_pairtype
	// set variants - make your mark
	mutating func opSet(as:MDB_val_pairtype.Type, _:UnsafeMutablePointer<MDB_val>) throws -> MDB_val
	@discardableResult mutating func opSetKey(as:MDB_val_pairtype.Type, _:UnsafeMutablePointer<MDB_val>) throws -> MDB_val_pairtype
	@discardableResult mutating func opSetRange(as:MDB_val_pairtype.Type, _:UnsafeMutablePointer<MDB_val>) throws -> MDB_val_pairtype
	// multiple variants - theres more than meets the eye
	@discardableResult mutating func opGetMultiple(as:MDB_val_pairtype.Type, _:UnsafeMutablePointer<MDB_val>) throws -> MDB_val_pairtype
	@discardableResult mutating func opNextMultiple(as:MDB_val_pairtype.Type, _:UnsafeMutablePointer<MDB_val>) throws -> MDB_val_pairtype
	
	// write entry function
	/// set an entry in the database with a specified key and value. the operation will be committed with the specified flags.
	mutating func setEntry(_:UnsafeMutablePointer<MDB_val>, _:UnsafeMutablePointer<MDB_val>, flags:Operation.Flags) throws

	// checking for entries
	mutating func containsEntry(_:UnsafeMutablePointer<MDB_val>, _:UnsafeMutablePointer<MDB_val>) throws -> Bool
	mutating func containsEntry(_:UnsafeMutablePointer<MDB_val>) throws -> Bool

	// delete the current entry
	mutating func deleteCurrentEntry(flags:Operation.Flags) throws

	// comparing
	mutating func compareEntryKeys(_ dataL:UnsafePointer<MDB_val>, _ dataR:UnsafePointer<MDB_val>) -> Int32
	mutating func compareEntryValues(_ dataL:UnsafePointer<MDB_val>, _ dataR:UnsafePointer<MDB_val>) -> Int32
	
	// returns the number of duplicate entries in the database for this key.
	mutating func dupCount() throws -> size_t
}

extension MDB_cursor {
	@discardableResult mutating func opFirst(as:MDB_val_pairtype.Type) throws -> MDB_val_pairtype {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .first, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (keyVal, valueVal)
	}
	
	@discardableResult mutating func opFirstDup() throws -> (MDB_val, MDB_val) {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .firstDup, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}

	@discardableResult mutating func opGetBoth(key keyVal:UnsafeMutablePointer<MDB_val>, value valueVal:UnsafeMutablePointer<MDB_val>) throws -> (MDB_val, MDB_val) {
		#if DEBUG
		let keyPtr = keyVal.pointee.mv_data
		let valuePtr = valueVal.pointee.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .getBoth, key:keyVal, value:valueVal)

		#if DEBUG
		assert(keyPtr != keyVal.pointee.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.pointee.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal.pointee, value:valueVal.pointee)
	}

	@discardableResult mutating func opGetBothRange(key keyVal:UnsafeMutablePointer<MDB_val>, value valueVal:UnsafeMutablePointer<MDB_val>) throws -> (MDB_val, MDB_val) {
		#if DEBUG
		let keyPtr = keyVal.pointee.mv_data
		let valuePtr = valueVal.pointee.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .getBothRange, key:keyVal, value:valueVal)

		#if DEBUG
		assert(keyPtr != keyVal.pointee.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.pointee.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal.pointee, value:valueVal.pointee)
	}

	@discardableResult mutating func opGetCurrent() throws -> (MDB_val, MDB_val) {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .getCurrent, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}

	@discardableResult mutating func opLast() throws -> (MDB_val, MDB_val) {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .last, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}

	@discardableResult mutating func opLastDup() throws -> (MDB_val, MDB_val) {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .lastDup, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}

	@discardableResult mutating func opNext() throws -> (MDB_val, MDB_val) {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .next, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}

	@discardableResult mutating func opNextDup() throws -> (MDB_val, MDB_val) {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .nextDup, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}

	@discardableResult mutating func opNextNoDup() throws -> (MDB_val, MDB_val) {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .nextNoDup, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}

	@discardableResult mutating func opPrevious() throws -> (MDB_val, MDB_val) {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .previous, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}

	@discardableResult mutating func opPreviousDup() throws -> (MDB_val, MDB_val) {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .previousDup, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}

	@discardableResult mutating func opPreviousNoDup() throws -> (MDB_val, MDB_val) {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .previousNoDup, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}

	mutating func opSet(key:UnsafeMutablePointer<MDB_val>) throws -> MDB_val {
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .set, key:key, value:&valueVal)

		#if DEBUG
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return valueVal
	}

	@discardableResult mutating func opSetKey(key:UnsafeMutablePointer<MDB_val>) throws -> (MDB_val, MDB_val) {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .setKey, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}

	@discardableResult mutating func opSetRange(key:UnsafeMutablePointer<MDB_val>) throws -> (MDB_val, MDB_val) {
		var keyVal = MDB_val.unitialized()
		var valueVal = MDB_val.unitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(&self, .setRange, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}
}


extension MDB_cursor {
	/// set the current entry with a specified key and value.
	public mutating func setEntry<K:MDB_encodable, V:MDB_encodable>(key keyVal:UnsafePointer<K>, value valuePtr:UnsafePointer<V>, flags:Operation.Flags) throws {
		switch flags.contains(.reserve) {
			case true:
				try keyVal.pointee.MDB_encodable_access { keyVal in
					var valueVal = valuePtr.pointee.MDB_encodable_reserved_val()
					
					#if DEBUG
					let trashPointer = valueVal.mv_data
					#endif

					#if QUICKLMDB_SHOULDLOG
					try MDB_cursor_set_entry_static(&self, key:keyVal, value:&valueVal, flags:flags, logger:logger)
					#else
					try MDB_cursor_set_entry_static(&self, key:keyVal, value:&valueVal, flags:flags)
					#endif

					#if DEBUG
					assert(trashPointer != valueVal.mv_data, "database failed to return a unique buffer pointer for reserved value")
					#endif

					valuePtr.pointee.MDB_encodable_write(reserved:&valueVal)
				}
			case false:
				try keyVal.pointee.MDB_encodable_access { keyVal in
					try valuePtr.pointee.MDB_encodable_access { valueVal in
						#if QUICKLMDB_SHOULDLOG
						try MDB_cursor_set_entry_static(&self, key:keyVal, value:valueVal, flags:flags, logger:logger)
						#else
						try MDB_cursor_set_entry_static(&self, key:keyVal, value:valueVal, flags:flags)
						#endif
					}
				}
		}
	}

	public mutating func containsEntry<K:MDB_encodable, V:MDB_encodable>(key:UnsafePointer<K>, value:UnsafePointer<V>) throws -> Bool {
		return try key.pointee.MDB_encodable_access { keyVal in
			return try value.pointee.MDB_encodable_access { valueVal in
				let searchKey = mdb_cursor_get(MDB_cursor_handle, keyVal, valueVal, MDB_GET_BOTH)
				switch searchKey {
					case MDB_SUCCESS:
						return true;
					case MDB_NOTFOUND:
						return false;
					default:
						throw LMDBError(returnCode:searchKey)
				}
			}
		}
	}

	public func containsEntry<K:MDB_encodable>(key:UnsafePointer<K>) throws -> Bool {
		return try key.pointee.MDB_encodable_access { keyVal in
			let searchKey = mdb_cursor_get(MDB_cursor_handle, keyVal, nil, MDB_SET)
			switch searchKey {
				case MDB_SUCCESS:
					return true;
				case MDB_NOTFOUND:
					return false;
				default:
					throw LMDBError(returnCode:searchKey)
			}
		}
	}

	public func deleteCurrentEntry(flags:Operation.Flags) throws {
		let deleteResult = mdb_cursor_del(MDB_cursor_handle, flags.rawValue)
		guard deleteResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:deleteResult)
		}
	}

	public mutating func compareEntryKeys(_ dataL:UnsafePointer<MDB_val>, _ dataR:UnsafePointer<MDB_val>) -> Int32 {
		return dataL.pointee.RAW_access { lBuff in
			return dataR.pointee.RAW_access { rBuff in
				var lVal = MDB_val(lBuff)
				var rVal = MDB_val(rBuff)
				return mdb_cmp(MDB_txn_handle, MDB_db_handle, &lVal, &rVal)
			}
		}
	}

	public func MDB_cursor_compare_values<L:RAW_accessible, R:RAW_accessible>(_ dataL:UnsafePointer<L>, _ dataR:UnsafePointer<R>) -> Int32 {
		return dataL.pointee.RAW_access { lBuff in
			return dataR.pointee.RAW_access { rBuff in
				var lVal = MDB_val(lBuff)
				var rVal = MDB_val(rBuff)
				return mdb_dcmp(MDB_txn_handle, MDB_db_handle, &lVal, &rVal)
			}
		}
	}

	public func MDB_cursor_dup_count() throws -> size_t {
		var dupCount = size_t()
		let countResult = mdb_cursor_count(self.MDB_cursor_handle, &dupCount)
		switch countResult { 
			case MDB_SUCCESS:
				return dupCount
			default:
				throw LMDBError(returnCode:countResult)
		}
	}
}

extension Cursor:MDB_cursor_strict where MDB_cursor_dbtype:MDB_db_strict {}

extension Cursor:MDB_cursor where MDB_cursor_dbtype:MDB_db {}

/// LMDB cursor. this is defined as a class so that the cursor can be auto-closed when references to this instances are free'd from memory.
/// - conforms to the ``MDB_cursor`` protocol with any database (unconditional)
/// - conforms to the ``MDB_cursor_strict`` protocol with any database that conforms to the ``MDB_db_strict`` protocol.
public final class Cursor<D:MDB_db>:Sequence {
	/// returns a dup iterator for a specified key. if the key does not exist, an error is thrown.
	public func makeDupIterator<A:RAW_accessible>(key:inout A) throws -> DupIterator {
		try MDB_cursor_get_entry(.setKey, key:&key)
		return DupIterator(self)
	}
	
	/// traditional 'makeiterator' that allows a cursor to conform to Sequence
	public func makeIterator() -> Iterator {
		return Iterator(self)
	}
	
	/// primary dup iterator implementation
	public struct DupIterator:IteratorProtocol, Sequence {
		private var cursor:Cursor<D>
		private var op:Operation

		fileprivate init(_ cursor:Cursor<D>) {
			self.cursor = cursor
			self.op = .firstDup
		}

		public mutating func next() -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)? {
			defer {
				switch op {
					case .firstDup:
						op = .nextDup
					default:
						break;
				}
			}
			do {
				return try cursor.MDB_cursor_get_entry(op)
			} catch {
				return nil
			}
		}
	}

	public struct Iterator:IteratorProtocol, Sequence {
		private var cursor:Cursor<D>
		private var op:Operation

		public init(_ cursor:Cursor<D>) {
			self.cursor = cursor
			self.op = .first
		}

		public mutating func next() -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)? {
			defer {
				switch op {
					case .first:
						op = .next
					default:
						break;
				}
			}
			do {
				return try cursor.MDB_cursor_get_entry(op)
			} catch {
				return nil
			}
		}
	}

	public typealias MDB_cursor_dbtype = D

	/// this is the pointer to the `MDB_cursor` struct associated with a given instance.
	public let MDB_cursor_handle:OpaquePointer
	
	/// this is the database that this cursor is associated with.
	public let MDB_db_handle:MDB_dbi
	
	/// pointer to the `MDB_txn` struct associated with a given instance.
	public let MDB_txn_handle:OpaquePointer

	/// stores the readonly state of the attached transaction.
	private let MDB_txn_readonly:Bool
	
	/// opens a new cursor instance from a given database and transaction pairing.
	public init<T:MDB_tx>(MDB_db dbh:MDB_dbi, MDB_tx:inout T) throws {
		var buildCursor:OpaquePointer? = nil
		let openCursorResult = mdb_cursor_open(MDB_tx.MDB_tx_handle, dbh, &buildCursor)
		guard openCursorResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openCursorResult)
		}
		MDB_cursor_handle = buildCursor!
		MDB_db_handle = dbh
		MDB_txn_handle = MDB_tx.MDB_tx_handle
		MDB_txn_readonly = MDB_tx.MDB_tx_readOnly
	}

	deinit {
		// close the cursor
		mdb_cursor_close(MDB_cursor_handle)
	}
}