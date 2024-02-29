import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

extension MDB_db where MDB_db_key_type:MDB_convertible, MDB_db_val_type:MDB_convertible {
//	public func deleteEntry(key:borrowing MDB_db_key_type, value:consuming MDB_db_val_type, tx:borrowing Transaction) throws {
//		try key.MDB_access({ keyVal in
//			try value.MDB_access({ valueVal in
//				try deleteEntry(key:keyVal, value:valueVal, tx:tx)
//			})
//		})
//	}

//	public func deleteEntry(key:borrowing MDB_db_key_type, tx:borrowing Transaction) throws {
//		try key.MDB_access({ keyVal in
//			try deleteEntry(key:keyVal, tx:tx)
//		})
//	}

//	public func setEntry(key:borrowing MDB_db_key_type, value:consuming MDB_db_val_type, flags:consuming Operation.Flags, tx:borrowing Transaction) throws {
//		switch flags.contains(.reserve) {
//		case true:
//			try key.MDB_access({ keyVal in
//				try reserveEntry(key:keyVal, reservedSize:value.MDB_encodable_reserved_val(), flags:flags, tx:tx, { valVal in 
//					value.MDB_encodable_write(reserved:valVal)
//				})
//			})
//		case false:
//			try key.MDB_access({ keyVal in
//				try value.MDB_access({ valueVal in
//					try setEntry(key:keyVal, value:valueVal, flags:flags, tx:tx)
//				})
//			})
//		}
//	}

//	public func containsEntry(key:borrowing MDB_db_key_type, value:consuming MDB_db_val_type, tx:borrowing Transaction) throws -> Bool {
//		try key.MDB_access({ keyVal in
//			return try value.MDB_access({ valueVal in
//				return try containsEntry(key:keyVal, value:valueVal, tx:tx)
//			})
//		})
//	}

//	public func containsEntry(key:borrowing MDB_db_key_type, tx:borrowing Transaction) throws -> Bool {
//		try key.MDB_access({ keyVal in
//			return try containsEntry(key:keyVal, tx:tx)
//		})
//	}

	public func loadEntry(key:borrowing MDB_db_key_type, as _:MDB_db_val_type.Type, tx:borrowing Transaction) throws -> MDB_db_val_type {
		try key.MDB_access({ keyVal in 
			return MDB_db_val_type(try loadEntry(key:keyVal, as:MDB_val.self, tx:tx))!
		})
	}
}

extension MDB_db {
	public func deleteEntry<K:RAW_accessible, V:RAW_accessible>(key:borrowing K, value:consuming V, tx:borrowing Transaction) throws {
		try key.MDB_access({ keyVal in
			try value.MDB_access({ valueVal in
				try deleteEntry(key:keyVal, value:valueVal, tx:tx)
			})
		})
	}

	public func deleteEntry<K:RAW_accessible>(key:borrowing K, tx:borrowing Transaction) throws {
		try key.MDB_access({ keyVal in
			try deleteEntry(key:keyVal, tx:tx)
		})
	}

	public func setEntry<K:RAW_accessible, V:RAW_accessible & RAW_encodable>(key:borrowing K, value:consuming V, flags:consuming Operation.Flags, tx:borrowing Transaction) throws {
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

	public func containsEntry<K:RAW_accessible, V:RAW_accessible>(key:borrowing K, value:consuming V, tx:borrowing Transaction) throws -> Bool {
		try key.MDB_access({ keyVal in
			return try value.MDB_access({ valueVal in
				return try containsEntry(key:keyVal, value:valueVal, tx:tx)
			})
		})
	}
	
	public func containsEntry<K:RAW_accessible>(key:borrowing K, tx:borrowing Transaction) throws -> Bool {
		try key.MDB_access({ keyVal in
			return try containsEntry(key:keyVal, tx:tx)
		})
	}
	public func loadEntry<K:RAW_accessible, V:RAW_decodable>(key:borrowing K, as _:V.Type, tx:borrowing Transaction) throws -> V? {
		try key.MDB_access({ keyVal in 
			return V(try loadEntry(key:keyVal, as:MDB_val.self, tx:tx))
		})
	}
}

// every MDB_db will have the ability to exchange consuming MDB_val with the database at any time.
extension MDB_db {
	public borrowing func cursor<C:MDB_cursor, R>(as:C.Type, tx:borrowing Transaction, _ handler:(consuming C) throws -> R) rethrows -> R where C.MDB_cursor_dbtype == Self {
		return try handler(try! C(db:self, tx:tx))
	}

	// get entry implementations
	public borrowing func loadEntry(key keyVal:consuming MDB_val, as:MDB_val.Type, tx:borrowing Transaction) throws -> MDB_val {
		return try MDB_db_get_entry_static(db:self, key:&keyVal, tx:tx)
	}
	public borrowing func containsEntry(key keyVal:consuming MDB_val, tx:borrowing Transaction) throws -> Bool {
		return try MDB_db_contains_entry_static(db:self, key:&keyVal, tx:tx)
	}
	public borrowing func containsEntry(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing Transaction) throws -> Bool {
		return try MDB_db_contains_entry_static(db:self, key:&keyVal, value:&valueVal, tx:tx)
	}
	
	// set entry implementation
	public borrowing func setEntry(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, flags:consuming Operation.Flags, tx:borrowing Transaction) throws {
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
	public borrowing func deleteEntry(key keyVal:consuming MDB_val, tx:borrowing Transaction) throws {
		try MDB_db_delete_entry_static(db:self, key:&keyVal, tx:tx)
	}
	public borrowing func deleteEntry(key keyVal:consuming MDB_val, value valueVal:consuming MDB_val, tx:borrowing Transaction) throws {
		try MDB_db_delete_entry_static(db:self, key:&keyVal, value:&valueVal, tx:tx)
	}
	public borrowing func deleteAllEntries(tx:borrowing Transaction) throws {
		try MDB_db_delete_all_entries_static(db:self, tx:tx)
	}

	// metadata implementations
	public borrowing func dbStatistics(tx:borrowing Transaction) throws -> MDB_stat {
		try MDB_db_get_statistics_static(db:self, tx:tx)
	}
	public borrowing func dbFlags(tx:borrowing Transaction) throws -> MDB_db_flags {
		return MDB_db_flags(rawValue:try MDB_db_get_flags_static(db:self, tx:tx))
	}
}

