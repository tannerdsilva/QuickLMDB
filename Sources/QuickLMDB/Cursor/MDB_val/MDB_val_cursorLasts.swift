extension MDB_cursor {
	// last implementations
	public borrowing func opLast() throws {
		try MDB_cursor_get_entry_static(cursor:self, .last)
	}
	public borrowing func opLastDup() throws {
		try MDB_cursor_get_entry_static(cursor:self, .lastDup)
	}
}