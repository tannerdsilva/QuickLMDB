import RAW

extension MDB_cursor_dupsort {
	/// get the current key from the database
	@available(*, noasync)
	public borrowing func dupCount() throws(LMDBError) -> Int {
		return try MDB_cursor_get_dupcount(cursor:self.cursorHandle())
	}

	@available(*, noasync)
	public consuming func makeDupIterator(key:consuming MDB_cursor_dbtype.MDB_db_key_type) -> DatabaseDupIterator<Self> {
		return DatabaseDupIterator(self, key:key)
	}
}

extension MDB_cursor {
	/// get the current entry from the database
	@available(*, noasync)
	public borrowing func setEntry(key:consuming MDB_val, value:consuming MDB_val, flags:consuming Operation.Flags, tx:borrowing Transaction<Write>) throws(LMDBError) {
		return try MDB_cursor_set_entry(cursor:self.cursorHandle(), key:key, value:value, flags:flags.rawValue)
	}
	
	/// get the current entry from the database
	@available(*, noasync)
	public borrowing func containsEntry(key:consuming MDB_val, value:consuming MDB_val) throws(LMDBError) -> Bool {
		return try MDB_cursor_contains_entry(cursor:self.cursorHandle(), key:key, value:value)
	}

	/// check if the current entry is present in the database
	@available(*, noasync)
	public borrowing func containsEntry(key:consuming MDB_val) throws(LMDBError) -> Bool {
		return try MDB_cursor_contains_entry(cursor:self.cursorHandle(), key:key)
	}

	/// delete the current entry from the database
	@available(*, noasync)
	public borrowing func deleteCurrentEntry(flags:consuming Operation.Flags, tx:borrowing Transaction<Write>) throws(LMDBError) {
		return try MDB_cursor_delete_current_entry(cursor:self.cursorHandle(), flags:flags.rawValue)
	}

	/// compare two MDB_val's based on the key comparison function of the cursor and its underlying database
	@available(*, noasync)
	public borrowing func compareEntryKeys(_ dataL:consuming MDB_val, _ dataR:consuming MDB_val) -> Int32 {
		return MDB_cursor_compare_keys(tx:self.txHandle(), db:self.dbHandle(), lhs:dataL, rhs:dataR)
	}

	/// compare two MDB_val's based on the value comparison function of the cursor and its underlying database
	@available(*, noasync)
	public borrowing func compareEntryValues(_ dataL:consuming MDB_val, _ dataR:consuming MDB_val) -> Int32 {
		return MDB_cursor_compare_values(tx:self.txHandle(), db:self.dbHandle(), lhs:dataL, rhs:dataR)
	}
}