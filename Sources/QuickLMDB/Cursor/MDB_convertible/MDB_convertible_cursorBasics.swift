extension MDB_cursor where MDB_cursor_dbtype.MDB_db_key_type:MDB_convertible, MDB_cursor_dbtype.MDB_db_val_type:MDB_convertible {
	public borrowing func opPreviousNoDup(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		return try opPreviousNoDup(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! })
	}

	public borrowing func opPreviousDup(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		return try opPreviousDup(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! })
	}

	public borrowing func opPrevious(returning: (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		return try opPrevious(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! })
	}
}