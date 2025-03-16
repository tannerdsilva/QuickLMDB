import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

// every MDB_db will have the ability to exchange consuming MDB_val with the database at any time.
extension MDB_db {
	public borrowing func cursor<R, E>(tx:borrowing Transaction, _ handler:(consuming MDB_db_cursor_type) throws(E) -> R) throws(E) -> R {
		return try handler(try! MDB_db_cursor_type(db:self, tx:tx))
	}

	// get entry implementations
	public borrowing func loadEntry(key keyVal:consuming MDB_val, as:MDB_val.Type, tx:borrowing Transaction) throws(LMDBError) -> MDB_val {
		return try MDB_db_get_entry_static(db:self, key:&keyVal, tx:tx)
	}
	public borrowing func containsEntry(key keyVal:consuming MDB_val, tx:borrowing Transaction) throws(LMDBError) -> Bool {
		return try MDB_db_contains_entry_static(db:self, key:&keyVal, tx:tx)
	}
	public borrowing func containsEntry(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing Transaction) throws(LMDBError) -> Bool {
		return try MDB_db_contains_entry_static(db:self, key:&keyVal, value:&valueVal, tx:tx)
	}
	
	// set entry implementation
	public borrowing func setEntry(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, flags:consuming Operation.Flags, tx:borrowing Transaction) throws(LMDBError) {
		flags.subtract(.reserve)
		try MDB_db_set_entry_static(db:self, key:&keyVal, value:&valueVal, flags:flags, tx:tx)
	}
	
	public borrowing func reserveEntry(key keyVal:consuming MDB_val, reservedSize valReserve:consuming MDB_val, flags:consuming Operation.Flags, tx:borrowing Transaction, _ handlerFunc:(consuming MDB_val) throws -> Void) throws {
		flags.formUnion(.reserve)
		#if DEBUG
		assert(valReserve.mv_size >= 0, "lmdb cannot reserve a buffer of negative size")
		#endif
		
		try handlerFunc(try MDB_db_set_entry_static(db:self, returning:MDB_val.self, key:&keyVal, value:&valReserve, flags:flags, tx:tx))
	}
	
	// delete entry implementations
	public borrowing func deleteEntry(key keyVal:consuming MDB_val, tx:borrowing Transaction) throws(LMDBError) {
		try MDB_db_delete_entry_static(db:self, key:&keyVal, tx:tx)
	}
	public borrowing func deleteEntry(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing Transaction) throws(LMDBError) {
		try MDB_db_delete_entry_static(db:self, key:&keyVal, value:&valueVal, tx:tx)
	}
	public borrowing func deleteAllEntries(tx:borrowing Transaction) throws(LMDBError) {
		try MDB_db_delete_all_entries_static(db:self, tx:tx)
	}

	// metadata implementations
	public borrowing func dbStatistics(tx:borrowing Transaction) throws(LMDBError) -> MDB_stat {
		try MDB_db_get_statistics_static(db:self, tx:tx)
	}
	public borrowing func dbFlags(tx:borrowing Transaction) throws(LMDBError) -> MDB_db_flags {
		return MDB_db_flags(rawValue:try MDB_db_get_flags_static(db:self, tx:tx))
	}
}