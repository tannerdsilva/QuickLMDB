import CLMDB
import SystemPackage

public class Environment:Transactable {
	
	///Flags that can be used to open an environment
	public struct Flags:OptionSet {
		public let rawValue:UInt32
		public init(rawValue:UInt32) { self.rawValue = rawValue }
		
		///Experimental option that opens the memorymap at a fixed address.
		public static let fixedMap = Flags(rawValue:UInt32(MDB_FIXEDMAP))
		
		///Specify that the environment is a file instead of a directory.
		public static let noSubDir = Flags(rawValue:UInt32(MDB_NOSUBDIR))
		
		///Disables the `fsync` call that typically executes after a transaction is committed.
		public static let noSync = Flags(rawValue:UInt32(MDB_NOSYNC))
		
		///Open the environment as readonly.
		public static let readOnly = Flags(rawValue:UInt32(MDB_RDONLY))
		
		///Disables the `fsync` on the metapage that typically executes after a transaction is committed.
		public static let noMetaSync = Flags(rawValue:UInt32(MDB_NOMETASYNC))
		
		///Use a writable memorymap.
		public static let writeMap = Flags(rawValue:UInt32(MDB_WRITEMAP))
		
		///Sync the memorymap to disk asynchronously when used in combination with the ``Environment/Flags/writeMap`` flag.
		public static let mapAsync = Flags(rawValue:UInt32(MDB_MAPASYNC))
		
		///Associate reader locks with their respective ``Transaction`` objects instead of associating them with their current thread.
		public static let noTLS = Flags(rawValue:UInt32(MDB_NOTLS))
		
		///Disable all locking mechanisms for the database. Caller must manage their own locking.
		public static let noLock = Flags(rawValue:UInt32(MDB_NOLOCK))
		
		///Do not readahead (this flag has no effect on Windows).
		public static let noReadAhead = Flags(rawValue:UInt32(MDB_NORDAHEAD))
		
		///Do not initialize malloc'd memory before writing to the datafile.
		public static let noMemoryInit = Flags(rawValue:UInt32(MDB_NOMEMINIT))
	}
	
	///This is an opaque pointer to the underlying `MDB_env` object for this environment.
	/// - This pointer can be used if you want to interop this Swift wrapper with the underlying LMDB library functions.
	public var env_handle:OpaquePointer?
	
	/// Initialize an LMDB environment at the specified path string.
	/// - Parameters:
	///   - path: The path where the environment will be stored.
	///   - flags: Special options for this environment.
	///   - mapSize: Assign the size of the memory map that will be used for this environment. If left unspecified, the LMDB default value will be used, which is "intentionally set low".
	///   - maxReaders: Specify the number of concurrent read transactions that can happen in this environment.
	///   - maxDBs: Specify the number of named databases that can exist in the environment. It is recommended to specify a low to moderate maxumum value, as each named database costs between 7 to 120 words per transaction. It is NOT recommended to specify a huge value for the maximum database count.
	///   - mode: The UNIX permissions to be set on on created files and semaphores. These permissions are not applied to files that already exist on the system.
	public init(path:String, flags:Flags = [], mapSize:size_t? = nil, maxReaders:MDB_dbi = 128, maxDBs:MDB_dbi = 16, mode:FilePermissions = [.ownerReadWriteExecute, .groupRead, .groupExecute]) throws {
		
		//create the environment variable
		var environmentHandle:OpaquePointer? = nil;
		let envStatus = mdb_env_create(&environmentHandle)
		guard envStatus == 0 else {
			throw LMDBError(returnCode:envStatus)
		}
		
		//set the map size
		if mapSize != nil {
			let mdbSetResult = mdb_env_set_mapsize(environmentHandle, mapSize!)
			guard mdbSetResult == 0 else {
				throw LMDBError(returnCode:mdbSetResult)
			}
		}
		
		//set the maximum readers. this must be done between the `mdb_env_create` and `mdb_env_open` calls.
		let setReadersResult = mdb_env_set_maxreaders(environmentHandle, maxReaders);
		guard setReadersResult == 0 else {
			throw LMDBError(returnCode:setReadersResult)
		}
		
		//set maximum db count
		let mdbSetResult = mdb_env_set_maxdbs(environmentHandle, maxDBs)
		guard mdbSetResult == 0 else {
			throw LMDBError(returnCode:mdbSetResult)
		}
		
		//convert the path into a c-compatible string
		try path.withCString { stringBuffer in
			//open the environment with the specified flags and file modes specified
			let openStatus = mdb_env_open(environmentHandle, stringBuffer, UInt32(flags.rawValue), mode.rawValue)
			guard openStatus == 0 else {
				throw LMDBError(returnCode:openStatus)
			}
		}
		
		self.env_handle = environmentHandle
	}
	
