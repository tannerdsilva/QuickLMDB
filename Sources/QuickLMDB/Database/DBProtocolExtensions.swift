import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

extension MDB_db where MDB_db_key_type:MDB_convertible, MDB_db_val_type:MDB_convertible {
	public borrowing func deleteEntry<T:MDB_tx>(key:borrowing MDB_db_key_type, value:borrowing MDB_db_val_type, tx:borrowing T) throws {
		try key.MDB_encodable_access({ keyVal in 
			try value.MDB_encodable_access({ valueVal in 
				try deleteEntry(key:keyVal, value:valueVal, tx:tx)
			})
		})
	}

	public borrowing func deleteEntry<T:MDB_tx>(key:borrowing MDB_db_key_type, tx:borrowing T) throws where T : MDB_tx {
		try key.MDB_encodable_access({ keyVal in 
			try deleteEntry(key:keyVal, tx:tx)
		})
	}

	public borrowing func setEntry<T:MDB_tx>(key:borrowing MDB_db_key_type, value:borrowing MDB_db_val_type, flags:Operation.Flags, tx:borrowing T) throws {
		try key.MDB_encodable_access({ keyVal in 
			try value.MDB_encodable_access({ valueVal in 
				try setEntry(key:keyVal, value:valueVal, flags:flags, tx:tx)
			})
		})
	}

	public borrowing func containsEntry<T:MDB_tx>(key:borrowing MDB_db_key_type, value:borrowing MDB_db_val_type, tx:borrowing T) throws -> Bool {
		try key.MDB_encodable_access({ keyVal in 
			try value.MDB_encodable_access({ valueVal in 
				return try containsEntry(key:keyVal, value:valueVal, tx:tx)
			})
		})
	}

	public borrowing func containsEntry<T:MDB_tx>(key:borrowing MDB_db_key_type, tx:borrowing T) throws -> Bool {
		try key.MDB_encodable_access({ keyVal in 
			return try containsEntry(key:keyVal, tx:tx)
		})
	}

	public borrowing func loadEntry<T:MDB_tx>(key:borrowing MDB_db_key_type, as _:MDB_db_val_type.Type, tx: borrowing T) throws -> MDB_db_val_type {
		try key.MDB_encodable_access({ keyVal in 
			return MDB_db_val_type(try loadEntry(key:keyVal, as:MDB_val.self, tx:tx))!
		})
	}
}

// every MDB_db will have the ability to exchange consuming MDB_val with the database at any time.
extension MDB_db {
	public borrowing func cursor<C:MDB_cursor, T:MDB_tx>(as:C.Type, tx:borrowing T) throws -> C {
		#if QUICKLMDB_SHOULDLOG
		return try C(db:self, tx:tx, logger:logger)
		#else
		return try C(db:self, tx:tx)
		#endif
	}

	// get entry implementations
	public borrowing func loadEntry<T:MDB_tx>(key keyVal:consuming MDB_val, as:MDB_val.Type, tx:borrowing T) throws -> MDB_val {
		#if QUICKLMDB_SHOULDLOG
		return try MDB_db_get_entry_static(self, key:keyVal, tx:tx, logger:logger)
		#else
		return try MDB_db_get_entry_static(self, key:keyVal, tx:tx)
		#endif
	}
	public borrowing func containsEntry<T:MDB_tx>(key keyVal:consuming MDB_val, tx:borrowing T) throws -> Bool {
		#if QUICKLMDB_SHOULDLOG
		return try MDB_db_contains_entry_static(self, key:keyVal, tx:tx, logger:logger)
		#else
		return try MDB_db_contains_entry_static(self, key:keyVal, tx:tx)
		#endif
	}
	public borrowing func containsEntry<T:MDB_tx>(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing T) throws -> Bool {
		#if QUICKLMDB_SHOULDLOG
		return try MDB_db_contains_entry_static(self, key:keyVal, value:valueVal, tx:tx, logger:logger)
		#else
		return try MDB_db_contains_entry_static(self, key:keyVal, value:valueVal, tx:tx)
		#endif
	}
	
	// set entry implementation
	public borrowing func setEntry<T:MDB_tx>(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, flags:consuming Operation.Flags, tx:borrowing T) throws {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_set_entry_static(self, key:keyVal, value:valueVal, flags:flags, tx:tx, logger:logger)
		#else
		try MDB_db_set_entry_static(self, key:keyVal, value:valueVal, flags:flags, tx:tx)
		#endif
	}
	
	// delete entry implementations
	public borrowing func deleteEntry<T:MDB_tx>(key keyVal:consuming MDB_val, tx:borrowing T) throws {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_delete_entry_static(self, key:keyVal, tx:tx, logger:logger)
		#else
		try MDB_db_delete_entry_static(self, key:keyVal, tx:tx)
		#endif
	}
	public borrowing func deleteEntry<T:MDB_tx>(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing T) throws {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_delete_entry_static(self, key:keyVal, value:valueVal, tx:tx, logger:logger)
		#else
		try MDB_db_delete_entry_static(self, key:keyVal, value:valueVal, tx:tx)
		#endif
	}
	public borrowing func deleteAllEntries<T:MDB_tx>(tx:borrowing T) throws {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_delete_all_entries_static(self, tx:tx, logger:logger)
		#else
		try MDB_db_delete_all_entries_static(self, tx:tx)
		#endif
	}

	// metadata implementations
	public borrowing func dbStatistics<T:MDB_tx>(tx:borrowing T) throws -> MDB_stat {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_get_statistics_static(self, tx:tx, logger:logger)
		#else
		try MDB_db_get_statistics_static(self, tx:tx)
		#endif
	}
	public borrowing func dbFlags<T:MDB_tx>(tx:borrowing T) throws -> MDB_db_flags {
		#if QUICKLMDB_SHOULDLOG
		return MDB_db_flags(rawValue:try MDB_db_get_flags_static(self, tx:tx, logger:logger))
		#else
		return MDB_db_flags(rawValue:try MDB_db_get_flags_static(self, tx:tx))
		#endif
	}
}

