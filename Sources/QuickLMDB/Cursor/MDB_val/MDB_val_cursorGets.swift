extension MDB_cursor {
	public borrowing func opGetBoth(key keyVal:consuming MDB_cursor_dbtype.MDB_db_key_type, value valueVal:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		return try opGetBoth(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).self, key:keyVal, value:valueVal)
	}
	public borrowing func opGetBothRange(key keyVal:consuming MDB_cursor_dbtype.MDB_db_key_type, value valueVal:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		return try opGetBothRange(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).self, key:keyVal, value:valueVal)
	}
	public borrowing func opGetCurrent() throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		return try opGetCurrent(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).self)
	}
}

extension MDB_cursor {
	// get variants
	public borrowing func opGetBoth(returning:(key:MDB_val, value:MDB_val).Type, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val) throws -> (key:MDB_val, value:MDB_val) {
		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .getBoth, key:&keyVal, value:&valueVal)
		
		#if DEBUG
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
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
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
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
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}
}

extension MDB_cursor {
	public borrowing func opGetBoth<K, V>(transforming:(key:MDB_val, value:MDB_val).Type, keyOutTransformer:(consuming MDB_val) -> K, valueOutTransformer:(consuming MDB_val) -> V, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val) throws -> (key:K, value:V) {
		try MDB_cursor_get_entry_static(cursor:self, .getBoth, key:&keyVal, value:&valueVal)
		return (key:keyOutTransformer(keyVal), value:valueOutTransformer(valueVal))
	}
	public borrowing func opGetBothRange<K, V>(transforming:(key:MDB_val, value:MDB_val).Type, keyOutTransformer:(consuming MDB_val) -> K, valueOutTransformer:(consuming MDB_val) -> V, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val) throws -> (key:K, value:V) {
		try MDB_cursor_get_entry_static(cursor:self, .getBothRange, key:&keyVal, value:&valueVal)
		return (key:keyOutTransformer(keyVal), value:valueOutTransformer(valueVal))
	}
	public borrowing func opGetCurrent<K, V>(transforming:(key:MDB_val, value:MDB_val).Type, keyOutTransformer:(consuming MDB_val) -> K, valueOutTransformer:(consuming MDB_val) -> V) throws -> (key:K, value:V) {
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
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyOutTransformer(keyVal), value:valueOutTransformer(valueVal))
	}
}