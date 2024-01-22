import CLMDB
import RAW

public protocol MDB_db {
	
	var MDB_env_handle:OpaquePointer { get }
	var MDB_db_name:String? { get }
	var MDB_db_handle:MDB_dbi { get }

	init(MDB_env_handle:OpaquePointer, MDB_db_name:String?, MDB_db_flags:Database.Flags, tx:Transaction) throws

	// reading entries in the database
	/// get an entry from the database.
	///	- parameters:
	///		- key: the key that will be searched in the database.
	///		- as: the type to decode from the database.
	///		- tx: the transaction to use for the entry search.
	/// - throws: throws ``LMDBError.notFound`` if the key does not exist, or other errors for more obscure circumstances.
	///	- returns: the decoded value type, if it successfully decoded from the database. if the entry is found but it fails to decode, `nil` is returned.
	func getEntry<K:RAW_accessible, V:RAW_decodable>(key:inout K, as:V.Type, tx:Transaction) throws -> V?
	
	/// search the database for the existence of a given entry.
	func containsEntry<K:RAW_accessible>(key:inout K, tx:Transaction) throws -> Bool

	// writing entries to the database
	func setEntry<K:RAW_accessible, V:RAW_encodable>(key:inout K, value:inout V, tx:Transaction) throws

	// removing entries to the database
	func deleteEntry<K:RAW_accessible>(key:inout K, tx:Transaction) throws
	func deleteEntry<K:RAW_accessible, V:RAW_accessible>(key:inout K, value:inout V, tx:Transaction)
	func deleteAllEntries(tx:Transaction)

	func setEntryCompare(keys:MDB_comparable.MDB_compare_ftype, tx:Transaction) throws
	func setEntryCompare(values:MDB_comparable.MDB_compare_ftype, tx:Transaction) throws
}

extension MDB_db {

	public func getEntry<K:RAW_accessible, V:RAW_decodable>(key:inout K, as:V.Type, tx:Transaction) throws -> V? {
		return V(try key.RAW_access_mutating { ptr in
			var keyVal = MDB_val(ptr)
			var dbValue = MDB_val.nullValue()
			let valueResult = mdb_get(tx.txn_handle, MDB_db_handle, &keyVal, &dbValue)
			guard valueResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:valueResult)
			}
			return dbValue
		})
	}

	public func containsEntry<K:RAW_accessible>(key:inout K, tx:Transaction) throws -> Bool {
		return try key.RAW_access_mutating { ptr in
			var keyVal = MDB_val(ptr)
			var dbValue = MDB_val.nullValue()
			let valueResult = mdb_get(tx.txn_handle, MDB_db_handle, &keyVal, &dbValue)
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

	public func setEntry<K:RAW_accessible, V:RAW_encodable>(key:inout K, value:inout V, flags:Cursor.Operation.Flags, tx:Transaction) throws {
		try key.RAW_access_mutating { ptr in
			var keyVal = MDB_val(ptr)
			var mdbValVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			value.RAW_encode(count:&mdbValVal.mv_size)
			let dbResult = mdb_put(tx.txn_handle, MDB_db_handle, &keyVal, &mdbValVal, flags.union(.reserve).rawValue)
			guard dbResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:dbResult)
			}
			#if DEBUG
			assert(mdbValVal.mv_data != nil)
			#endif
			value.RAW_encode(dest:mdbValVal.mv_data.assumingMemoryBound(to:UInt8.self))
		}
	}
	public func deleteEntry<K:RAW_accessible>(key:inout K, tx:Transaction) throws {
		try key.RAW_access_mutating { ptr in
			var keyVal = MDB_val(ptr)
			let dbResult = mdb_del(tx.txn_handle, MDB_db_handle, &keyVal, nil)
			guard dbResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:dbResult)
			}
		}
	}

	public func deleteEntry<K:RAW_accessible, V:RAW_accessible>(key:inout K, value:inout V, tx:Transaction) throws {
		return try key.RAW_access_mutating({ keyBuff in
			return try value.RAW_access_mutating({ valBuff in
				var keyV = MDB_val(keyBuff)
				var valV = MDB_val(valBuff)
				let dbResult = mdb_del(tx.txn_handle, MDB_db_handle, &keyV, &valV)
				guard dbResult == MDB_SUCCESS else {
					throw LMDBError(returnCode:dbResult)
				}
			})
		})
	}

	public func deleteAllEntries(tx:Transaction) throws {
		let dbResult = mdb_drop(tx.txn_handle, MDB_db_handle, 0)
		guard dbResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:dbResult)
		}
	}

	public func setEntryCompare(keys:MDB_comparable.MDB_compare_ftype, tx:Transaction) throws {
		let dbResult = mdb_set_compare(tx.txn_handle, MDB_db_handle, keys)
		guard dbResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:dbResult)
		}
	}

	public func setEntryCompare(values:MDB_comparable.MDB_compare_ftype, tx:Transaction) throws {
		let dbResult = mdb_set_dupsort(tx.txn_handle, MDB_db_handle, values)
		guard dbResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:dbResult)
		}
	}
}

