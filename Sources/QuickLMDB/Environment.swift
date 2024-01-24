import CLMDB
import SystemPackage

public protocol MDB_env {

	/// the type of transaction that this environment uses for transactions.
	associatedtype MDB_tx_type:MDB_tx

	/// the environment handle primitive that LMDB uses.
	var MDB_env_handle:OpaquePointer { get }
	/// the environment flags that was used to create the environment.
	var MDB_env_flags:Environment.Flags { get }

	/// create a new environment given the specified path and flags.
	init(path:String, flags:Environment.Flags, mapSize:size_t?, maxReaders:MDB_dbi, maxDBs:MDB_dbi, mode:FilePermissions) throws
}

public final class Environment:MDB_env {
    public typealias MDB_tx_type = Transaction

    public init(path: String, flags: Flags, mapSize:size_t?, maxReaders:MDB_dbi, maxDBs:MDB_dbi, mode:SystemPackage.FilePermissions) throws {
	
		// create the environment variable
		var environmentHandle:OpaquePointer? = nil;
		let envStatus = mdb_env_create(&environmentHandle)
		guard envStatus == 0 else {
			throw LMDBError(returnCode:envStatus)
		}
		
		// set the map size
		if mapSize != nil {
			let mdbSetResult = mdb_env_set_mapsize(environmentHandle, mapSize!)
			guard mdbSetResult == 0 else {
				throw LMDBError(returnCode:mdbSetResult)
			}
		}
		
		// set the maximum readers. this must be done between the `mdb_env_create` and `mdb_env_open` calls.
		let setReadersResult = mdb_env_set_maxreaders(environmentHandle, maxReaders)
		guard setReadersResult == 0 else {
			throw LMDBError(returnCode:setReadersResult)
		}
		
		// set maximum db count
		let mdbSetResult = mdb_env_set_maxdbs(environmentHandle, maxDBs)
		guard mdbSetResult == 0 else {
			throw LMDBError(returnCode:mdbSetResult)
		}
		
		// open the environment with the specified flags and file modes specified
		let openStatus = mdb_env_open(environmentHandle, path, UInt32(flags.rawValue), mode.rawValue)
		guard openStatus == 0 else {
			throw LMDBError(returnCode:openStatus)
		}
		
		self.MDB_env_handle = environmentHandle!
		self.MDB_env_flags = flags
    }

	/// flags that can be used to open an environment
	public struct Flags:OptionSet {

		public let rawValue:UInt32

		public init(rawValue:UInt32) { self.rawValue = rawValue }
		
		/// experimental option that opens the memorymap at a fixed address.
		public static let fixedMap = Flags(rawValue:UInt32(MDB_FIXEDMAP))
		
		/// specify that the environment is a file instead of a directory.
		public static let noSubDir = Flags(rawValue:UInt32(MDB_NOSUBDIR))
		
		/// disables the `fsync` call that typically executes after a transaction is committed.
		public static let noSync = Flags(rawValue:UInt32(MDB_NOSYNC))
		
		/// open the environment as readonly.
		public static let readOnly = Flags(rawValue:UInt32(MDB_RDONLY))
		
		/// disables the `fsync` on the metapage that typically executes after a transaction is committed.
		public static let noMetaSync = Flags(rawValue:UInt32(MDB_NOMETASYNC))
		
		/// use a writable memorymap.
		public static let writeMap = Flags(rawValue:UInt32(MDB_WRITEMAP))
		
		/// sync the memorymap to disk asynchronously when used in combination with the ``Environment/Flags-swift.struct/writeMap`` flag.
		public static let mapAsync = Flags(rawValue:UInt32(MDB_MAPASYNC))
		
		/// associate reader locks with their respective ``Transaction`` objects instead of associating them with their current thread.
		public static let noTLS = Flags(rawValue:UInt32(MDB_NOTLS))
		
		/// disable all locking mechanisms for the database. Caller must manage their own locking.
		public static let noLock = Flags(rawValue:UInt32(MDB_NOLOCK))
		