	/// Open a database in the environment.
	/// - Parameters:
	///   - databaseName: The name of the database to open. If only a single database is needed in the environment, this value may be `nil`.
	///   - flags: Special options for the database.
	///   - tx: The transaction in which this Database is to be opened. If `nil` is specified, a read/write transaction will be conveniently opened behind the scenes.
	/// - Returns: The newly created Database structure.
	public func openDatabase(named databaseName:String? = nil, flags:Database.Flags = [], tx:Transaction?) throws -> Database {
		if tx != nil {
			return try Database(environment:env_handle, name:databaseName, flags:flags, tx:tx!)
		} else {
			return try Transaction.instantTransaction(environment:env_handle, readOnly:false, parent:nil) { someTrans in
				return try Database(environment:env_handle, name:databaseName, flags:flags, tx:someTrans)
			}
		}
	}
	
	/// Remove a database from the environment.
	/// - Parameters:
	///   - database: The database that is to be removed from the environment.
	///   - tx: The transaction in which to apply this action. If `nil` is specified, a writable transaction is
    /// - Throws: This function will throw an ``LMDBError`` if the environment operation does not return `MDB_SUCCESS`.
	public func deleteDatabase(_ database:Database, tx:Transaction?) throws {
		if tx != nil {
			let result = mdb_drop(env_handle, database.db_handle, 1)
			guard result == MDB_SUCCESS else {
				throw LMDBError(returnCode:result)
			}
		} else {
			try Transaction.instantTransaction(environment:env_handle, readOnly:false, parent:nil) { someTrans in
				let result = mdb_drop(env_handle, database.db_handle, 1)
				guard result == MDB_SUCCESS else {
					throw LMDBError(returnCode:result)
				}
			}
		}
	}
	
    /// Open a new transaction in the environment.
    /// - Parameters:
    ///   - readOnly: If true the transaction is read-only. If false the transaction is read-write.
    ///   - txFunc: The handler transaction.
    /// - Throws: The function will throw if the transaction can't be created.
    /// - Returns: The opened transaction.
	public func transact<R>(readOnly:Bool = true, _ txFunc:(Transaction) throws -> R) throws -> R {
		return try Transaction.instantTransaction(environment:self.env_handle, readOnly:readOnly, parent:nil, txFunc)
	}
	
	///Set the size of the memory map to use for this environment.
	/// - The size should be a multiple of the OS page size.
	/// - Callers MUST explicitly ensure that no transactions are active in the process before calling this function.
	/// - The new size takes effect immediately for the calling process, but the change will not take effect for other processes until the current process commits a new write transaction.
	public func setMapSize(_ newMapSize:size_t) throws {
		let mdbSetResult = mdb_env_set_mapsize(env_handle, newMapSize)
		guard mdbSetResult == 0 else {
			throw LMDBError(returnCode:mdbSetResult)
		}
	}
    
    /// Copy an LMDB environment to a specified path.
    /// - Parameters:
    ///   - path: The path where the environment is to be copied.
    ///   - performCompaction: If true, the operation preforms compation while copying (consumes more CPU and runs slower). If false, the operation does not preform compation.
    /// - Throws: This function will throw an ``LMDBError`` if the environment operation fails.
	public func copyTo(path:String, performCompaction:Bool) throws {
		try path.withCString { pathCString in
			let copyFlags:UInt32 = (performCompaction == true) ? UInt32(MDB_CP_COMPACT) : 0
			let copyResult = mdb_env_copy2(env_handle, pathCString, copyFlags)
			guard copyResult == 0 else {
				throw LMDBError(returnCode:copyResult)
			}
		}
	}
    
    /// Flush the data buffers to disk.
    /// - Parameter force: If true, the operation forces a synchronus flush. If false, an asynchronus flush is preformed.
    /// - Throws: This function will throw an ``LMDBError`` if the environment operation fails.
	public func sync(force:Bool = true) throws {
		let syncStatus = mdb_env_sync(env_handle, (force == true ? 1 : 0))
		guard syncStatus == 0 else {
			throw LMDBError(returnCode:syncStatus)
		}
	}
    
    /// Checks for stale entries in the reader lock table.
    /// - Throws: This function will throw an ``LMDBError`` if the environment operation fails.
    /// - Returns: The number of stale slots that were cleared.
	@discardableResult public func readerCheck() throws -> Int32 {
		var deadCheck:Int32 = 0
		let clearCheck = mdb_reader_check(self.env_handle, &deadCheck)
		guard clearCheck == MDB_SUCCESS else {
			throw LMDBError(returnCode:clearCheck)
		}
		return deadCheck
	}

	deinit {
		//close the environment handle when all references to this instance are released
		mdb_env_close(self.env_handle)
	}
}

