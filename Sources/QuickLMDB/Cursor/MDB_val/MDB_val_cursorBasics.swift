import RAW

extension MDB_cursor_dupsort {
	/// get the current key from the database
	@available(*, noasync)
	public borrowing func dupCount() throws(LMDBError) -> RAW.size_t {
		return try MDB_cursor_get_dupcount_static(cursor:self)
	}

	@available(*, noasync)
	public consuming func makeDupIterator(key:consuming MDB_cursor_dbtype.MDB_db_key_type) -> DatabaseDupIterator<Self> {
		return DatabaseDupIterator(self, key:key)
	}
}

extension MDB_cursor {
	/// get the current entry from the database
	@available(*, noasync)
	public borrowing func setEntry(key:consuming MDB_val, value:consuming MDB_val, flags:consuming Operation.Flags) throws(LMDBError) {
		return try MDB_cursor_set_entry_static(cursor:self, key:&key, value:&value, flags:flags)
	}
	
	/// get the current entry from the database
	@available(*, noasync)
	public borrowing func containsEntry(key:consuming MDB_val, value:consuming MDB_val) throws(LMDBError) -> Bool {
		return try MDB_cursor_contains_entry_static(cursor:self, key:&key, value:&value)
	}

	/// check if the current entry is present in the database
	@available(*, noasync)
	public borrowing func containsEntry(key:consuming MDB_val) throws(LMDBError) -> Bool {
		return try MDB_cursor_contains_entry_static(cursor:self, key:&key)
	}

	/// delete the current entry from the database
	@available(*, noasync)
	public borrowing func deleteCurrentEntry(flags:consuming Operation.Flags) throws(LMDBError) {
		return try MDB_cursor_delete_current_entry_static(cursor:self, flags:flags)
	}

	/// compare two MDB_val's based on the key comparison function of the cursor and its underlying database
	@available(*, noasync)
	public borrowing func compareEntryKeys(_ dataL:consuming MDB_val, _ dataR:consuming MDB_val) -> Int32 {
		return MDB_cursor_compare_keys_static(cursor:self, lhs:&dataL, rhs:&dataR)
	}

	/// compare two MDB_val's based on the value comparison function of the cursor and its underlying database
	@available(*, noasync)
	public borrowing func compareEntryValues(_ dataL:consuming MDB_val, _ dataR:consuming MDB_val) -> Int32 {
		return MDB_cursor_compare_values_static(cursor:self, lhs:&dataL, rhs:&dataR)
	}
}