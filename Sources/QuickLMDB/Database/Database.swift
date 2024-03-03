import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

public struct Database:Sendable, MDB_db_basic {

    public typealias MDB_db_cursor_type = Cursor
	
	public typealias MDB_db_key_type = MDB_val
	public typealias MDB_db_val_ptrtype = MDB_val

	/// the environment handle primitive that this database instance is based on
	private let _db_env:Environment
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

	#if QUICKLMDB_SHOULDLOG
	/// the public logging facility that this database will use for debugging and auditing
	private let _logger:Logger?
	public borrowing func logger() -> Logger? {
		return _logger
	}

	/// initialize a new database instance from the specified environment.
	/// - parameters:
	/// 	- env: a pointer to the environment that the database will be based on.
	/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
	/// 	- flags: the flags that will be used when opening the database.
	///		- tx: a pointer to the transaction that will be used to open the database.
    public init(env:borrowing Environment, name name_in:String?, flags:MDB_db_flags, tx:borrowing Transaction, logger:Logger? = nil) throws {
		var mutateLogger = logger
		mutateLogger?[metadataKey:"type"] = "Database.Strict<\(String(describing:MDB_db_key_type.self)), \(String(describing:MDB_db_val_ptrtype.self))>"
		self._logger = mutateLogger
		self._db_env = copy env
		self._db_name = name_in
		var dbHandle = MDB_dbi()
		let openResult = mdb_dbi_open(tx.txHandle(), name_in, flags.rawValue, &dbHandle)
		guard openResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openResult)
		}
		self._db_handle = dbHandle
    }
	#else
	/// initialize a new database instance from the specified environment.
	/// - parameters:
	/// 	- env: a pointer to the environment that the database will be based on.
	/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
	/// 	- flags: the flags that will be used when opening the database.
	///		- tx: a pointer to the transaction that will be used to open the database.
	public init(env:borrowing Environment, name name_in:String?, flags:MDB_db_flags, tx:borrowing Transaction) throws {
		self._db_env = copy env
		self._db_name = name_in
		var dbHandle = MDB_dbi()
		let openResult = mdb_dbi_open(tx.txHandle(), name_in, flags.rawValue, &dbHandle)
		guard openResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openResult)
		}
		self._db_handle = dbHandle
	}
	#endif
}

extension Database {
	public struct DupSort<K:MDB_comparable & MDB_convertible, V:MDB_comparable & MDB_convertible>:MDB_db_dupsort {
		public typealias MDB_db_key_type = K
		public typealias MDB_db_val_type = V

		public typealias MDB_db_cursor_type = Cursor.DupSort<Self>

		/// the environment handle primitive that this database instance is based on
		private let _db_env:Environment
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

		#if QUICKLMDB_SHOULDLOG
		/// the public logging facility that this database will use for debugging and auditing
		private let _logger:Logger?
		public borrowing func logger() -> Logger? {
			return _logger
		}
		
