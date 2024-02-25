import CLMDB

#if QUICKLMDB_MACROLOG
import Logging
#endif

public struct Database:MDB_db {
	
	public typealias MDB_db_key_type = MDB_val
	public typealias MDB_db_val_ptrtype = MDB_val

	/// the environment handle primitive that this database instance is based on
	public let env:MDB_env
	/// the LMDB database name of this instance
    public let name:String?
	/// the database handle primitive for this instance
    public let handle:MDB_dbi

	#if QUICKLMDB_MACROLOG
	/// the public logging facility that this database will use for debugging and auditing
	public let logger:Logger?
	
	/// initialize a new database instance from the specified environment.
	/// - parameters:
	/// 	- env: a pointer to the environment that the database will be based on.
	/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
	/// 	- flags: the flags that will be used when opening the database.
	///		- tx: a pointer to the transaction that will be used to open the database.
    public init<E, T>(env:borrowing E, name name_in:String?, flags:MDB_db_flags, tx:borrowing T, logger:Logger? = nil) throws where E:MDB_env, T:MDB_tx {
		var mutateLogger = logger
		mutateLogger?[metadataKey:"type"] = "Database.Strict<\(String(describing:K.self)), \(String(describing:V.self))>"
		self.logger = logger
		self.env = copy env
		self.name = name_in
		self.handle = MDB_dbi()
		let openResult = mdb_dbi_open(tx.txHandle, name_in, flags.rawValue, &dbHandle)
		guard openResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openResult)
		}
    }
	#else
	/// initialize a new database instance from the specified environment.
	/// - parameters:
	/// 	- env: a pointer to the environment that the database will be based on.
	/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
	/// 	- flags: the flags that will be used when opening the database.
	///		- tx: a pointer to the transaction that will be used to open the database.
	public init<E:MDB_env, T:MDB_tx>(env:borrowing E, name name_in:String?, flags:MDB_db_flags, tx:borrowing T) throws {
		self.env = copy env
		self.name = name_in
		self.handle = MDB_dbi()
		let openResult = mdb_dbi_open(tx.handle, name, flags.rawValue, &handle)
		guard openResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openResult)
		}
	}
	#endif
}

extension Database {
	public struct Strict<K:MDB_convertible, V:MDB_convertible>:MDB_db {

		public typealias MDB_db_key_type = K
		public typealias MDB_db_val_type = V

		/// the environment handle primitive that this database instance is based on
		public let env:MDB_env
		/// the LMDB database name of this instance
		public let name:String?
		/// the database handle primitive for this instance
		public let handle:MDB_dbi

		#if QUICKLMDB_MACROLOG
		/// the public logging facility that this database will use for debugging and auditing
		public let logger:Logger?
		
		/// initialize a new database instance from the specified environment.
		/// - parameters:
		/// 	- env: a pointer to the environment that the database will be based on.
		/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
		/// 	- flags: the flags that will be used when opening the database.
		///		- tx: a pointer to the transaction that will be used to open the database.
		public init<E, T>(env:borrowing E, name:String?, flags:MDB_db_flags, tx:borrowing T, logger:Logger? = nil) throws where E:MDB_env, T:MDB_tx {
			var mutateLogger = logger
			mutateLogger?[metadataKey:"type"] = "Database.Strict<\(String(describing:K.self)), \(String(describing:V.self))>"
			self.env = copy env
			self.dbName = copy name
			var dbHandle = MDB_dbi()
			mutateLogger?.trace("initializing...", metadata:["mdb_db_name":"\(String(describing:name))", "mdb_db_flags":"\(String(describing:flags))", "mdb_tx_id":"\(tx.pointee)"])
			let openResult = mdb_dbi_open(tx.txHandle, name, flags.rawValue, &dbHandle)
			guard openResult == MDB_SUCCESS else {
				mutateLogger?.error("initialization failure", metadata:["mdb_db_name":"\(String(describing:name))", "mdb_db_flags":"\(String(describing:flags))", "mdb_tx_id":"\(tx.pointee)", "mdb_return_code":"\(openResult)"])
				throw LMDBError(returnCode:openResult)
			}
			mutateLogger[metadataKey: "mdb_db_iid"] = "\(dbHandle.rawValue)"
			mutateLogger?.debug("configuring...")
			logger = mutateLogger
			handle = dbHandle
			
		}
		#else
		public init<E, T>(env:borrowing E, name:String?, flags:MDB_db_flags, tx:borrowing T) throws where E:MDB_env, T:MDB_tx {
			self.env = copy env
			self.name = name
			var handle = MDB_dbi()
			let openResult = mdb_dbi_open(tx.h, name, flags.rawValue, &handle)
			guard openResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:openResult)
			}
			self.handle = handle
		}
		#endif
	}
}