import CLMDB

public struct Database {
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
	public struct Statistics {
		public let pageSize:UInt32
		public let depth:UInt32
		public let branch_pages:size_t
		public let leaf_pages:size_t
		public let overflow_pages:size_t
		public let entries:size_t
	}
	
	public let name:String?
	public let env_handle:OpaquePointer?
	public let db_handle:MDB_dbi
	
	//primary initializer
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
	
	public func cursor(tx:Transaction) throws -> Cursor {
		return try Cursor(tx_handle:tx.txn_handle, db:self.db_handle, readOnly:tx.readOnly)
	}
	
	/*
	Metadata related to the database
	*/
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
	
	
	//Functions for managing the entires that are stored in a database
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
	
	public func setEntry<K:MDB_convertible, V:MDB_convertible>(value:V, forKey key:K, flags:Cursor.Operation.Flags? = nil, tx:Transaction?) throws {
		return try key.asMDB_val { keyVal in
			return try value.asMDB_val { valueVal in
				let valueResult:Int32
				if tx != nil {
					valueResult = mdb_put(tx!.txn_handle, db_handle, &keyVal, &valueVal, flags?.rawValue ?? 0)
				} else {
					valueResult = try Transaction.instantTransaction(environment:env_handle, readOnly:false, parent:nil) { someTrans in
						return mdb_put(someTrans.txn_handle, db_handle, &keyVal, &valueVal, flags?.rawValue ?? 0)
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
			let valueResult:Int32
			if tx != nil {
				valueResult = mdb_get(tx!.txn_handle, db_handle, &keyVal, nil)
			} else {
				valueResult = try Transaction.instantTransaction(environment:env_handle, readOnly:true, parent:nil) { someTrans -> Int32 in
					return mdb_get(someTrans.txn_handle, db_handle, &keyVal, nil)
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
}
