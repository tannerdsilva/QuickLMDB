extension MDB_cursor {
	@available(*, noasync)
	public borrowing func opSet(key keyVal:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type {
		return try opSet(returning:MDB_cursor_dbtype.MDB_db_val_type.self, key:keyVal)
	}
	@available(*, noasync)
	public borrowing func opSetKey(key keyVal:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		return try opSetKey(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).self, key:keyVal)
	}
	@available(*, noasync)
	public borrowing func opSetRange(key keyVal:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		return try opSetRange(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).self, key:keyVal)
	}
}
extension MDB_cursor {
	
	@available(*, noasync)
	public borrowing func opSet(returning:MDB_val.Type, key keyVal:consuming MDB_val) throws(LMDBError) -> MDB_val {
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .set, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return valueVal
	}
	@available(*, noasync)
	public borrowing func opSetKey(returning:(key:MDB_val, value:MDB_val).Type, key keyVal:consuming MDB_val) throws(LMDBError) -> (key:MDB_val, value:MDB_val) {
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .setKey, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}
	@available(*, noasync)
	public borrowing func opSetRange(returning:(key:MDB_val, value:MDB_val).Type, key keyVal:consuming MDB_val) throws(LMDBError) -> (key:MDB_val, value:MDB_val) {
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .setRange, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyVal, value:valueVal)
	}
}

extension MDB_cursor {
	@available(*, noasync)
	public borrowing func opSet<K, V>(transforming:(key:MDB_val, value:MDB_val).Type, keyOutTransformer:(consuming MDB_val) -> K, valueOutTransformer:(consuming MDB_val) -> V, key keyVal:consuming MDB_val) throws(LMDBError) -> (key:K, value:V) {
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .set, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyVal.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyOutTransformer(keyVal), value:valueOutTransformer(valueVal))
	}
	@available(*, noasync)
	public borrowing func opSetKey<K, V>(transforming:(key:MDB_val, value:MDB_val).Type, keyOutTransformer:(consuming MDB_val) -> K, valueOutTransformer:(consuming MDB_val) -> V, key keyVal:consuming MDB_val) throws(LMDBError) -> (key:K, value:V) {
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .setKey, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyOutTransformer(keyVal), value:valueOutTransformer(valueVal))
	}
	@available(*, noasync)
	public borrowing func opSetRange<K, V>(transforming:(key:MDB_val, value:MDB_val).Type, keyOutTransformer:(consuming MDB_val) -> K, valueOutTransformer:(consuming MDB_val) -> V, key keyVal:consuming MDB_val) throws(LMDBError) -> (key:K, value:V) {
		var valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		try MDB_cursor_get_entry_static(cursor:self, .setRange, key:&keyVal, value:&valueVal)

		#if DEBUG
		assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
		assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != valueVal.mv_data && valueVal.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyOutTransformer(keyVal), value:valueOutTransformer(valueVal))
	}
}