extension MDB_cursor {
	// previous implementations
	public borrowing func opPrevious() throws {
		try MDB_cursor_get_entry_static(cursor:self, .previous)
	}
	public borrowing func opPreviousDup() throws {
		try MDB_cursor_get_entry_static(cursor:self, .previousDup)
	}
	public borrowing func opPreviousNoDup() throws {
		try MDB_cursor_get_entry_static(cursor:self, .previousNoDup)
	}
}