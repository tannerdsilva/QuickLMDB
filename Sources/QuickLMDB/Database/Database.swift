import CLMDB

#if QUICKLMDB_MACROLOG
import Logging
#endif

public struct Database:MDB_db {
	
	public typealias MDB_db_key_ptrtype = UnsafeMutablePointer<MDB_val>
	public typealias MDB_db_val_ptrtype = UnsafeMutablePointer<MDB_val>

	/// the environment handle primitive that this database instance is based on
	public private(set) var envHandle:OpaquePointer
	/// the LMDB database name of this instance
    public private(set) var dbName:String?
	/// the database handle primitive for this instance
    public private(set) var dbHandle:MDB_dbi

	#if QUICKLMDB_MACROLOG
	/// the public logging facility that this database will use for debugging and auditing
	public private(set) var logger:Logger?
	
	/// initialize a new database instance from the specified environment.
	/// - parameters:
	/// 	- env: a pointer to the environment that the database will be based on.
	/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
	/// 	- flags: the flags that will be used when opening the database.
	///		- tx: a pointer to the transaction that will be used to open the database.
    public init<E, T>(env:UnsafePointer<E>, name:String?, flags:MDB_db_flags, tx:UnsafePointer<T>, logger:Logger? = nil) throws where E:MDB_env, T:MDB_tx {
		logger = logger
		envHandle = env.pointer(to:\E.envHandle)!.pointee
		dbName = name
		dbHandle = MDB_dbi()
		let openResult = mdb_dbi_open(tx.pointer(to:\T.txHandle)!.pointee, name, flags.rawValue, &dbHandle)
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
	public init<E:MDB_env, T:MDB_tx>(env:UnsafePointer<E>, name:String?, flags:MDB_db_flags, tx:UnsafePointer<T>) throws {
		envHandle = env.pointer(to:\E.envHandle)!.pointee
		dbName = name
		dbHandle = MDB_dbi()
		let openResult = mdb_dbi_open(tx.pointer(to:\T.txHandle)!.pointee, name, flags.rawValue, &dbHandle)
		guard openResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openResult)
		}
	}
	#endif
}

extension Database {
	public struct Strict<K:MDB_convertible, V:MDB_convertible>:MDB_db {
		public typealias MDB_db_key_type = K
		public typealias MDB_db_key_ptrtype = UnsafePointer<MDB_db_key_type>
		public typealias MDB_db_val_type = V
		public typealias MDB_db_val_ptrtype = UnsafePointer<MDB_db_val_type>

		/// the environment handle primitive that this database instance is based on
		public private(set) var envHandle:OpaquePointer
		/// the LMDB database name of this instance
		public private(set) var dbName:String?
		/// the database handle primitive for this instance
		public private(set) var dbHandle:MDB_dbi

		#if QUICKLMDB_MACROLOG
		/// the public logging facility that this database will use for debugging and auditing
		public private(set) var logger:Logger?
		
		/// initialize a new database instance from the specified environment.
		/// - parameters:
		/// 	- env: a pointer to the environment that the database will be based on.
		/// 	- name: the name of the database. you may pass `nil` for this argument if you plan on storing only one database in the environment.
		/// 	- flags: the flags that will be used when opening the database.
		///		- tx: a pointer to the transaction that will be used to open the database.
		public init<E, T>(env:UnsafePointer<E>, name:String?, flags:MDB_db_flags, tx:UnsafePointer<T>, logger:Logger? = nil) throws where E:MDB_env, T:MDB_tx {
			var mutateLogger = logger
			mutateLogger?[metadataKey:"type"] = "Database.Strict<\(String(describing:K.self)), \(String(describing:V.self))>"
			envHandle = env.pointer(to:\E.envHandle)!.pointee
			dbName = name
			dbHandle = MDB_dbi()
			mutateLogger?.trace("initializing...", metadata:["mdb_db_name":"\(String(describing:name))", "mdb_db_flags":"\(String(describing:flags))", "mdb_tx_id":"\(tx.pointee)"])
			let openResult = mdb_dbi_open(tx.pointer(to:\T.txHandle)!.pointee, name, flags.rawValue, &dbHandle)
			guard openResult == MDB_SUCCESS else {
				mutateLogger?.error("initialization failure", metadata:["mdb_db_name":"\(String(describing:name))", "mdb_db_flags":"\(String(describing:flags))", "mdb_tx_id":"\(tx.pointee)", "mdb_return_code":"\(openResult)"])
				throw LMDBError(returnCode:openResult)
			}
			mutateLogger[metadataKey: "mdb_db_iid"] = "\(dbHandle.rawValue)"
			mutateLogger?.debug("configuring...")
			logger = mutateLogger
			
		}
		#else
		public init<E, T>(env:UnsafePointer<E>, name:String?, flags:MDB_db_flags, tx:UnsafePointer<T>) throws where E:MDB_env, T:MDB_tx {
			envHandle = env.pointer(to:\E.envHandle)!.pointee
			dbName = name
			dbHandle = MDB_dbi()
			let openResult = mdb_dbi_open(tx.pointer(to:\T.txHandle)!.pointee, name, flags.rawValue, &dbHandle)
			guard openResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:openResult)
			}
		}
		#endif
	}
}