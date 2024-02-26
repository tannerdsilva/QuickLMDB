import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

public protocol MDB_db {
	
	/// the type that the database is exchanging as the key value
	associatedtype MDB_db_key_type
	/// the type that the database is exchanging as the value value
	associatedtype MDB_db_val_type

	#if QUICKLMDB_SHOULDLOG
	/// the primary logging facility that this database will use for debugging and auditing
	borrowing func logger() -> Logger?
	/// create a new database from the specified environment
	/// - parameters:
	/// 	- env: a pointer to the environment that the database
	/// 	- name: the name of the database to 
	init(env:borrowing Environment, name:String?, flags:MDB_db_flags, tx:borrowing Transaction, logger:Logger?) throws
	#else
	/// create a new database from the specified environment
	init(env:borrowing Environment, name:String?, flags:MDB_db_flags, tx:borrowing Transaction) throws
	#endif
	
	borrowing func dbHandle() -> MDB_dbi
	
	// get the database name
	/// returns the name of the database, if one exists
	borrowing func dbName() -> String?
	
	// create a cursor 
	/// creates a cursor of a specified type that can traverse the contents of the database instance.
	/// - parameters:
	///		- as: the cursor type that will be initialized to traverse the database.
	///		- tx: a pointer to the transaction to use for the creation of the cursor.
	/// - throws: a corresponding ``LMDBError.notFound`` if the entry could not be found.
	/// - returns: the newly initialized instance of the cursor type.
	borrowing func cursor<C:MDB_cursor, R>(as:C.Type, tx:borrowing Transaction, _ handler:(consuming C) throws -> R) rethrows -> R where C.MDB_cursor_dbtype == Self

	// reading entries in the database
	/// retrieve an entry from the database. if ``Database/Flags/dupSort`` is set and multiple entries exist for the specified key, the first entry will be returned
	///	- parameters:
	///		- key: a pointer to the type that conveys the key to search for.
	///		- as: the value type to return as a conveyance of the value that would be found in the database.
	///		- tx: a pointer to the lmdb transaction that will be used to retrieve the entry.
	/// - throws: a corresponding ``LMDBError.notFound`` if the key does not exist, or other ``LMDBError`` for more obscure circumstances.
	///	- returns: the decoded value type.
	borrowing func loadEntry(key:MDB_db_key_type, as:MDB_db_val_type.Type, tx:borrowing Transaction) throws -> MDB_db_val_type
	/// check if an entry key exists in the database
	/// - parameters:
	/// 	- key: a pointer to the type that conveys the key to search for. this function reserves the right to modify the value pointed to by this pointer. contents of the pointed value should not be handled after this function is called.
	/// 	- tx: a pointer to the lmdb transaction that will be used to check for the entry.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be found.
	/// - returns: true if an entry exists, false if it does not.
	borrowing func containsEntry(key:MDB_db_key_type, tx:borrowing Transaction) throws -> Bool
	/// check if an entry key and value exists in the database
	/// - parameters:
	/// 	- key: a pointer to the type that conveys the key to search for. this function reserves the right to modify the value pointed to by this pointer. contents of the pointed value should not be handled after this function is called.
	/// 	- value: a pointer to the type that conveys the value to search for. this function reserves the right to modify the value pointed to by this pointer. contents of the pointed value should not be handled after this function is called.
	/// 	- tx: a pointer to the lmdb transaction that will be used to check for the entry.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be found.
	/// - returns: true if the entry exists, false if it does not.
	borrowing func containsEntry(key:MDB_db_key_type, value:MDB_db_val_type, tx:borrowing Transaction) throws -> Bool
	
	// writing entries to the database
	/// assign an entry to the database. flags can be used to modify the behavior of the entry assignment as needed
	/// - parameters:
	/// 	- key: a pointer to the type that conveys the key that will be set in the database. this function reserves the right to modify the value pointed to by this pointer. contents of the pointed value should not be handled after this function is called.
	/// 	- value: a pointer to the type that conveys the value that will be set in the database. this function reserves the right to modify the value pointed to by this pointer. contents of the pointed value should not be handled after this function is called.
	/// 	- flags: the flags that will be used when assigning the entry in the database.
	/// 	- tx: a pointer to the lmdb transaction that will be used to set the entry.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be set. the particular set of errors that can be thrown are dependent on the database and environment flags being used, as well as the operation flags.
	borrowing func setEntry(key:MDB_db_key_type, value:MDB_db_val_type, flags:Operation.Flags, tx:borrowing Transaction) throws

	// remove entries from the database.
	/// remove all entries matching a specified key from the database
	/// - parameters:
	/// 	- key: the key that will be removed from the database.
	/// 	- tx: the transaction to use for the entry removal.
	borrowing func deleteEntry(key:MDB_db_key_type, tx:borrowing Transaction) throws

	/// remove a specific key and value pairing from the database
	/// - parameters:
	/// 	- key: the key that will be removed from the database.
	/// 	- value: the value that will be removed from the database.
	/// 	- tx: the transaction to use for the entry removal.
	/// - note: despite this function requiring inout parameters, the passed values are not mutated. they are treated as read-only values.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be removed.
	borrowing func deleteEntry(key:MDB_db_key_type, value:MDB_db_val_type, tx:borrowing Transaction) throws

	/// remove all entries from the database
	/// - parameters:
	/// 	- tx: the transaction to use for the entry removal.
	/// - throws: a corresponding ``LMDBError`` if the entries could not be removed.
	borrowing func deleteAllEntries(tx:borrowing Transaction) throws

	// metadata
	/// returns the statistics for the database
	/// - parameters:
	/// 	- tx: the transaction to use for the statistics retrieval.
	/// - throws: a corresponding ``LMDBError`` if the statistics could not be retrieved.
	borrowing func dbStatistics(tx:borrowing Transaction) throws -> MDB_stat
	/// returns the flags that were used when opening the database
	/// - parameters:
	/// 	- tx: the transaction to use for the flags retrieval.
	/// - throws: a corresponding ``LMDBError`` if the flags could not be retrieved.
	borrowing func dbFlags(tx:borrowing Transaction) throws -> MDB_db_flags
}

extension MDB_db {
	// default entry for all MDB_db implementations where `loadEntry` is called but the value type is not specified. in this case, the value type is assumed to be `MDB_db_val_type`
	public borrowing func loadEntry(key keyVal:borrowing MDB_db_key_type, tx:borrowing Transaction) throws -> MDB_db_val_type {
		return try loadEntry(key:keyVal, as:MDB_db_val_type.self, tx:tx)
	}
}
