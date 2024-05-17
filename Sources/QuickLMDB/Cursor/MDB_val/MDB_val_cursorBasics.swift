import RAW

// extension MDB_cursor_strict {
// 	/// traditional 'makeiterator' that allows a cursor to conform to Sequence
// 	public func makeIterator() -> DatabaseIterator<Self> {
// 		return DatabaseIterator(self)
// 	}
// }

extension MDB_cursor {
	public borrowing func dupCount() throws -> RAW.size_t {
		return try MDB_cursor_get_dupcount_static(cursor:self)
	}

	public borrowing func setEntry(key:consuming MDB_val, value:consuming MDB_val, flags:Operation.Flags) throws {
		return try MDB_cursor_set_entry_static(cursor:self, key:&key, value:&value, flags:flags)
	}
	
	public borrowing func containsEntry(key:consuming MDB_val, value:consuming MDB_val) throws -> Bool {
		return try MDB_cursor_contains_entry_static(cursor:self, key:&key, value:&value)
	}

	public borrowing func containsEntry(key:consuming MDB_val) throws -> Bool {
		return try MDB_cursor_contains_entry_static(cursor:self, key:&key)
	}

	public borrowing func deleteCurrentEntry(flags:Operation.Flags) throws {
		return try MDB_cursor_delete_current_entry_static(cursor:self, flags:flags)
	}

	public borrowing func compareEntryKeys(_ dataL:consuming MDB_val, _ dataR:consuming MDB_val) -> Int32 {
		return MDB_cursor_compare_keys_static(cursor:self, lhs:&dataL, rhs:&dataR)
	}

	public borrowing func compareEntryValues(_ dataL:consuming MDB_val, _ dataR:consuming MDB_val) -> Int32 {
		return MDB_cursor_compare_values_static(cursor:self, lhs:&dataL, rhs:&dataR)
	}
}