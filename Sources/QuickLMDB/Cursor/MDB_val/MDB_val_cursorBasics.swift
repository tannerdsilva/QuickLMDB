import RAW

extension MDB_cursor {
	/// get the current key from the database
	public borrowing func dupCount() throws -> RAW.size_t {
		return try MDB_cursor_get_dupcount_static(cursor:self)
	}
}

extension MDB_cursor {

	/// get the current entry from the database
	public borrowing func setEntry(key:consuming MDB_val, value:consuming MDB_val, flags:consuming Operation.Flags) throws {
		return try MDB_cursor_set_entry_static(cursor:self, key:&key, value:&value, flags:flags)
	}
	
	/// get the current entry from the database
	public borrowing func containsEntry(key:consuming MDB_val, value:consuming MDB_val) throws -> Bool {
		return try MDB_cursor_contains_entry_static(cursor:self, key:&key, value:&value)
	}

	/// check if the current entry is present in the database
	public borrowing func containsEntry(key:consuming MDB_val) throws -> Bool {
		return try MDB_cursor_contains_entry_static(cursor:self, key:&key)
	}

	/// delete the current entry from the database
	public borrowing func deleteCurrentEntry(flags:consuming Operation.Flags) throws {
		return try MDB_cursor_delete_current_entry_static(cursor:self, flags:flags)
	}

	/// compare two MDB_val's based on the key comparison function of the cursor and its underlying database
	public borrowing func compareEntryKeys(_ dataL:consuming MDB_val, _ dataR:consuming MDB_val) -> Int32 {
		return MDB_cursor_compare_keys_static(cursor:self, lhs:&dataL, rhs:&dataR)
	}

	/// compare two MDB_val's based on the value comparison function of the cursor and its underlying database
	public borrowing func compareEntryValues(_ dataL:consuming MDB_val, _ dataR:consuming MDB_val) -> Int32 {
		return MDB_cursor_compare_values_static(cursor:self, lhs:&dataL, rhs:&dataR)
	}
}