import struct CLMDB.MDB_val

extension MDB_cursor {
	@available(*, noasync)
	public borrowing func opFirst() throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		return try opFirst(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).self)
	}
}

extension MDB_cursor_dupsort {
	@available(*, noasync)
	public borrowing func opFirstDup() throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type {
		return try opFirstDup(returning:MDB_cursor_dbtype.MDB_db_val_type.self)
	}
}

extension MDB_cursor {
	// first implementations
	@available(*, noasync)
	public borrowing func opFirst(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).Type) throws(LMDBError) -> (key:CLMDB.MDB_val, value:CLMDB.MDB_val) {
let keyVal = MDB_val.uninitialized()
let valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		let entry = try MDB_cursor_get_entry(cursor:self.cursorHandle(), op:Operation.first.mdbValue, key:keyVal, value:valueVal)

		#if DEBUG
		assert(entry.key.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != entry.key.mv_data, "key buffer was not modified so it cannot be returned")
		assert(entry.value.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != entry.value.mv_data && entry.value.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:entry.key, value:entry.value)
	}
}

extension MDB_cursor_dupsort {
	@available(*, noasync)
	public borrowing func opFirstDup(returning:MDB_val.Type) throws(LMDBError) -> MDB_val {
let keyVal = MDB_val.uninitialized()
let valueVal = MDB_val.uninitialized()

		#if DEBUG
		let valuePtr = valueVal.mv_data
		#endif

		let entry = try MDB_cursor_get_entry(cursor:self.cursorHandle(), op:Operation.firstDup.mdbValue, key:keyVal, value:valueVal)
		
		#if DEBUG
		assert(entry.value.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != entry.value.mv_data && entry.value.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return entry.value
	}
}

extension MDB_cursor {
	@available(*, noasync)
	public borrowing func opFirst<K, V>(transforming:(key:MDB_val, value:MDB_val).Type, keyOutTransformer:(consuming MDB_val) -> K, valueOutTransformer:(consuming MDB_val) -> V) throws(LMDBError) -> (key:K, value:V) {
let keyVal = MDB_val.uninitialized()
let valueVal = MDB_val.uninitialized()

		#if DEBUG
		let keyPtr = keyVal.mv_data
		let valuePtr = valueVal.mv_data
		#endif

		let entry = try MDB_cursor_get_entry(cursor:self.cursorHandle(), op:Operation.first.mdbValue, key:keyVal, value:valueVal)

		#if DEBUG
		assert(entry.key.mv_size != -1, "key buffer was not modified so it cannot be returned")
		assert(keyPtr != entry.key.mv_data, "key buffer was not modified so it cannot be returned")
		assert(entry.value.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != entry.value.mv_data && entry.value.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return (key:keyOutTransformer(entry.key), value:valueOutTransformer(entry.value))
	}
}

extension MDB_cursor_dupsort {
	@available(*, noasync)
	public borrowing func opFirstDup<V>(transforming:MDB_val.Type, valueOutTransformer:(consuming MDB_val) -> V) throws(LMDBError) -> V {
let keyVal = MDB_val.uninitialized()
let valueVal = MDB_val.uninitialized()

		#if DEBUG
		let valuePtr = valueVal.mv_data
		#endif

		let entry = try MDB_cursor_get_entry(cursor:self.cursorHandle(), op:Operation.firstDup.mdbValue, key:keyVal, value:valueVal)
		
		#if DEBUG
		assert(entry.value.mv_size != -1, "value buffer was not modified so it cannot be returned")
		assert(valuePtr != entry.value.mv_data && entry.value.mv_size > 0, "value buffer was not modified so it cannot be returned")
		#endif

		return valueOutTransformer(entry.value)
	}
}