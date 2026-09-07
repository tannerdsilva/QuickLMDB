import CLMDB
import RAW

// every MDB_db will have the ability to exchange consuming MDB_val with the database at any time.
extension MDB_db {
	public borrowing func cursor<R, E>(tx:borrowing Transaction, _ handler:(consuming MDB_db_cursor_type) throws(E) -> R) throws(E) -> R where E:Swift.Error {
		return try handler(try! MDB_db_cursor_type(db:self, tx:tx))
	}

	// get entry implementations
	public borrowing func loadEntry(key keyVal:consuming MDB_val, as:MDB_val.Type, tx:borrowing Transaction) throws(LMDBError) -> MDB_val {
		return try MDB_db_get_entry(db:self.dbHandle(), key:keyVal, tx:tx.txHandle())
	}
	public borrowing func containsEntry(key keyVal:consuming MDB_val, tx:borrowing Transaction) throws(LMDBError) -> Bool {
		return try MDB_db_contains_entry(db:self.dbHandle(), key:keyVal, tx:tx.txHandle())
	}
	
	// set entry implementation
	public borrowing func setEntry(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, flags:consuming Operation.Flags, tx:borrowing Transaction) throws(LMDBError) {
		try MDB_db_set_entry(db:self.dbHandle(), key:keyVal, value:valueVal, flags:flags.rawValue, tx:tx.txHandle())
	}

	// delete entry implementations
	public borrowing func deleteEntry(key keyVal:consuming MDB_val, tx:borrowing Transaction) throws(LMDBError) {
		try MDB_db_delete_entry(db:self.dbHandle(), key:keyVal, tx:tx.txHandle())
	}
	public borrowing func deleteEntry(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing Transaction) throws(LMDBError) {
		try MDB_db_delete_entry(db:self.dbHandle(), key:keyVal, value:valueVal, tx:tx.txHandle())
	}
	public borrowing func deleteAllEntries(tx:borrowing Transaction) throws(LMDBError) {
		try MDB_db_delete_all_entries(db:self.dbHandle(), tx:tx.txHandle())
	}
	public consuming func deleteDatabase(tx:borrowing Transaction) throws(LMDBError) {
		try MDB_db_delete_database(db:self.dbHandle(), tx:tx.txHandle())
	}

	// metadata implementations
	public borrowing func dbStatistics(tx:borrowing Transaction) throws(LMDBError) -> MDB_stat {
		try MDB_db_get_statistics(db:self.dbHandle(), tx:tx.txHandle())
	}
	public borrowing func dbFlags(tx:borrowing Transaction) throws(LMDBError) -> MDB_db_flags {
		return MDB_db_flags(rawValue:try MDB_db_get_flags(db:self.dbHandle(), tx:tx.txHandle()))
	}

	// compare-function assignment (database config-time plumbing, used by the typed handle inits)
	@available(*, noasync)
	internal borrowing func assignCompareKey(_ compare:MDB_cmp_func_t, tx:borrowing Transaction) {
		MDB_db_assign_compare_key(db:self.dbHandle(), compare:compare, tx:tx.txHandle())
	}
	@available(*, noasync)
	internal borrowing func assignCompareVal(_ compare:MDB_cmp_func_t, tx:borrowing Transaction) {
		MDB_db_assign_compare_val(db:self.dbHandle(), compare:compare, tx:tx.txHandle())
	}
}