import CLMDB
import RAW

public struct Database:Sendable, MDB_db_basic {

    public typealias MDB_db_cursor_type = Cursor
	
	public typealias MDB_db_key_type = MDB_val
	public typealias MDB_db_val_ptrtype = MDB_val

	/// the environment handle primitive that this database instance is based on
	private let _db_env:Environment
	public borrowing func dbEnvironment() -> Environment {
		return _db_env
	}
	
	/// the LMDB database name of this instance
    private let _db_name:String?
    public borrowing func dbName() -> String? {
    	return _db_name
    }
	/// the database handle primitive for this instance
    private let _db_handle:MDB_dbi
    public borrowing func dbHandle() -> MDB_dbi {
    	return _db_handle
    }
	
	/// initialize a new database instance from the specified environment.
	/// - parameters:
	/// 	- env: a pointer to the environment that the database will be based on.
	/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
	/// 	- flags: the flags that will be used when opening the database.
	///		- tx: a pointer to the transaction that will be used to open the database.
	@available(*, noasync)
    public init(env:borrowing Environment, name name_in:String?, flags:MDB_db_flags, tx:borrowing Transaction<Write>) throws(LMDBError) {
		self._db_env = copy env
		self._db_name = name_in
		var dbHandle = MDB_dbi()
		let openResult = mdb_dbi_open(tx.txHandle(), name_in, flags.rawValue, &dbHandle)
		guard openResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openResult)
		}
		self._db_handle = dbHandle
    }
}

extension Database {
	
	@MDB_db_strict_impl()
	public struct DupSort<K:MDB_comparable & MDB_convertible, V:MDB_comparable & MDB_convertible>:Sendable, MDB_db_dupsort {
		public typealias MDB_db_key_type = K
		public typealias MDB_db_val_type = V

		public typealias MDB_db_cursor_type = Cursor.DupSort<Self>

		/// the environment handle primitive that this database instance is based on
		private let _db_env:Environment
		public borrowing func dbEnvironment() -> Environment {
			return _db_env
		}
		/// the LMDB database name of this instance
		private let _db_name:String?
		@available(*, noasync)
		public borrowing func dbName() -> String? {
			return _db_name
		}
		/// the database handle primitive for this instance
		private let _db_handle:MDB_dbi
		@available(*, noasync)
		public borrowing func dbHandle() -> MDB_dbi {
			return _db_handle
		}

		/// initialize a new database instance from the specified environment.
		/// - parameters:
		/// 	- env: a pointer to the environment that the database will be based on.
		/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
		/// 	- flags: the flags that will be used when opening the database.
		///		- tx: a pointer to the transaction that will be used to open the database.
		@available(*, noasync)
		public init(env:borrowing Environment, name:String?, flags:consuming MDB_db_flags, tx:borrowing Transaction<Write>) throws(LMDBError) {
			flags.update(with:.dupSort)
			
			self._db_env = copy env
			self._db_name = name
			var dbHandle = MDB_dbi()
			let openResult = mdb_dbi_open(tx.txHandle(), name, flags.rawValue, &dbHandle)
			guard openResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:openResult)
			}
			self._db_handle = dbHandle
			self.assignCompareKey(MDB_db_key_type.MDB_compare_f, tx:tx)
			self.assignCompareVal(MDB_db_val_type.MDB_compare_f, tx:tx)
		}
	}

	@MDB_db_strict_impl()
	public struct DupFixed<KeyType:MDB_convertible & RAW_staticbuff & MDB_comparable, ValueType:MDB_convertible & RAW_staticbuff & MDB_comparable>:Sendable, MDB_db_dupfixed {
		/// the key type that the database uses.
		/// 	- must be MDB_comparable
		/// 	- must be static length
		public typealias MDB_db_key_type = KeyType
		
		/// the value type that the database uses.
		/// 	- must be MDB_comparable
		/// 	- must be static length
		public typealias MDB_db_val_type = ValueType

		/// the cursor type that this database operates with.
		public typealias MDB_db_cursor_type = Cursor.DupFixed<Self>

		// the environment handle primitive that this database instance is based on
		private let _db_env:Environment
		public borrowing func dbEnvironment() -> Environment {
			return _db_env
		}
		// the LMDB database name of this instance
		private let _db_name:String?
		public borrowing func dbName() -> String? {
			return _db_name
		}
		/// the database handle primitive for this instance
		private let _db_handle:MDB_dbi
		public borrowing func dbHandle() -> MDB_dbi {
			return _db_handle
		}
		
		/// initialize a new database instance from the specified environment.
		/// - parameters:
		/// 	- env: borrows an environment that the database will be based on.
		/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
		/// 	- flags: the flags that will be used when opening the database.
		///		- tx: borrows a transaction that will be used to complete the database initialization.
		@available(*, noasync)
		public init(env:borrowing Environment, name:String?, flags:consuming MDB_db_flags, tx:borrowing Transaction<Write>) throws(LMDBError) {
			// configure the correct flags before consuming the variable
			flags.update(with:.dupFixed)
			flags.update(with:.dupSort)
						
			self._db_env = copy env
			self._db_name = name
			var dbHandle = MDB_dbi()
			let openResult = mdb_dbi_open(tx.txHandle(), name, flags.rawValue, &dbHandle)
			guard openResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:openResult)
			}
			self._db_handle = dbHandle
			self.assignCompareKey(MDB_db_key_type.MDB_compare_f, tx:tx)
			self.assignCompareVal(MDB_db_val_type.MDB_compare_f, tx:tx)
		}
	}

	@MDB_db_strict_impl()
	public struct Strict<K:MDB_convertible & MDB_comparable, V:MDB_convertible>:Sendable, MDB_db_strict {
		public typealias MDB_db_key_type = K
		public typealias MDB_db_val_type = V

		public typealias MDB_db_cursor_type = Cursor.Strict<Self>

		// storage for the environment handle primitive that this database instance is based on
		private let _db_env:Environment
		public borrowing func dbEnvironment() -> Environment {
			return _db_env
		}
		
		// storage for the LMDB database name of this instance
		private let _db_name:String?
		
		/// returns the database name
		public borrowing func dbName() -> String? {
			return _db_name
		}
		
		// the database handle primitive for this instance
		private let _db_handle:MDB_dbi
		
		/// returns the database handle primitive that LMDB uses to represent this database
		public borrowing func dbHandle() -> MDB_dbi {
			return _db_handle
		}
	
		/// initialize a new database instance from the specified environment.
		/// - parameters:
		/// 	- env: a pointer to the environment that the database will be based on.
		/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
		/// 	- flags: the flags that will be used when opening the database.
		///		- tx: a pointer to the transaction that will be used to open the database.
		@available(*, noasync)
		public init(env:borrowing Environment, name:String?, flags:consuming MDB_db_flags, tx:borrowing Transaction<Write>) throws(LMDBError) {
			
			self._db_env = copy env
			self._db_name = name
			var dbHandle = MDB_dbi()
			let openResult = mdb_dbi_open(tx.txHandle(), name, flags.rawValue, &dbHandle)
			guard openResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:openResult)
			}
			self._db_handle = dbHandle
			self.assignCompareKey(MDB_db_key_type.MDB_compare_f, tx:tx)
		}
	}
}