		/// do not readahead (this flag has no effect on Windows).
		public static let noReadAhead = Flags(rawValue:UInt32(MDB_NORDAHEAD))
		
		/// do not initialize malloc'd memory before writing to the datafile.
		public static let noMemoryInit = Flags(rawValue:UInt32(MDB_NOMEMINIT))
	}
	
	/// this is an opaque pointer to the underlying `MDB_env` object for this environment.
	/// - this pointer can be used if you want to interop this Swift wrapper with the underlying LMDB library functions.
	public let MDB_env_handle:OpaquePointer
	
	/// the flags that were used to initialize the Environment.
	public let MDB_env_flags:Flags
	
	/// remove a database from the environment.
	/// - parameters:
	///   - database: The database that is to be removed from the environment.
	///   - tx: The transaction in which to apply this action. If `nil` is specified, a writable transaction is
    /// - throws: This function will throw an ``LMDBError`` if the environment operation does not return `MDB_SUCCESS`.
	/// - WARNING: this function will remove all of the data in the database. call with caution.
	public func deleteDatabase<D:MDB_db, T:MDB_tx>(_ database:D, MDB_tx tx:T) throws {
		let result = mdb_drop(tx.MDB_tx_handle, database.MDB_db_handle, 1)
		guard result == MDB_SUCCESS else {
			throw LMDBError(returnCode:result)
		}
	}
	
	/// set the size of the memory map to use for this environment.
	/// - the size should be a multiple of the OS page size.
	/// - callers MUST explicitly ensure that no transactions are active in the process before calling this function.
	/// - the new size takes effect immediately for the calling process, but the change will not take effect for other processes until the current process commits a new write transaction.
	public func setMapSize(_ newMapSize:size_t) throws {
		let mdbSetResult = mdb_env_set_mapsize(MDB_env_handle, newMapSize)
		guard mdbSetResult == 0 else {
			throw LMDBError(returnCode:mdbSetResult)
		}
	}
    
    /// copy an LMDB environment to a specified path.
    /// - parameters:
    ///   - path: The path where the environment is to be copied.
    ///   - performCompaction: If true, the operation preforms compation while copying (consumes more CPU and runs slower). If false, the operation does not preform compation.
    /// - throws: this function will throw an ``LMDBError`` if the environment operation fails.
	public func copyTo(path:String, performCompaction:Bool) throws {
		let copyFlags:UInt32 = (performCompaction == true) ? UInt32(MDB_CP_COMPACT) : 0
		let copyResult = mdb_env_copy2(MDB_env_handle, path, copyFlags)
		guard copyResult == 0 else {
			throw LMDBError(returnCode:copyResult)
		}
	}
    
    /// flush the data buffers to disk. Useful for Environments with ``QuickLMDB/Environment/Flags-swift.struct/writeMap`` enabled.
    /// - parameter force: If true, the operation forces a synchronus flush. If false, an asynchronus flush is preformed.
    /// - throws: This function will throw an ``LMDBError`` if the environment operation fails.
	public func sync(force:Bool = true) throws {
		let syncStatus = mdb_env_sync(MDB_env_handle, (force == true ? 1 : 0))
		guard syncStatus == 0 else {
			throw LMDBError(returnCode:syncStatus)
		}
	}
    
    /// checks for stale entries in the reader lock table.
    /// - throws: this function will throw an ``LMDBError`` if the environment operation fails.
    /// - returns: the number of stale slots that were cleared.
	@discardableResult public func readerCheck() throws -> Int32 {
		var deadCheck:Int32 = 0
		let clearCheck = mdb_reader_check(MDB_env_handle, &deadCheck)
		guard clearCheck == MDB_SUCCESS else {
			throw LMDBError(returnCode:clearCheck)
		}
		return deadCheck
	}

	deinit {
		// close the environment handle when all references to this instance are released
		mdb_env_close(MDB_env_handle)
	}
}

