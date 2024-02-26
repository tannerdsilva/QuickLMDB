extension MDB_cursor {
	
	// set variants
	public borrowing func opSet(key keyVal:consuming MDB_cursor_dbtype.MDB_db_key_type) throws -> MDB_cursor_dbtype.MDB_db_val_type {
		return try opSet(returning:MDB_cursor_dbtype.MDB_db_val_type.self, key:keyVal)
	}
	public borrowing func opSet(returning:MDB_val.Type, key keyVal:consuming MDB_val) throws -> MDB_val {
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .set, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return valueVal
	}
	public borrowing func opSetKey(key keyVal:consuming MDB_cursor_dbtype.MDB_db_key_type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		return try opSetKey(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).self, key:keyVal)
	}
	public borrowing func opSetKey(returning:(key:MDB_val, value:MDB_val).Type, key keyVal:consuming MDB_val) throws -> (key:MDB_val, value:MDB_val) {
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .setKey, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}
	public borrowing func opSetRange(key keyVal:consuming MDB_cursor_dbtype.MDB_db_key_type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		return try opSetRange(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).self, key:keyVal)
	}
	public borrowing func opSetRange(returning:(key:MDB_val, value:MDB_val).Type, key keyVal:consuming MDB_val) throws -> (key:MDB_val, value:MDB_val) {
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .setRange, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}
}