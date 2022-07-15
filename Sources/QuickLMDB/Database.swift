import CLMDB

public struct Database {
	
	///Special options for this database. These flags are specified
	public struct Flags:OptionSet {
		public let rawValue:UInt32
		public init(rawValue:UInt32) { self.rawValue = rawValue }

		public static let reverseKey = Flags(rawValue:UInt32(MDB_REVERSEKEY))
		public static let dupSort = Flags(rawValue:UInt32(MDB_DUPSORT))
		public static let integerKey = Flags(rawValue:UInt32(MDB_INTEGERKEY))
		public static let dupFixed = Flags(rawValue:UInt32(MDB_DUPFIXED))
		public static let integerDup = Flags(rawValue:UInt32(MDB_INTEGERDUP))
		public static let reverseDup = Flags(rawValue:UInt32(MDB_REVERSEDUP))
		public static let create = Flags(rawValue:UInt32(MDB_CREATE))
	}
	
	///Statistics for the database.
	public struct Statistics {
		///Size of the database page. This is currently the same for all databases.
		public let pageSize:UInt32
		///Depth (height) of the B-tree.
		public let depth:UInt32
		///Number of internal (non-leaf) pages.
		public let branch_pages:size_t
		///Number of leaf pages.
		public let leaf_pages:size_t
		///Number of overflow pages.
		public let overflow_pages:size_t
		///Number of data items.
		public let entries:size_t
	}
	
	///The name of the database. When this value is `nil`, this is the only database that exists in the Environment.
	public let name:String?
	///The `MDB_env` that this Database is associated with.
	public let env_handle:OpaquePointer?
	///This database as an `MDB_dbi`. Used for calling into LMDB core functions.
	public let db_handle:MDB_dbi
	
	/// Primary initializer. Opens a database.
	/// - Parameters:
	///   - environment: The environment that the database belongs to..
	///   - name: The name of the database to open. if only a single database is needed in the environment, this value may be `nil`.
	///   - flags: Special options for this database.
	///   - tx: The transaction in which this Database is to be opened.
	internal init(environment:OpaquePointer?, name:String?, flags:Flags, tx:Transaction) throws {
		var captureHandle = MDB_dbi()
		
		if (name != nil) {
			try name!.withCString { namePointer in
				let openDatabaseResult = mdb_dbi_open(tx.txn_handle, namePointer, UInt32(flags.rawValue), &captureHandle)
				guard openDatabaseResult == 0 else {
					throw LMDBError(returnCode:openDatabaseResult)
				}
			}
		} else {
			let openDatabaseResult = mdb_dbi_open(tx.txn_handle, nil, UInt32(flags.rawValue), &captureHandle)
			guard openDatabaseResult == 0 else {
				throw LMDBError(returnCode:openDatabaseResult)
			}
		}
		self.db_handle = captureHandle
		self.env_handle = environment
		self.name = name
	}
	
	///Create a cursor from this Database.
	public func cursor(tx:Transaction) throws -> Cursor {
		return try Cursor(txn_handle:tx.txn_handle, db:self.db_handle, readOnly:tx.readOnly)
	}
	
	/// Get the statistics for the database..
	/// - Parameter tx: The transaction to use to capture the statistics. If `nil` is specified, a read-only transaction is opened to retrieve the statistics.
	/// - Returns: Statistics object with info of the database.
	/// - Throws: This function with throw an ``LMDBError`` if the statistics could not be retrieved.
	public func getStatistics(tx:Transaction?) throws -> Statistics {
		var statObj = MDB_stat()
		if tx != nil {
			let getStatTry = mdb_stat(tx!.txn_handle, db_handle, &statObj)
			guard getStatTry == 0 else {
				throw LMDBError(returnCode:getStatTry)
			}
			return Statistics(pageSize:statObj.ms_psize, depth:statObj.ms_depth, branch_pages:statObj.ms_branch_pages, leaf_pages:statObj.ms_leaf_pages, overflow_pages:statObj.ms_overflow_pages, entries:statObj.ms_entries)
		} else {
			return try Transaction.instantTransaction(environment:env_handle, readOnly:true, parent:nil) { someTransaction in
				var statObj = MDB_stat()
				let getStatTry = mdb_stat(someTransaction.txn_handle, db_handle, &statObj)
				guard getStatTry == 0 else {
					throw LMDBError(returnCode:getStatTry)
				}
				return Statistics(pageSize:statObj.ms_psize, depth:statObj.ms_depth, branch_pages:statObj.ms_branch_pages, leaf_pages:statObj.ms_leaf_pages, overflow_pages:statObj.ms_overflow_pages, entries:statObj.ms_entries)
			}
		}
	}

	/// Get the flags that were used when opening the database.
	/// - Parameter tx: The transaction to use to get the flags for the database. If `nil` is specified, a read-only transaction is opened to retrieve the flags.
	/// - Returns: Current flags assigned to the database object.
	public func getFlags(tx:Transaction?) throws -> Flags {
		var captureFlags = UInt32()
		if tx != nil {
			mdb_dbi_flags(tx!.txn_handle, db_handle, &captureFlags)
			return Flags(rawValue:captureFlags)
		} else {
			return try Transaction.instantTransaction(environment:env_handle, readOnly:true, parent:nil) { someTransaction in
				mdb_dbi_flags(someTransaction.txn_handle, db_handle, &captureFlags)
				return Flags(rawValue:captureFlags)
			}
		}
	}
	
	
	
	/// Return the value of an entry with a specified key.
	/// - Parameters:
	///   - type: The value type to return from the database.
	///   - key: The key of the entry that is to be retrieved.
	///   - tx: The transaction that is to be used to retrieve this entry.
	/// - Throws: Will throw ``LMDBError.notFound`` if an entry with the given key could not be found.
	/// - Returns: Returns `nil` if the entry exists but could not be deserialized to the specified type. Otherwise, the value of the specified type is returned.
	public func getEntry<K:MDB_convertible, V:MDB_convertible>(type:V.Type, forKey key:K, tx:Transaction?) throws -> V? {
		return try key.asMDB_val { keyVal -> V? in
			var dataVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			let valueResult:Int32
			if tx != nil {
				valueResult = mdb_get(tx!.txn_handle, db_handle, &keyVal, &dataVal)
			} else {
				valueResult = try Transaction.instantTransaction(environment:env_handle, readOnly:true, parent:nil) { someTrans in
					return mdb_get(someTrans.txn_handle, db_handle, &keyVal, &dataVal)
				}
			}
			guard valueResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:valueResult)
			}
			return V(dataVal)
		}
	}
	
	public func setEntry<K:MDB_convertible, V:MDB_convertible>(value:V, forKey key:K, flags:Cursor.Operation.Flags = [], tx:Transaction?) throws {
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
	
	public func containsEntry<K:MDB_convertible>(key:K, tx:Transaction?) throws -> Bool {
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
	
	public func deleteEntry<K:MDB_convertible>(key:K, tx:Transaction?) throws {
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
	
	public func deleteEntry<K:MDB_convertible, V:MDB_convertible>(key:K, value:V, tx:Transaction?) throws {
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
	
	public func removeDatabase(tx:Transaction?) throws {
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
	
	/// Close a database handle. **NOT NEEDED IN MOST USE CASES**
	public func closeDatabase() {
		mdb_dbi_close(env_handle, db_handle);
	}
}