public struct Database:MDB_db {

    public var MDB_env_handle: OpaquePointer { 
		return env_handle!
	}

    public var MDB_db_name: String? {
		self.name
	}

    public var MDB_db_handle: MDB_dbi {
		db_handle
	}

    public init(MDB_env_handle: OpaquePointer, MDB_db_name: String?, MDB_db_flags: Flags, tx: Transaction) throws {
        try self.init(environment:MDB_env_handle, name:MDB_db_name, flags:MDB_db_flags, tx:tx)
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
	
	/// statistics for the database.
	public typealias Statistics = MDB_stat

	/// the name of the database. When this value is `nil`, this is the only database that exists in the Environment.
	public let name:String?
	/// the `MDB_env` that this Database is associated with.
	public let env_handle:OpaquePointer?
	/// this database as an `MDB_dbi`. Used for calling into LMDB core functions.
	public let db_handle:MDB_dbi
	
	/// Primary initializer. Opens a database.
	/// - Parameters:
	///   - environment: The environment that the database belongs to.
	///   - name: The name of the database to open. if only a single database is needed in the environment, this value may be `nil`.
	///   - flags: Special options for this database.
	///   - tx: The transaction in which this Database is to be opened.
	internal init(environment:OpaquePointer?, name:String?, flags:Flags, tx:Transaction) throws {
		var captureHandle = MDB_dbi()
		let openDatabaseResult = mdb_dbi_open(tx.txn_handle, name, UInt32(flags.rawValue), &captureHandle)
		guard openDatabaseResult == 0 else {
			throw LMDBError(returnCode:openDatabaseResult)
		}
		self.db_handle = captureHandle
		self.env_handle = environment
		self.name = name
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
	
	/// Return the value of an entry with a specified key.
	/// - Parameters:
	///   - type: The value type to return from the database.
	///   - key: The key of the entry that is to be retrieved.
	///   - tx: The transaction that is to be used to retrieve this entry.
	/// - Throws: Will throw ``QuickLMDB/LMDBError/notFound`` if an entry with the given key could not be found.
	/// - Returns: Returns `nil` if the entry exists but could not be deserialized to the specified type. Otherwise, the value of the specified type is returned.
	public func getEntry<K:MDB_encodable, V:MDB_decodable>(type:V.Type, forKey key:K, tx:Transaction) throws -> V? {
		return try key.asMDB_val { keyVal -> V? in
			var dataVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			let valueResult:Int32 = mdb_get(tx.txn_handle, db_handle, &keyVal, &dataVal)
			guard valueResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:valueResult)
			}
			return V(dataVal)
		}
	}
	
    /// Sets an entry with a specified key and value for that key
    /// - Parameters:
    ///   - value: The value (or data) to be stored in the database
    ///   - key: The key to assosiate with the specified value
    ///   - flags: Options for this operation
    ///   - tx: The transaction to use to set the entry into the database. If `nil` is specified, a read-write transaction is opened to set the entry.
    /// - Throws: This function will throw an ``LMDBError`` if the database operation does not return `MDB_SUCCESS`
	public func setEntry<K:MDB_encodable, V:MDB_encodable>(value:V, forKey key:K, flags:Cursor.Operation.Flags = [], tx:Transaction?) throws {
		return try key.asMDB_val { keyVal in
			return try value.asMDB_val { valueVal in
				let valueResult:Int32
				if tx != nil {
					valueResult = mdb_put(tx!.txn_handle, db_handle, &keyVal, &valueVal, flags.rawValue)
				} else {
					valueResult = try Transaction.instantTransaction(environment:env_handle, readOnly:false, parent:nil) { someTrans in
						return mdb_put(someTrans.txn_handle, db_handle, &keyVal, &valueVal, flags.rawValue)
					}
				}
				guard valueResult == MDB_SUCCESS else {
					throw LMDBError(returnCode:valueResult)
				}
			}
		}
	}
    
