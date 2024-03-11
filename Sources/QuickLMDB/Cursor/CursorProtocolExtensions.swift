extension MDB_cursor {
	public consuming func makeDupIterator(key:consuming MDB_cursor_dbtype.MDB_db_key_type) -> DatabaseDupIterator<Self> {
		return DatabaseDupIterator(self, key:key)
	}
}