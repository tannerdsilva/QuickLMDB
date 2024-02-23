import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

extension MDB_db where MDB_db_key_type:MDB_convertible, MDB_db_key_ptrtype == UnsafePointer<MDB_db_key_type>, MDB_db_val_type:MDB_convertible, MDB_db_val_ptrtype == UnsafePointer<MDB_db_val_type> {
	public mutating func loadEntry<T>(key: UnsafePointer<MDB_db_key_type>, as:MDB_db_val_type.Type, tx: UnsafePointer<T>, myVar:myNonCopyable) throws -> MDB_db_val_type where T : MDB_tx {
		return try loadEntry(key: key, as:MDB_db_val_type.self, tx: tx)!
	}
	// reading entries in the database
	/// retrieve an entry from the database. if ``Database/Flags/dupSort`` is set and multiple entries exist for the specified key, the first entry will be returned
	///	- parameters:
	///		- key: a pointer to the type that conveys the key to search for.
	///		- tx: a pointer to the lmdb transaction that will be used to retrieve the entry.
	/// - throws: a corresponding ``LMDBError.notFound`` if the key does not exist, or other ``LMDBError`` for more obscure circumstances.
	///	- returns: the decoded value type.
	public mutating func loadEntry<T:MDB_tx>(key keyVal:MDB_db_key_ptrtype, tx:UnsafePointer<T>) throws -> MDB_db_val_type {
		return try keyVal.pointee.MDB_encodable_access { mdb_keyval in
			return MDB_db_val_type(try loadEntry(key:mdb_keyval, as:MDB_val.self, tx:tx))!
		}
	}

	public mutating func loadEntry<T:MDB_tx, V:MDB_decodable>(key keyVal:MDB_db_key_ptrtype, as:V.Type, tx:UnsafePointer<T>) throws -> V? {
		return try keyVal.pointee.MDB_encodable_access { mdb_keyval in
			return try V(loadEntry(key:mdb_keyval, as:MDB_val.self, tx:tx))
		}
	}
	
	public mutating func containsEntry<T:MDB_tx>(key keyVal:MDB_db_key_ptrtype, tx:UnsafePointer<T>) throws -> Bool {
		return try keyVal.pointee.MDB_encodable_access { mdb_keyval in
			return try containsEntry(key:mdb_keyval, tx:tx)
		}
	}

	public mutating func containsEntry<T:MDB_tx, V:MDB_convertible>(key keyVal:MDB_db_key_ptrtype, value valueVal:UnsafePointer<V>, tx:UnsafePointer<T>) throws -> Bool {
		return try keyVal.pointee.MDB_encodable_access { mdb_keyval in
			return try valueVal.pointee.MDB_encodable_access { mdb_valueval in
				return try containsEntry(key:mdb_keyval, value:mdb_valueval, tx:tx)
			}
		}
	}

	public mutating func setEntry<T:MDB_tx>(key keyVal:MDB_db_key_ptrtype, value valueVal:MDB_db_val_ptrtype, flags:Operation.Flags, tx:UnsafePointer<T>) throws {
		return try keyVal.pointee.MDB_encodable_access { mdb_keyval in
			return try valueVal.pointee.MDB_encodable_access { mdb_valueval in
				return try setEntry(key:mdb_keyval, value:mdb_valueval, flags:flags, tx:tx)
			}
		}
	}

	public mutating func deleteEntry<T:MDB_tx>(key keyVal:MDB_db_key_ptrtype, tx:UnsafePointer<T>) throws {
		return try keyVal.pointee.MDB_encodable_access { mdb_keyval in
			return try deleteEntry(key:mdb_keyval, tx:tx)
		}
	}

	public mutating func deleteEntry<T:MDB_tx, V:MDB_convertible>(key keyVal:MDB_db_key_ptrtype, value valueVal:UnsafePointer<V>, tx:UnsafePointer<T>) throws {
		return try keyVal.pointee.MDB_encodable_access { mdb_keyval in
			return try valueVal.pointee.MDB_encodable_access { mdb_valueval in
				return try deleteEntry(key:mdb_keyval, value:mdb_valueval, tx:tx)
			}
		}
	}

	public mutating func deleteAllEntries<T:MDB_tx>(tx:UnsafePointer<T>) throws {
		return try deleteAllEntries(tx:tx)
	}
}