    /// Checks if the database contains a specified key
    /// - Parameters:
    ///   - key: The key to search for
    ///   - tx: The transaction to use to search for the specified key. If `nil` is specified, a read-only transaction is opened to search for the key.
    /// - Throws: This function will throw an ``LMDBError`` if any value other than `MDB_SUCCESS` or `MDB_NOTFOUND` are returned.
    /// - Returns: True if the database contains the key. False otherwise.
	public func containsEntry<K:MDB_encodable>(key:K, tx:Transaction?) throws -> Bool {
		return try key.asMDB_val { keyVal in
			var dataVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			let valueResult:Int32
			if tx != nil {
				valueResult = mdb_get(tx!.txn_handle, db_handle, &keyVal, &dataVal)
			} else {
				valueResult = try Transaction.instantTransaction(environment:env_handle, readOnly:true, parent:nil) { someTrans -> Int32 in
					return mdb_get(someTrans.txn_handle, db_handle, &keyVal, &dataVal)
				}
			}
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
    
    /// Deletes an entry in the database for a specified key
    /// - Parameters:
    ///   - key: The key to be deleted
    ///   - tx: The transaction to use to delete the entry for the specified key. If `nil` is specified, a read-write transaction is opened to delete the entry.
    /// - Throws: This function will throw an ``LMDBError`` if the database operation does not return `MDB_SUCCESS`
	public func deleteEntry<K:MDB_encodable>(key:K, tx:Transaction?) throws {
		return try key.asMDB_val { keyVal in
			let valueResult:Int32
			if tx != nil {
				valueResult = mdb_del(tx!.txn_handle, db_handle, &keyVal, nil)
			} else {
				valueResult = try Transaction.instantTransaction(environment:env_handle, readOnly:false, parent:nil) { someTrans in
					return mdb_del(someTrans.txn_handle, db_handle, &keyVal, nil)
				}
			}
			guard valueResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:valueResult)
			}
		}
	}
	
    /// Deletes an entry in the database for a specified key and value
    /// - Parameters:
    ///   - key: The key to be deleted
    ///   - value: The value that must assosiate with the key
    ///   - tx: The transaction to use to delete the entry for the specified key and value. If `nil` is specified, a read-write transaction is opened to delete the entry.
    /// - Throws: This function will throw an ``LMDBError`` if the database operation does not return `MDB_SUCCESS`
	public func deleteEntry<K:MDB_encodable, V:MDB_encodable>(key:K, value:V, tx:Transaction?) throws {
		return try key.asMDB_val { keyVal in
			return try value.asMDB_val { valueVal in
				let valueResult:Int32
				if tx != nil {
					valueResult = mdb_del(tx!.txn_handle, db_handle, &keyVal, &valueVal)
				} else {
					valueResult = try Transaction.instantTransaction(environment:env_handle, readOnly:false, parent:nil) { someTrans in
						return mdb_del(someTrans.txn_handle, db_handle, &keyVal, &valueVal)
					}
				}
				guard valueResult == MDB_SUCCESS else {
					throw LMDBError(returnCode:valueResult)
				}

			}
		}
	}
    
    /// Deletes all entries in the database
    /// - Parameter tx: The transaction to use to delete all entries. If `nil` is specified, a read-write transaction is opened to delete all entries.
    /// - Throws: This function will throw an ``LMDBError`` if the database operation does not return `MDB_SUCCESS`
	public func deleteAllEntries(tx:Transaction?) throws {
		let valueResult:Int32
		if tx != nil {
			valueResult = mdb_drop(tx!.txn_handle, db_handle, 0)
		} else {
			valueResult = try Transaction.instantTransaction(environment:env_handle, readOnly:false, parent:nil) { someTrans in
				mdb_drop(someTrans.txn_handle, db_handle, 0)
			}
		}
		guard valueResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:valueResult)
		}
	}
    
    /// Removes this database from its current environment
    /// - Parameter tx: The transaction to use to remove this database. If `nil` is specified, a read-write transaction is opened to delete this database.
    /// - Throws: This function will throw an ``LMDBError`` if the database operation does not return `MDB_SUCCESS`
	public func deleteDatabase(tx:Transaction?) throws {
		let valueResult:Int32
		if tx != nil {
			valueResult = mdb_drop(tx!.txn_handle, db_handle, 1)
		} else {
			valueResult = try Transaction.instantTransaction(environment:env_handle, readOnly:false, parent:nil) { someTrans in
				return mdb_drop(someTrans.txn_handle, db_handle, 1)
			}
		}
		guard valueResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:valueResult)
		}
	}

	/// Assigns a custom key comparison function to a database.
	public func setCompare(tx someTrans:Transaction, _ compareFunction:MDB_comparable.MDB_compare_ftype) throws {
		let result = mdb_set_compare(someTrans.txn_handle, db_handle, compareFunction)
		guard result == MDB_SUCCESS else {
			throw LMDBError(returnCode: result)
		}
	}

	/// Applies a custom value comparison function to a database.
	/// - Database must be configured with ``MDB_DUPSORT`` flag to use this feature.
	public func setDupsortCompare(tx someTrans:Transaction, _ compareFunction:MDB_comparable.MDB_compare_ftype) throws {
		let result = mdb_set_dupsort(someTrans.txn_handle, db_handle, compareFunction)
		guard result == MDB_SUCCESS else {
			throw LMDBError(returnCode: result)
		}
	}
	
	/// Close a database handle. **NOT NEEDED IN MOST USE CASES**
	public func closeDatabase() {
		mdb_dbi_close(env_handle, db_handle);
	}
}
