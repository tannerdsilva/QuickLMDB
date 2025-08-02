extension MDB_cursor {
	@available(*, noasync)
	public borrowing func opGetCurrent() throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		return try opGetCurrent(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).self)
	}
}

extension MDB_cursor_dupsort {
	@available(*, noasync)
	public borrowing func opGetBoth(key keyVal:consuming MDB_cursor_dbtype.MDB_db_key_type, value valueVal:consuming MDB_cursor_dbtype.MDB_db_val_type) throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type {
		return try opGetBoth(returning:MDB_cursor_dbtype.MDB_db_val_type.self, key:keyVal, value:valueVal)
	}
	@available(*, noasync)
	public borrowing func opGetBothRange(key keyVal:consuming MDB_cursor_dbtype.MDB_db_key_type, value valueVal:consuming MDB_cursor_dbtype.MDB_db_val_type) throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type {
		return try opGetBothRange(returning:MDB_cursor_dbtype.MDB_db_val_type.self, key:keyVal, value:valueVal)
	}
}

extension MDB_cursor {
	@available(*, noasync)
	public borrowing func opGetCurrent(returning:(key:MDB_val, value:MDB_val).Type) throws(LMDBError) -> (key:MDB_val, value:MDB_val) {
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

extension MDB_cursor_dupsort {
	@available(*, noasync)
	public borrowing func opGetBoth(returning:MDB_val.Type, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val) throws(LMDBError) -> MDB_val {
		#if DEBUG
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .getBoth, key:&keyVal, value:&valueVal)
		
		#if DEBUG
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return valueVal
	}
	@available(*, noasync)
	public borrowing func opGetBothRange(returning:MDB_val.Type, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val) throws(LMDBError) -> MDB_val {
		#if DEBUG
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .getBothRange, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return valueVal
	}
}

extension MDB_cursor_dupsort {
	@available(*, noasync)
	public borrowing func opGetBoth<V>(transforming:MDB_val.Type, valueOutTransformer:(consuming MDB_val) -> V, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val) throws(LMDBError) -> V {
		try MDB_cursor_get_entry_static(cursor:self, .getBoth, key:&keyVal, value:&valueVal)
		return valueOutTransformer(valueVal)
	}
	@available(*, noasync)
	public borrowing func opGetBothRange<V>(transforming:MDB_val.Type, valueOutTransformer:(consuming MDB_val) -> V, key keyVal:consuming MDB_val, value valueVal:consuming MDB_val) throws(LMDBError) -> V {
		try MDB_cursor_get_entry_static(cursor:self, .getBothRange, key:&keyVal, value:&valueVal)
		return valueOutTransformer(valueVal)
	}
}

extension MDB_cursor {
	@available(*, noasync)
	public borrowing func opGetCurrent<K, V>(transforming:(key:MDB_val, value:MDB_val).Type, keyOutTransformer:(consuming MDB_val) -> K, valueOutTransformer:(consuming MDB_val) -> V) throws(LMDBError) -> (key:K, value:V) {
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