		/// initialize a new database instance from the specified environment.
		/// - parameters:
		/// 	- env: a pointer to the environment that the database will be based on.
		/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
		/// 	- flags: the flags that will be used when opening the database.
		///		- tx: a pointer to the transaction that will be used to open the database.
		public init(env:borrowing Environment, name:String?, flags:consuming MDB_db_flags, tx:borrowing Transaction, logger:Logger? = nil) throws {
			flags.update(with:.dupSort)
			var mutateLogger = logger
			mutateLogger?[metadataKey:"type"] = "Database.Strict<\(String(describing:K.self)), \(String(describing:V.self))>"
			self._db_env = copy env
			self._db_name = name
			var dbHandle = MDB_dbi()
			let openResult = mdb_dbi_open(tx.txHandle(), name, flags.rawValue, &dbHandle)
			guard openResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:openResult)
			}
			self._db_handle = dbHandle
			self._logger = mutateLogger
			MDB_db_assign_compare_key_f(db:self, type:MDB_db_key_type.self, tx:tx)
			MDB_db_assign_compare_val_f(db:self, type:MDB_db_val_type.self, tx:tx)
		}
		#else
		public init(env:borrowing Environment, name:String?, flags:consuming MDB_db_flags, tx:borrowing Transaction) throws {
			flags.update(with:.dupSort)
			self._db_env = copy env
			self._db_name = name
			var handle = MDB_dbi()
			let openResult = mdb_dbi_open(tx.txHandle(), name, flags.rawValue, &handle)
			guard openResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:openResult)
			}
			self._db_handle = handle
			MDB_db_assign_compare_key_f(db:self, type:MDB_db_key_type.self, tx:tx)
			MDB_db_assign_compare_val_f(db:self, type:MDB_db_val_type.self, tx:tx)
		}
		#endif
	}

	public struct DupFixed<K:RAW_staticbuff & MDB_comparable, V:RAW_staticbuff & MDB_comparable>:Sendable, MDB_db_dupfixed {
		public typealias MDB_db_key_type = K
		public typealias MDB_db_val_type = V

		public typealias MDB_db_cursor_type = Cursor.DupFixed<Self>

		/// the environment handle primitive that this database instance is based on
		private let _db_env:Environment
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

		#if QUICKLMDB_SHOULDLOG
		/// the public logging facility that this database will use for debugging and auditing
		private let _logger:Logger?
		public borrowing func logger() -> Logger? {
			return _logger
		}
		
		/// initialize a new database instance from the specified environment.
		/// - parameters:
		/// 	- env: a pointer to the environment that the database will be based on.
		/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
		/// 	- flags: the flags that will be used when opening the database.
		///		- tx: a pointer to the transaction that will be used to open the database.
		public init(env:borrowing Environment, name:String?, flags:consuming MDB_db_flags, tx:borrowing Transaction, logger:Logger? = nil) throws {
			flags.update(with:.dupFixed)
			flags.update(with:.dupSort)
			var mutateLogger = logger
			mutateLogger?[metadataKey:"type"] = "Database.Strict<\(String(describing:K.self)), \(String(describing:V.self))>"
			self._db_env = copy env
			self._db_name = name
			var dbHandle = MDB_dbi()
			let openResult = mdb_dbi_open(tx.txHandle(), name, flags.rawValue, &dbHandle)
			guard openResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:openResult)
			}
			self._db_handle = dbHandle
			self._logger = mutateLogger
			MDB_db_assign_compare_key_f(db:self, type:MDB_db_key_type.self, tx:tx)
			MDB_db_assign_compare_val_f(db:self, type:MDB_db_val_type.self, tx:tx)
		}
		#else
		public init(env:borrowing Environment, name:String?, flags:consuming MDB_db_flags, tx:borrowing Transaction) throws {
			flags.update(with:.dupFixed)
			flags.update(with:.dupSort)
			self._db_env = copy env
			self._db_name = name
			var handle = MDB_dbi()
			let openResult = mdb_dbi_open(tx.txHandle(), name, flags.rawValue, &handle)
			guard openResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:openResult)
			}
			self._db_handle = handle
			MDB_db_assign_compare_key_f(db:self, type:MDB_db_key_type.self, tx:tx)
			MDB_db_assign_compare_val_f(db:self, type:MDB_db_val_type.self, tx:tx)
		}
		#endif
	}

	public struct Strict<K:MDB_convertible & MDB_comparable, V:MDB_convertible>:Sendable, MDB_db_strict {
		public typealias MDB_db_key_type = K
		public typealias MDB_db_val_type = V

		public typealias MDB_db_cursor_type = Cursor.Strict<Self>

		/// the environment handle primitive that this database instance is based on
		private let _db_env:Environment
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

		#if QUICKLMDB_SHOULDLOG
		/// the public logging facility that this database will use for debugging and auditing
		private let _logger:Logger?
		public borrowing func logger() -> Logger? {
			return _logger
		}
		
		public borrowing func dbHandle() -> Logger? {
			return _logger
		}
		/// initialize a new database instance from the specified environment.
		/// - parameters:
		/// 	- env: a pointer to the environment that the database will be based on.
		/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
		/// 	- flags: the flags that will be used when opening the database.
		///		- tx: a pointer to the transaction that will be used to open the database.
		public init(env:borrowing Environment, name:String?, flags:borrowing MDB_db_flags, tx:borrowing Transaction, logger:Logger? = nil) throws {
			var mutateLogger = logger
			mutateLogger?[metadataKey:"type"] = "Database.Strict<\(String(describing:K.self)), \(String(describing:V.self))>"
			self._db_env = copy env
			self._db_name = name
			var dbHandle = MDB_dbi()
			mutateLogger?.trace("initializing...", metadata:["mdb_db_name":"\(String(describing:name))", "mdb_db_flags":"\(String(describing:flags))", "tx_id":"\(tx.txHandle().hashValue)"])
			let openResult = mdb_dbi_open(tx.txHandle(), name, flags.rawValue, &dbHandle)
			guard openResult == MDB_SUCCESS else {
				mutateLogger?.error("initialization failure", metadata:["mdb_db_name":"\(String(describing:name))", "mdb_db_flags":"\(String(describing:flags))", "tx_id":"\(tx.txHandle().hashValue)", "mdb_return_code":"\(openResult)"])
				throw LMDBError(returnCode:openResult)
			}
			mutateLogger?[metadataKey: "mdb_db_iid"] = "\(dbHandle.hashValue)"
			mutateLogger?.debug("configuring...")
			self._logger = mutateLogger
			self._db_handle = dbHandle
			MDB_db_assign_compare_key_f(db:self, type:MDB_db_key_type.self, tx:tx)
		}
		#else
		public init(env:borrowing Environment, name:String?, flags:borrowing MDB_db_flags, tx:borrowing Transaction) throws {
			self._db_env = copy env
			self._db_name = name
			var handle = MDB_dbi()
			let openResult = mdb_dbi_open(tx.txHandle(), name, flags.rawValue, &handle)
			guard openResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:openResult)
			}
			self._db_handle = handle
			MDB_db_assign_compare_key_f(db:self, type:MDB_db_key_type.self, tx:tx)
		}
		#endif
	}
}