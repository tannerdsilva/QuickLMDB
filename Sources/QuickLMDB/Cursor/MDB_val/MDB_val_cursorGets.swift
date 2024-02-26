/*
extension MDB_cursor {
	// get variants
	public borrowing func opGetBoth(returning:(key:MDB_val, value:MDB_val).Type, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val) throws -> (key:MDB_val, value:MDB_val) {
		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		#if QUICKLMDB_SHOULDLOG
		try MDB_cursor_get_entry_static(cursor:self, .getBoth, key:&keyVal, value:&valueVal, logger:logger)
		#else
		try MDB_cursor_get_entry_static(cursor:self, .getBoth, key:&keyVal, value:&valueVal)
		#endif
		
		#if DEBUG
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}

	public borrowing func opGetBothRange(returning:(key:MDB_val, value:MDB_val).Type, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val) throws -> (key:MDB_val, value:MDB_val) {
		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .getBothRange, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}
	public borrowing func opGetCurrent(returning:(key:MDB_val, value:MDB_val).Type) throws -> (key:MDB_val, value:MDB_val) {
		var keyVal = MDB_val.uninitialized()
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .getCurrent, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}
}
*/