import CLMDB
import RAW

public protocol MDB_db {
	/// the environment handle primitive that LMDB uses.
	var MDB_env_handle:OpaquePointer { get }
	/// the database name.
	var MDB_db_name:String? { get }
	/// the database handle primitive that LMDB uses.
	var MDB_db_handle:MDB_dbi { get }

	init<E:MDB_env, T:MDB_tx>(MDB_env:E, MDB_db_name:String?, MDB_db_flags:Database.Flags, MDB_tx:T) throws

	// reading entries in the database
	/// get an entry from the database.
	///	- parameters:
	///		- key: the key that will be searched in the database.
	///		- as: the type to decode from the database.
	///		- MDB_tx: the transaction to use for the entry search.
	/// - throws: a corresponding ``LMDBError.notFound`` if the key does not exist, or other errors for more obscure circumstances.
	/// - note: despite this function requiring an inout parameter, the passed value is not mutated. it is treated as a read-only value.
	///	- returns: the decoded value type, if it successfully decoded from the database. if the entry is found but it fails to decode, `nil` is returned.
	func getEntry<K:RAW_accessible, V:RAW_decodable, T:MDB_tx>(key:inout K, as:V.Type, MDB_tx:inout T) throws -> V?
	/// search the database for the existence of a given entry key.
	/// - parameters:
	/// 	- key: the key that will be searched in the database.
	/// 	- MDB_tx: the transaction to use for the entry search.
	/// - note: despite this function requiring an inout parameter, the passed value is not mutated. it is treated as a read-only value.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be searched.
	/// - returns: `true` if the entry exists, `false` if it does not.
	func containsEntry<K:RAW_accessible, T:MDB_tx>(key:inout K, MDB_tx:inout T) throws -> Bool

	// writing entries to the database.
	/// set an entry in the database.
	/// - parameters:
	/// 	- key: the key that will be set in the database.
	/// 	- value: the value that will be set in the database.
	/// 	- flags: the flags that will be used when setting the entry.
	/// 	- MDB_tx: the transaction to use for the entry set.
	/// - note: despite this function requiring inout parameters, the passed values are not mutated. they are treated as read-only values.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be set.
	func setEntry<K:RAW_accessible, V:RAW_encodable, T:MDB_tx>(key:inout K, value:inout V, flags:Cursor.Operation.Flags, MDB_tx:inout T) throws

	// removing entries to the database
	/// remove an entry key (along with its corresponding value) from the database.
	/// - parameters:
	/// 	- key: the key that will be removed from the database.
	/// 	- MDB_tx: the transaction to use for the entry removal.
	/// - note: despite this function requiring an inout parameter, the passed value is not mutated. it is treated as a read-only value.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be removed.
	func deleteEntry<K:RAW_accessible, T:MDB_tx>(key:inout K, MDB_tx:inout T) throws
	/// remove a specific key and value pairing from the database.
	/// - parameters:
	/// 	- key: the key that will be removed from the database.
	/// 	- value: the value that will be removed from the database.
	/// 	- MDB_tx: the transaction to use for the entry removal.
	/// - note: despite this function requiring inout parameters, the passed values are not mutated. they are treated as read-only values.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be removed.
	func deleteEntry<K:RAW_accessible, V:RAW_accessible, T:MDB_tx>(key:inout K, value:inout V, MDB_tx:inout T) throws
	/// remove all entries from the database.
	/// - parameters:
	/// 	- MDB_tx: the transaction to use for the entry removal.
	/// - throws: a corresponding ``LMDBError`` if the entries could not be removed.
	func deleteAllEntries<T:MDB_tx>(MDB_tx:inout T) throws
}

extension MDB_db {

