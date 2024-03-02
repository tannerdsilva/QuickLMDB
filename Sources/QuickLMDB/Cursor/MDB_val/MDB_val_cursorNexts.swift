extension MDB_cursor {
	// next implementations
	public borrowing func opNext() throws {
		try MDB_cursor_get_entry_static(cursor:self, .next)
	}
	public borrowing func opNextDup() throws {
		try MDB_cursor_get_entry_static(cursor:self, .nextDup)
	}
	public borrowing func opNextNoDup() throws {
		try MDB_cursor_get_entry_static(cursor:self, .nextNoDup)
	}
}