// every MDB_db will have the ability to exchange UnsafeMutablePointer<MDB_val> with the database at any time.
extension MDB_db {
	public mutating func cursor<C:MDB_cursor, T:MDB_tx>(as:C.Type, tx:UnsafePointer<T>) throws -> C {
		#if QUICKLMDB_SHOULDLOG
		return try C(db:&self, tx:tx, logger:logger)
		#else
		return try C(db:&self, tx:tx)
		#endif
	}

	// get entry implementations
	public mutating func loadEntry<T:MDB_tx>(key keyVal:UnsafeMutablePointer<MDB_val>, as:MDB_val.Type, tx:UnsafePointer<T>) throws -> MDB_val {
		#if QUICKLMDB_SHOULDLOG
		return try MDB_db_get_entry_static(&self, key:keyVal, tx:tx, logger:logger)
		#else
		return try MDB_db_get_entry_static(&self, key:keyVal, tx:tx)
		#endif
	}
	public mutating func containsEntry<T:MDB_tx>(key keyVal:UnsafeMutablePointer<MDB_val>, tx:UnsafePointer<T>) throws -> Bool {
		#if QUICKLMDB_SHOULDLOG
		return try MDB_db_contains_entry_static(&self, key:keyVal, value:nil, tx:tx, logger:logger)
		#else
		return try MDB_db_contains_entry_static(&self, key:keyVal, value:nil, tx:tx)
		#endif
	}
	public mutating func containsEntry<T:MDB_tx>(key keyVal:UnsafeMutablePointer<MDB_val>, value valueVal:UnsafeMutablePointer<MDB_val>, tx:UnsafePointer<T>) throws -> Bool {
		#if QUICKLMDB_SHOULDLOG
		return try MDB_db_contains_entry_static(&self, key:keyVal, value:valueVal, tx:tx, logger:logger)
		#else
		return try MDB_db_contains_entry_static(&self, key:keyVal, value:valueVal, tx:tx)
		#endif
	}
	
	// set entry implementation
	public mutating func setEntry<T:MDB_tx>(key keyVal:UnsafeMutablePointer<MDB_val>, value valueVal:UnsafeMutablePointer<MDB_val>, flags:Operation.Flags, tx:UnsafePointer<T>) throws {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_set_entry_static(&self, key:keyVal, value:valueVal, flags:flags, tx:tx, logger:logger)
		#else
		try MDB_db_set_entry_static(&self, key:keyVal, value:valueVal, flags:flags, tx:tx)
		#endif
	}
	
	// delete entry implementations
	public mutating func deleteEntry<T:MDB_tx>(key keyVal:UnsafeMutablePointer<MDB_val>, tx:UnsafePointer<T>) throws {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_delete_entry_static(&self, key:keyVal, value:nil, tx:tx, logger:logger)
		#else
		try MDB_db_delete_entry_static(&self, key:keyVal, value:nil, tx:tx)
		#endif
	}
	public mutating func deleteEntry<T:MDB_tx>(key keyPtr:UnsafeMutablePointer<MDB_val>, value valueVal:UnsafeMutablePointer<MDB_val>, tx:UnsafePointer<T>) throws {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_delete_entry_static(&self, key:keyPtr, value:valueVal, tx:tx, logger:logger)
		#else
		try MDB_db_delete_entry_static(&self, key:keyPtr, value:valueVal, tx:tx)
		#endif
	}
	public mutating func deleteAllEntries<T:MDB_tx>(tx:UnsafePointer<T>) throws {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_delete_all_entries_static(&self, tx:tx, logger:logger)
		#else
		try MDB_db_delete_all_entries_static(&self, tx:tx)
		#endif
	}

	// metadata implementations
	public mutating func dbStatistics<T:MDB_tx>(tx:UnsafePointer<T>) throws -> MDB_stat {
		#if QUICKLMDB_SHOULDLOG
		try MDB_db_get_statistics_static(&self, tx:tx, logger:logger)
		#else
		try MDB_db_get_statistics_static(&self, tx:tx)
		#endif
	}
	public mutating func dbFlags<T:MDB_tx>(tx:UnsafePointer<T>) throws -> MDB_db_flags {
		#if QUICKLMDB_SHOULDLOG
		return MDB_db_flags(rawValue:try MDB_db_get_flags_static(&self, tx:tx, logger:logger))
		#else
		return MDB_db_flags(rawValue:try MDB_db_get_flags_static(&self, tx:tx))
		#endif
	}
}

