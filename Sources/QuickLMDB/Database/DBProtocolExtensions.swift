import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

extension MDB_db where MDB_db_key_type:MDB_convertible, MDB_db_val_type:MDB_convertible {
	public borrowing func deleteEntry(key:borrowing MDB_db_key_type, value:borrowing MDB_db_val_type, tx:borrowing Transaction) throws {
		try key.MDB_access({ keyVal in
			try value.MDB_access({ valueVal in
				try deleteEntry(key:keyVal, value:valueVal, tx:tx)
			})
		})
	}

	public borrowing func deleteEntry(key:borrowing MDB_db_key_type, tx:borrowing Transaction) throws {
		try key.MDB_access({ keyVal in
			try deleteEntry(key:keyVal, tx:tx)
		})
	}

	public borrowing func setEntry(key:borrowing MDB_db_key_type, value:borrowing MDB_db_val_type, flags:consuming Operation.Flags, tx:borrowing Transaction) throws {
		switch flags.contains(.reserve) {
		case true:
			try key.MDB_access({ keyVal in
				try reserveEntry(key:keyVal, reservedSize:value.MDB_encodable_reserved_val(), flags:flags, tx:tx, { valVal in 
					value.MDB_encodable_write(reserved:valVal)
				})
			})
		case false:
			try key.MDB_access({ keyVal in
				try value.MDB_access({ valueVal in
					try setEntry(key:keyVal, value:valueVal, flags:flags, tx:tx)
				})
			})
		}
	}

	public borrowing func containsEntry(key:borrowing MDB_db_key_type, value:borrowing MDB_db_val_type, tx:borrowing Transaction) throws -> Bool {
		try key.MDB_access({ keyVal in
			try value.MDB_access({ valueVal in
				return try containsEntry(key:keyVal, value:valueVal, tx:tx)
			})
		})
	}

	public borrowing func containsEntry(key:borrowing MDB_db_key_type, tx:borrowing Transaction) throws -> Bool {
		try key.MDB_access({ keyVal in
			return try containsEntry(key:keyVal, tx:tx)
		})
	}

	public borrowing func loadEntry(key:borrowing MDB_db_key_type, as _:MDB_db_val_type.Type, tx:borrowing Transaction) throws -> MDB_db_val_type {
		try key.MDB_access({ keyVal in 
			return MDB_db_val_type(try loadEntry(key:keyVal, as:MDB_val.self, tx:tx))!
		})
	}
}

// every MDB_db will have the ability to exchange consuming MDB_val with the database at any time.
extension MDB_db {
	public borrowing func cursor<C:MDB_cursor>(as:C.Type, tx:borrowing Transaction) throws -> C {
		#if QUICKLMDB_SHOULDLOG
		return try C(db:self, tx:tx, logger:logger)
		#else
		return try C(db:self, tx:tx)
		#endif
	}

	// get entry implementations
	public borrowing func loadEntry(key keyVal:consuming MDB_val, as:MDB_val.Type, tx:borrowing Transaction) throws -> MDB_val {
		#if QUICKLMDB_SHOULDLOG
		return try MDB_db_get_entry_static(db:self, key:&keyVal, tx:tx, logger:logger)
		#else
		return try MDB_db_get_entry_static(db:self, key:&keyVal, tx:tx)
		#endif
	}
	public borrowing func containsEntry(key keyVal:consuming MDB_val, tx:borrowing Transaction) throws -> Bool {
		#if QUICKLMDB_SHOULDLOG
		return try MDB_db_contains_entry_static(db:self, key:&keyVal, tx:tx, logger:logger)
		#else
		return try MDB_db_contains_entry_static(db:self, key:&keyVal, tx:tx)
		#endif
	}
	public borrowing func containsEntry(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing Transaction) throws -> Bool {
		#if QUICKLMDB_SHOULDLOG
		return try MDB_db_contains_entry_static(db:self, key:&keyVal, value:&valueVal, tx:tx, logger:logger)
		#else
		return try MDB_db_contains_entry_static(db:self, key:&keyVal, value:&valueVal, tx:tx)
		#endif
	}
	
	// set entry implementation
	public borrowing func setEntry(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, flags:consuming Operation.Flags, tx:borrowing Transaction) throws {
		flags.subtract(.reserve)
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_set_entry_static(db:self, key:&keyVal, value:&valueVal, flags:flags, tx:tx, logger:logger)
		#else
		try MDB_db_set_entry_static(db:self, key:&keyVal, value:&valueVal, flags:flags, tx:tx)
		#endif
	}

	public borrowing func reserveEntry(key keyVal:consuming MDB_val, reservedSize valReserve:consuming MDB_val, flags:consuming Operation.Flags, tx:borrowing Transaction, _ handlerFunc:(consuming MDB_val) throws -> Void) throws {
		flags.formUnion(.reserve)

		#if DEBUG
		assert(valReserve.mv_size >= 0, "lmdb cannot reserve a buffer of negative size")
		#endif
		
		#if QUICKLMDB_SHOULDLOG
		try handlerFunc(try MDB_db_set_entry_static(db:self, returning:MDB_val.self, key:&keyVal, value:&valReserve, flags:flags, tx:tx, logger:logger))
		#else
		try handlerFunc(try MDB_db_set_entry_static(db:self, returning:MDB_val.self, key:&keyVal, value:&valReserve, flags:flags, tx:tx))
		#endif
	}
	
	// delete entry implementations
	public borrowing func deleteEntry(key keyVal:consuming MDB_val, tx:borrowing Transaction) throws {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_delete_entry_static(db:self, key:&keyVal, tx:tx, logger:logger)
		#else
		try MDB_db_delete_entry_static(db:self, key:&keyVal, tx:tx)
		#endif
	}
	public borrowing func deleteEntry(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing Transaction) throws {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_delete_entry_static(db:self, key:&keyVal, value:&valueVal, tx:tx, logger:logger)
		#else
		try MDB_db_delete_entry_static(db:self, key:&keyVal, value:&valueVal, tx:tx)
		#endif
	}
	public borrowing func deleteAllEntries(tx:borrowing Transaction) throws {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_delete_all_entries_static(db:self, tx:tx, logger:logger)
		#else
		try MDB_db_delete_all_entries_static(db:self, tx:tx)
		#endif
	}

	// metadata implementations
	public borrowing func dbStatistics(tx:borrowing Transaction) throws -> MDB_stat {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_get_statistics_static(db:self, tx:tx, logger:logger)
		#else
		try MDB_db_get_statistics_static(db:self, tx:tx)
		#endif
	}
	public borrowing func dbFlags(tx:borrowing Transaction) throws -> MDB_db_flags {
		#if QUICKLMDB_SHOULDLOG
		return MDB_db_flags(rawValue:try MDB_db_get_flags_static(db:self, tx:tx, logger:logger))
		#else
		return MDB_db_flags(rawValue:try MDB_db_get_flags_static(db:self, tx:tx))
		#endif
	}
}
