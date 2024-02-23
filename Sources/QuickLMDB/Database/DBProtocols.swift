import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

public protocol MDB_db_v2 {

	var envHandle:OpaquePointer { get }

	var dbName:String? { get }

	var dbHandle:MDB_dbi { get }

	mutating func setEntry<T:MDB_tx>(key:consuming MDB_val , value:consuming MDB_val, flags:Operation.Flags, tx:UnsafePointer<T>) throws
}

extension MDB_db_v2 {
	public mutating func setEntry<T:MDB_tx>(key keyVal:inout MDB_val, value valueVal:consuming MDB_val, flags:Operation.Flags, tx:UnsafePointer<T>) throws {
		// return try keyVal.MDB_encodable_access { mdb_keyval in
			// return try valueVal.MDB_encodable_access { mdb_valueval in
				return try setEntry(key:&keyVal, value:mdb_valueval, flags:flags, tx:tx)
			// }
		// }
	}
}

public protocol MDB_db {
	
	/// the type that the database is exchanging as the key value
	associatedtype MDB_db_key_type = MDB_db_key_ptrtype.Pointee
	/// a pointer to the key type
	associatedtype MDB_db_key_ptrtype:_Pointer where MDB_db_key_ptrtype.Pointee == MDB_db_key_type
	/// the type that the database is exchanging as the value value
	associatedtype MDB_db_val_type = MDB_db_val_ptrtype.Pointee
	/// a pointer to the value type
	associatedtype MDB_db_val_ptrtype:_Pointer where MDB_db_val_ptrtype.Pointee == MDB_db_val_type

	/// the environment handle primitive that this database instance is based on
	var envHandle:OpaquePointer { get }
	/// the LMDB database name of this instance
	var dbName:String? { get }
	/// the database handle primitive for this instance
	var dbHandle:MDB_dbi { get }

	#if QUICKLMDB_SHOULDLOG
	/// the primary logging facility that this database will use for debugging and auditing
	var logger:Logger? { get }
	/// create a new database from the specified environment
	/// - parameters:
	/// 	- env: a pointer to the environment that the database
	/// 	- name: the name of the database to 
	init<E:MDB_env, T:MDB_tx>(env:UnsafePointer<E>, name:String?, flags:MDB_db_flags, tx:UnsafePointer<T>, logger:Logger?) throws
	#else
	/// create a new database from the specified environment
	init<E:MDB_env, T:MDB_tx>(env:UnsafePointer<E>, name:String?, flags:MDB_db_flags, tx:UnsafePointer<T>) throws
	#endif
	
	// create a cursor 
	/// creates a cursor of a specified type that can traverse the contents of the database instance.
	/// - parameters:
	///		- as: the cursor type that will be initialized to traverse the database.
	///		- tx: a pointer to the transaction to use for the creation of the cursor.
	/// - throws: a corresponding ``LMDBError.notFound`` if the entry could not be found.
	/// - returns: the newly initialized instance of the cursor type.
	mutating func cursor<C:MDB_cursor, T:MDB_tx>(as:C.Type, tx:UnsafePointer<T>) throws -> C

	// reading entries in the database
	/// retrieve an entry from the database. if ``Database/Flags/dupSort`` is set and multiple entries exist for the specified key, the first entry will be returned
	///	- parameters:
	///		- key: a pointer to the type that conveys the key to search for.
	///		- as: the value type to return as a conveyance of the value that would be found in the database.
	///		- tx: a pointer to the lmdb transaction that will be used to retrieve the entry.
	/// - throws: a corresponding ``LMDBError.notFound`` if the key does not exist, or other ``LMDBError`` for more obscure circumstances.
	///	- returns: the decoded value type.
	mutating func loadEntry<T:MDB_tx>(key:MDB_db_key_ptrtype, as:MDB_db_val_type.Type, tx:UnsafePointer<T>) throws -> MDB_db_val_type
	
