extension MDB_cursor {
	public borrowing func opFirst() throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		return try opFirst(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).self)
	}
/*	public borrowing func opFirstDup() throws -> MDB_cursor_dbtype.MDB_db_val_type {
		return try opFirstDup(returning:MDB_cursor_dbtype.MDB_db_val_type.self)
	}*/
}
extension MDB_cursor {
	// first implementations
	public borrowing func opFirst(returning:(key:MDB_val, value:MDB_val).Type) throws -> (key:MDB_val, value:MDB_val) {
		var keyVal = MDB_val.uninitialized()
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .first, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}
/*	public borrowing func opFirstDup(returning:MDB_val.Type) throws -> MDB_val {
		var keyVal = MDB_val.uninitialized()
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .firstDup, key:&keyVal, value:&valueVal)
		
		#if DEBUG
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return valueVal
	}*/
}

extension MDB_cursor {
	public borrowing func opFirst<K, V>(transforming:(key:MDB_val, value:MDB_val).Type, keyOutTransformer:(consuming MDB_val) -> K, valueOutTransformer:(consuming MDB_val) -> V) throws -> (key:K, value:V) {
		var keyVal = MDB_val.uninitialized()
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .first, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyOutTransformer(keyVal), value:valueOutTransformer(valueVal))
	}
/*	public borrowing func opFirstDup<V>(transforming:MDB_val.Type, valueOutTransformer:(consuming MDB_val) -> V) throws -> V {
		var keyVal = MDB_val.uninitialized()
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .firstDup, key:&keyVal, value:&valueVal)
		
		#if DEBUG
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return valueOutTransformer(valueVal)
	}*/
}