	public func getEntry<K:RAW_accessible, V:RAW_decodable, T:MDB_tx>(key:inout K, as:V.Type, MDB_tx tx:inout T) throws -> V? {
		return V(RAW_decode:try key.RAW_access_mutating { ptr in
			var keyVal = MDB_val(ptr)
			var dbValue = MDB_val.nullValue()
			let valueResult = mdb_get(tx.MDB_tx_handle, MDB_db_handle, &keyVal, &dbValue)
			guard valueResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:valueResult)
			}
			return dbValue
		})
	}

	public func containsEntry<K:RAW_accessible, T:MDB_tx>(key:inout K, MDB_tx tx:inout T) throws -> Bool {
		return try key.RAW_access_mutating { ptr in
			var keyVal = MDB_val(ptr)
			var dbValue = MDB_val.nullValue()
			let valueResult = mdb_get(tx.MDB_tx_handle, MDB_db_handle, &keyVal, &dbValue)
			switch valueResult {
				case MDB_SUCCESS:
					return true
				case MDB_NOTFOUND:
					return false
				default:
					throw LMDBError(returnCode:valueResult)
			}
		}
	}

	public func setEntry<K:RAW_accessible, V:RAW_encodable, T:MDB_tx>(key:inout K, value:inout V, flags:Cursor.Operation.Flags, MDB_tx tx:inout T) throws {
		try key.RAW_access_mutating { ptr in
			var keyVal = MDB_val(ptr)
			var mdbValVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			value.RAW_encode(count:&mdbValVal.mv_size)
			let dbResult = mdb_put(tx.MDB_tx_handle, MDB_db_handle, &keyVal, &mdbValVal, flags.union(.reserve).rawValue)
			guard dbResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:dbResult)
			}
			#if DEBUG
			assert(mdbValVal.mv_data != nil)
			#endif
			value.RAW_encode(dest:mdbValVal.mv_data.assumingMemoryBound(to:UInt8.self))
		}
	}

	public func deleteEntry<K:RAW_accessible, T:MDB_tx>(key:inout K, MDB_tx tx:T) throws {
		try key.RAW_access_mutating { ptr in
			var keyVal = MDB_val(ptr)
			let dbResult = mdb_del(tx.MDB_tx_handle, MDB_db_handle, &keyVal, nil)
			guard dbResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:dbResult)
			}
		}
	}

	public func deleteEntry<K:RAW_accessible, V:RAW_accessible, T:MDB_tx>(key:inout K, value:inout V, MDB_tx tx:inout T) throws {
		return try key.RAW_access_mutating({ keyBuff in
			return try value.RAW_access_mutating({ valBuff in
				var keyV = MDB_val(keyBuff)
				var valV = MDB_val(valBuff)
				let dbResult = mdb_del(tx.MDB_tx_handle, MDB_db_handle, &keyV, &valV)
				guard dbResult == MDB_SUCCESS else {
					throw LMDBError(returnCode:dbResult)
				}
			})
		})
	}

	public func deleteAllEntries<T:MDB_tx>(MDB_tx tx:inout T) throws {
		let dbResult = mdb_drop(tx.MDB_tx_handle, MDB_db_handle, 0)
		guard dbResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:dbResult)
		}
	}

	public func setEntryCompare<T:MDB_tx>(keys:MDB_comparable.MDB_compare_ftype, MDB_tx tx:inout T) throws {
		let dbResult = mdb_set_compare(tx.MDB_tx_handle, MDB_db_handle, keys)
		guard dbResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:dbResult)
		}
	}

	public func setEntryCompare<T:MDB_tx>(values:MDB_comparable.MDB_compare_ftype, MDB_tx tx:inout T) throws {
		let dbResult = mdb_set_dupsort(tx.MDB_tx_handle, MDB_db_handle, values)
		guard dbResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:dbResult)
		}
	}
}

public struct Database:MDB_db {

    public let MDB_env_handle:OpaquePointer
    public let MDB_db_name:String?
    public let MDB_db_handle:MDB_dbi

    public init<E:MDB_env, T:MDB_tx>(MDB_env env:E, MDB_db_name:String?, MDB_db_flags: Flags, MDB_tx tx:T) throws {
        var captureHandle = MDB_dbi()
		let openDatabaseResult = mdb_dbi_open(tx.MDB_tx_handle, MDB_db_name, UInt32(MDB_db_flags.rawValue), &captureHandle)
		guard openDatabaseResult == 0 else {
			throw LMDBError(returnCode:openDatabaseResult)
		}
		self.MDB_db_handle = captureHandle
		self.MDB_env_handle = env.MDB_env_handle
		self.MDB_db_name = MDB_db_name
    }
	
	/// special options for this database. These flags are specified
	public struct Flags:OptionSet {
		public let rawValue:UInt32
		public init(rawValue:UInt32) { self.rawValue = rawValue }

		/// use reverse string keys
		public static let reverseKey = Flags(rawValue:UInt32(MDB_REVERSEKEY))
		
		/// use sorted duplicates
		public static let dupSort = Flags(rawValue:UInt32(MDB_DUPSORT))
		
		/// numeric keys in native byte order. The keys must all be of the same size.
		public static let integerKey = Flags(rawValue:UInt32(MDB_INTEGERKEY))
		
		/// duplicate items have a fixed size
		/// - use with ``dupSort``
		public static let dupFixed = Flags(rawValue:UInt32(MDB_DUPFIXED))
		
		/// duplicate item are integers (``integerKey`` for duplicate items)
		public static let integerDup = Flags(rawValue:UInt32(MDB_INTEGERDUP))
		
		/// use reverse string duplicate keys
		/// - use with ``QuickLMDB/Database``
		public static let reverseDup = Flags(rawValue:UInt32(MDB_REVERSEDUP))
		
		/// create the database if it does not already exist
		public static let create = Flags(rawValue:UInt32(MDB_CREATE))
	}

	/// Create a cursor from this Database.
	public func cursor(tx:Transaction) throws -> Cursor {
		return try Cursor(txn_handle:tx.txn_handle, db:self.db_handle, readOnly:tx.readOnly)
	}
	
	/// Get the statistics for the database..
	/// - Parameter tx: The transaction to use to capture the statistics.
	/// - Returns: Statistics object with info of the database.
	/// - Throws: This function with throw an ``LMDBError`` if the statistics could not be retrieved.
	public func getStatistics(tx:Transaction) throws -> Statistics {
		var statObj = MDB_stat()
		let getStatTry = mdb_stat(tx.txn_handle, db_handle, &statObj)
		guard getStatTry == 0 else {
			throw LMDBError(returnCode:getStatTry)
		}
		return statObj
	}

	/// Get the flags that were used when opening the database.
	/// - Parameter tx: The transaction to use to get the flags for the database. If `nil` is specified, a read-only transaction is opened to retrieve the flags.
	/// - Returns: Current flags assigned to the database object.
	public func getFlags(tx:Transaction) throws -> Flags {
		var captureFlags = UInt32()
		let getFlagsTry = mdb_dbi_flags(tx.txn_handle, db_handle, &captureFlags)
		guard getFlagsTry == 0 else {
			throw LMDBError(returnCode:getFlagsTry)
		}
		return Flags(rawValue:captureFlags)
	}
	
	/// Close a database handle. **NOT NEEDED IN MOST USE CASES**
	public func closeDatabase() {
		mdb_dbi_close(env_handle, db_handle);
	}
}