	/// check if an entry key exists in the database
	/// - parameters:
	/// 	- key: a pointer to the type that conveys the key to search for. this function reserves the right to modify the value pointed to by this pointer. contents of the pointed value should not be handled after this function is called.
	/// 	- tx: a pointer to the lmdb transaction that will be used to check for the entry.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be found.
	/// - returns: true if an entry exists, false if it does not.
	mutating func containsEntry<T:MDB_tx>(key:MDB_db_key_ptrtype, tx:UnsafePointer<T>) throws -> Bool
	/// check if an entry key and value exists in the database
	/// - parameters:
	/// 	- key: a pointer to the type that conveys the key to search for. this function reserves the right to modify the value pointed to by this pointer. contents of the pointed value should not be handled after this function is called.
	/// 	- value: a pointer to the type that conveys the value to search for. this function reserves the right to modify the value pointed to by this pointer. contents of the pointed value should not be handled after this function is called.
	/// 	- tx: a pointer to the lmdb transaction that will be used to check for the entry.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be found.
	/// - returns: true if the entry exists, false if it does not.
	mutating func containsEntry<T:MDB_tx>(key:MDB_db_key_ptrtype, value:MDB_db_val_ptrtype, tx:UnsafePointer<T>) throws -> Bool
	
	// writing entries to the database
	/// assign an entry to the database. flags can be used to modify the behavior of the entry assignment as needed
	/// - parameters:
	/// 	- key: a pointer to the type that conveys the key that will be set in the database. this function reserves the right to modify the value pointed to by this pointer. contents of the pointed value should not be handled after this function is called.
	/// 	- value: a pointer to the type that conveys the value that will be set in the database. this function reserves the right to modify the value pointed to by this pointer. contents of the pointed value should not be handled after this function is called.
	/// 	- flags: the flags that will be used when assigning the entry in the database.
	/// 	- tx: a pointer to the lmdb transaction that will be used to set the entry.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be set. the particular set of errors that can be thrown are dependent on the database and environment flags being used, as well as the operation flags.
	mutating func setEntry<T:MDB_tx>(key:MDB_db_key_ptrtype, value:MDB_db_val_ptrtype, flags:Operation.Flags, tx:UnsafePointer<T>) throws

	// remove entries from the database.
	/// remove all entries matching a specified key from the database
	/// - parameters:
	/// 	- key: the key that will be removed from the database.
	/// 	- tx: the transaction to use for the entry removal.
	mutating func deleteEntry<T:MDB_tx>(key:MDB_db_key_ptrtype, tx:UnsafePointer<T>) throws
	/// remove a specific key and value pairing from the database
	/// - parameters:
	/// 	- key: the key that will be removed from the database.
	/// 	- value: the value that will be removed from the database.
	/// 	- tx: the transaction to use for the entry removal.
	/// - note: despite this function requiring inout parameters, the passed values are not mutated. they are treated as read-only values.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be removed.
	mutating func deleteEntry<T:MDB_tx>(key:MDB_db_key_ptrtype, value:MDB_db_val_ptrtype, tx:UnsafePointer<T>) throws
	/// remove all entries from the database
	/// - parameters:
	/// 	- tx: the transaction to use for the entry removal.
	/// - throws: a corresponding ``LMDBError`` if the entries could not be removed.
	mutating func deleteAllEntries<T:MDB_tx>(tx:UnsafePointer<T>) throws

	// metadata
	/// returns the statistics for the database
	/// - parameters:
	/// 	- tx: the transaction to use for the statistics retrieval.
	/// - throws: a corresponding ``LMDBError`` if the statistics could not be retrieved.
	mutating func dbStatistics<T:MDB_tx>(tx:UnsafePointer<T>) throws -> MDB_stat
	/// returns the flags that were used when opening the database
	/// - parameters:
	/// 	- tx: the transaction to use for the flags retrieval.
	/// - throws: a corresponding ``LMDBError`` if the flags could not be retrieved.
	mutating func dbFlags<T:MDB_tx>(tx:UnsafePointer<T>) throws -> MDB_db_flags
}

extension MDB_db {
	public mutating func loadEntry<T:MDB_tx>(key keyVal:MDB_db_key_ptrtype, tx:UnsafePointer<T>) throws -> MDB_db_val_type {
		return try self.loadEntry(key:keyVal, as:MDB_db_val_type.self, tx:tx)
	}
}
