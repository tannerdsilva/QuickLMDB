extension MDB_cursor {
	// first implementations
	public borrowing func opFirst() throws {
		try MDB_cursor_get_entry_static(cursor:self, .first)
	}
	public borrowing func opFirstDup() throws {
		try MDB_cursor_get_entry_static(cursor:self, .firstDup)
	}
}