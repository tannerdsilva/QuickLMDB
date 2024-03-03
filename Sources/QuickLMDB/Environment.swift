import CLMDB
import SystemPackage

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

public final class Environment:Sendable {
	/// flags that can be used to open an environment
	public struct Flags:OptionSet, Sendable {
		public let rawValue:UInt32
		public init(rawValue:UInt32) {
			self.rawValue = rawValue
		}
		
		/// Experimental option that opens the memorymap at a fixed address.
		public static let fixedMap = Flags(rawValue:UInt32(MDB_FIXEDMAP))
		
		/// Specify that the environment is a file instead of a directory.
		public static let noSubDir = Flags(rawValue:UInt32(MDB_NOSUBDIR))
		
		/// Disables the `fsync` call that typically executes after a transaction is committed.
		public static let noSync = Flags(rawValue:UInt32(MDB_NOSYNC))
		
		/// Open the environment as readonly.
		public static let readOnly = Flags(rawValue:UInt32(MDB_RDONLY))
		
		/// Disables the `fsync` on the metapage that typically executes after a transaction is committed.
		public static let noMetaSync = Flags(rawValue:UInt32(MDB_NOMETASYNC))
		
		/// Use a writable memorymap.
		public static let writeMap = Flags(rawValue:UInt32(MDB_WRITEMAP))
		
		/// Sync the memorymap to disk asynchronously when used in combination with the ``Environment/Flags-swift.struct/writeMap`` flag.
		public static let mapAsync = Flags(rawValue:UInt32(MDB_MAPASYNC))
		
		/// Associate reader locks with their respective ``Transaction`` objects instead of associating them with their current thread.
		public static let noTLS = Flags(rawValue:UInt32(MDB_NOTLS))
		
		/// Disable all locking mechanisms for the database. Caller must manage their own locking.
		public static let noLock = Flags(rawValue:UInt32(MDB_NOLOCK))
		
		/// Do not readahead (this flag has no effect on Windows).
		public static let noReadAhead = Flags(rawValue:UInt32(MDB_NORDAHEAD))
		
		/// Do not initialize malloc'd memory before writing to the datafile.
		public static let noMemoryInit = Flags(rawValue:UInt32(MDB_NOMEMINIT))
	}

	private let _env_handle:OpaquePointer
	
	/// returns the primitive that LMDB uses to convey this instance
	internal borrowing func envHandle() -> OpaquePointer { 
		return _env_handle
	}

	public let flags:Flags

	/// create a new environment given the specified path and flags.
	#if QUICKLMDB_SHOULDLOG
	private let _logger:Logger?
	public borrowing func logger() -> Logger? {
		return _logger
	}
	public init(path:String, flags:Environment.Flags, mapSize:size_t?, maxReaders:MDB_dbi, maxDBs:MDB_dbi, mode:FilePermissions, logger loggerIn:Logger? = nil) throws {
		var loggerMutate = loggerIn
		loggerMutate?[metadataKey:"type"] = "env"
		
		// create the environment variable
		var environmentHandle:OpaquePointer? = nil;
		let envStatus = mdb_env_create(&environmentHandle)
		guard envStatus == 0 && environmentHandle != nil else {
			loggerMutate?.critical("critical memory failure during init", metadata:["env_path":"\(path)", "env_flags":"\(flags)"])
			throw LMDBError(returnCode:envStatus)
		}
		
		// set the map size
		if mapSize != nil {
			let mdbSetResult = mdb_env_set_mapsize(environmentHandle, mapSize!)
			guard mdbSetResult == 0 else {
				loggerMutate?.critical("unable to set expected mapsize", metadata:["env_path":"\(path)", "env_flags":"\(flags)"])
				throw LMDBError(returnCode:mdbSetResult)
			}
		}
		
		// set the maximum readers. this must be done between the `mdb_env_create` and `mdb_env_open` calls.
		let setReadersResult = mdb_env_set_maxreaders(environmentHandle, maxReaders)
		guard setReadersResult == 0 else {
			loggerMutate?.critical("unable to set maximum number of readers", metadata:["env_path":"\(path)", "env_flags":"\(flags)"])
			throw LMDBError(returnCode:setReadersResult)
		}
		
		// set maximum db count
		let mdbSetResult = mdb_env_set_maxdbs(environmentHandle, maxDBs)
		guard mdbSetResult == 0 else {
			loggerMutate?.critical("unable to set maximum db count", metadata:["env_path":"\(path)", "env_flags":"\(flags)"])
			throw LMDBError(returnCode:mdbSetResult)
		}
		
		// open the environment with the specified flags and file modes specified
		let openStatus = mdb_env_open(environmentHandle, path, UInt32(flags.rawValue), mode.rawValue)
		guard openStatus == 0 else {
			loggerMutate?.critical("init failed", metadata:["env_path":"\(path)", "env_flags":"\(flags)", "mdb_return_code":"\(openStatus)"])
			throw LMDBError(returnCode:openStatus)
		}
		
		loggerMutate?.info("init successful", metadata:["env_path":"\(path)", "env_flags":"\(flags)"])
		self._env_handle = environmentHandle!
		self.flags = flags
		self._logger = loggerMutate
	}
	#else
	public init(path:String, flags:Environment.Flags, mapSize:size_t?, maxReaders:MDB_dbi, maxDBs:MDB_dbi, mode:FilePermissions) throws {

		// create the environment variable
		var environmentHandle:OpaquePointer? = nil;
		let envStatus = mdb_env_create(&environmentHandle)
		guard envStatus == 0 && environmentHandle != nil else {
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
		
		self._env_handle = environmentHandle!
		self.flags = flags
	}
	#endif
	
	// create a new root-level transaction.
	public borrowing func transact<R>(readOnly:Bool, _ handler:(consuming Transaction) throws -> R) rethrows -> R {
		#if QUICKLMDB_SHOULDLOG
		return try handler(try! Transaction(env:self, readOnly:readOnly))
		#else
		return try handler(try! Transaction(env:self, readOnly:readOnly))
		#endif
	}

	// create a sub-transaction with a provided parent.
	public borrowing func transact<R>(readOnly:Bool, parent:borrowing Transaction, _ handler:(consuming Transaction) throws -> R) rethrows -> R {
		#if QUICKLMDB_SHOULDLOG
		return try handler(try! Transaction(env:self, readOnly:readOnly, parent:parent))
		#else
		return try handler(try! Transaction(env:self, readOnly:readOnly, parent:parent))
		#endif
	}
}

// public protocol MDB_env {

// 	/// the environment handle primitive that LMDB uses.
// 	var handle:OpaquePointer { get }
// 	/// the environment flags that was used to create the environment.
// 	var flags:Environment.Flags { get }


// 	// initializer (conditional based on log config)
// 	#if QUICKLMDB_SHOULDLOG

// 	/// the logger that the environment uses to document its actions.
// 	var logger:Logger? { get }
// 	/// create a new environment given the specified path and flags.
// 	init(path:String, flags:Environment.Flags, mapSize:size_t?, maxReaders:MDB_dbi, maxDBs:MDB_dbi, mode:FilePermissions, logger:Logger?) throws

// 	#else
// 	/// create a new environment given the specified path and flags.
// 	init(path:String, flags:Environment.Flags, mapSize:size_t?, maxReaders:MDB_dbi, maxDBs:MDB_dbi, mode:FilePermissions) throws

// 	#endif


// 	// transaction functions (conditional based on log config)
// 	/// transaction handler with a parent
// 	// func transact<T, P, R>(readOnly:Bool, parent:borrowing P, _ handler:(consuming T) throws -> R) rethrows -> R where T:MDB_tx, P:MDB_tx
// 	/// transaction handler without a parent
// 	func transact<R>(readOnly:Bool, _ handler:(consuming Transaction) throws -> R) rethrows -> R
// }

// // default implementation of debug descriptions for the environment
// extension MDB_env where Self:CustomDebugStringConvertible {
// 	/// 
// 	public var debugDescription:String {
// 		return "[MDB_env](\(handle.hashValue))"
// 	}
// }

// extension MDB_env {

// 	public func transaction<R>(readOnly:Bool, _ handler:())
// 	/// transaction handler with a parent
// 	/// - parameters:
// 	/// 	- type: the type of transaction to create
// 	///		- readOnly: true if the newly created transaction should be restricted to readonly mode
// 	///		- MDB_tx_parent: the parent LMDB transaction to use to create this child transaction
// 	// public func MDB_tx<T, P, R>(_ txType:T.Type, readOnly:Bool, MDB_tx_parent parent:UnsafeMutablePointer<P>, _ handler:(UnsafeMutablePointer<T>) throws -> R) rethrows -> R where T:MDB_tx, P:MDB_tx {
		
// 	// 	return try withUnsafeMutablePointer(to:try! T(self, readOnly:readOnly, MDB_tx_parent:parent)) { txPtr in
// 	// 		let captureReturn:R
// 	// 		do {
// 	// 			#if QUICKLMDB_SHOULDLOG
// 	// 			logger?.trace("calling MDB_tx handler function (parent variant)", metadata:["MDB_tx":"\(txPtr.pointee)"])
// 	// 			#endif
// 	// 			captureReturn = try handler(txPtr)
// 	// 			if txPtr.pointee.MDB_tx_readOnly == false {
// 	// 				#if QUICKLMDB_SHOULDLOG
// 	// 				logger?.trace("MDB_tx handler returned without an error. calling transaction commit", metadata:["MDB_tx":"\(txPtr.pointee)"])
// 	// 				#endif
// 	// 				try! txPtr.pointee.MDB_tx_commit()
// 	// 			}
// 	// 		} catch let error {
// 	// 			if txPtr.pointee.MDB_tx_readOnly == false {
// 	// 				#if QUICKLMDB_SHOULDLOG
// 	// 				logger?.trace("MDB_tx handler returned with an error. calling transaction abort", metadata:["error_thrown":"\(error)", "MDB_tx":"\(txPtr.pointee)"])
// 	// 				#endif
// 	// 				txPtr.pointee.MDB_tx_abort()
// 	// 			} else {
// 	// 				#if QUICKLMDB_SHOULDLOG
// 	// 				logger?.trace("MDB_tx handler returned with an error. calling transaction abort", metadata:["error_thrown":"\(error)", "MDB_tx":"\(txPtr.pointee)"])
// 	// 				#endif
// 	// 			}
// 	// 			throw error
// 	// 		}
// 	// 		return captureReturn
// 	// 	}
// 	// }

// 	/// transaction handler without a parent
// 	/// - parameters:
// 	///		- type: the type of transaction to create
// 	///		- readOnly: true if the newly created transaction should be restricted to readonly mode
// 	///		- MDB_tx_parent: the parent LMDB transaction to use to create this child transaction
// 	public func MDB_tx<T, R>(_ txType:T.Type, readOnly:Bool, _ handler:(UnsafeMutablePointer<T>) throws -> R) rethrows -> R where T:MDB_tx {
// 		return try withUnsafeMutablePointer(to:try! T(self, readOnly:readOnly)) { txPtr in
// 			let captureReturn:R
// 			do {
// 				#if QUICKLMDB_SHOULDLOG
// 				logger?.trace("calling MDB_tx handler function (no parent variant)")
// 				#endif
// 				captureReturn = try handler(txPtr)
// 				if txPtr.pointee.MDB_tx_readOnly == false {
// 					#if QUICKLMDB_SHOULDLOG
// 					logger?.trace("MDB_tx handler returned without an error. calling transaction commit", metadata:["MDB_tx":"\(txPtr.pointee)"])
// 					#endif
// 					try! txPtr.pointee.MDB_tx_commit()
// 				}
// 			} catch let error {
// 				if txPtr.pointee.MDB_tx_readOnly == false {
// 					#if QUICKLMDB_SHOULDLOG
// 					logger?.trace("MDB_tx handler returned with an error. calling transaction abort", metadata:["error_thrown":"\(error)", "MDB_tx":"\(txPtr.pointee)"])
// 					#endif
// 					txPtr.pointee.MDB_tx_abort()
// 				} else {
// 					#if QUICKLMDB_SHOULDLOG
// 					logger?.trace("MDB_tx handler returned with an error. calling transaction abort", metadata:["error_thrown":"\(error)", "MDB_tx":"\(txPtr.pointee)"])
// 					#endif
// 				}
// 				throw error
// 			}
// 			return captureReturn
// 		}
// 	}
// }

// public struct Environmentb {
//     public typealias MDB_tx_type = Transaction

// 	#if QUICKLMDB_SHOULDLOG
// 	public private(set) let logger:Logger?
//     public init(path:String, flags:Flags, mapSize:size_t?, maxReaders:MDB_dbi, maxDBs:MDB_dbi, mode:SystemPackage.FilePermissions, logger:Logger? = nil) throws {
// 		var mutateLogger = logger
// 		mutateLogger?[metadataKey:"type"] = "Environment"
		
// 		// create the environment variable
// 		var environmentHandle:OpaquePointer? = nil;
// 		let envStatus = mdb_env_create(&environmentHandle)
// 		guard envStatus == 0 && environmentHandle != nil else {
// 			mutateLogger?.critical("unable to allocate space in memory for the LMDB environment")
// 			throw LMDBError(returnCode:envStatus)
// 		}
// 		mutateLogger?[metadataKey:"mdb_env_iid"] = "\(environmentHandle!.hashValue)"
// 		mutateLogger?.debug("initializing new LMDB environment", metadata:["mdb_env_path":"'\(path)'"])
		
// 		// set the map size
// 		if mapSize != nil {
// 			mutateLogger?.trace("using explicit mapsize (\(mapSize!) bytes) prior to environment initialization")
// 			let mdbSetResult = mdb_env_set_mapsize(environmentHandle, mapSize!)
// 			guard mdbSetResult == 0 else {
// 				mutateLogger?.critical("unable to set explicit mapsize of (\(mapSize!) bytes)")
// 				throw LMDBError(returnCode:mdbSetResult)
// 			}
// 		}
		
// 		// set the maximum readers. this must be done between the `mdb_env_create` and `mdb_env_open` calls.
// 		mutateLogger?.trace("assigning maximum reader count prior to environment initialization")
// 		let setReadersResult = mdb_env_set_maxreaders(environmentHandle, maxReaders)
// 		guard setReadersResult == 0 else {
// 			mutateLogger?.critical("unable to set maximum reader count prior to environment initialization")
// 			throw LMDBError(returnCode:setReadersResult)
// 		}
		
// 		// set maximum db count
// 		mutateLogger?.trace("assigning maximum database count prior to environment initialization", "maximum_db_count":"\(maxDBs)")
// 		let mdbSetResult = mdb_env_set_maxdbs(environmentHandle, maxDBs)
// 		guard mdbSetResult == 0 else {
// 			mutateLogger?.critical("unable to set maximum database count prior to environment initialization")
// 			throw LMDBError(returnCode:mdbSetResult)
// 		}
		
// 		// open the environment with the specified flags and file modes specified
// 		mutateLogger?.trace("initializing lmdb environment", metadata:["mdb_env_flags":"\(flags)"])
// 		let openStatus = mdb_env_open(environmentHandle, path, UInt32(flags.rawValue), mode.rawValue)
// 		guard openStatus == 0 else {
// 			mutateLogger?.critical("failed to initialize lmdb environment", metadata:["return_code":"\(openStatus)"])
// 			throw LMDBError(returnCode:openStatus)
// 		}
// 		mutateLogger?.info("successfully initialized LMDB environment", metadata:["mdb_env_path":"'\(path)'", "mdb_env_flags":"\(flags)"])
		
// 		self.MDB_env_handle = environmentHandle!
// 		self.MDB_env_flags = flags
// 		self.logger = logger
		
//     }
//     #else
//     public init(path: String, flags: Flags, mapSize:size_t?, maxReaders:MDB_dbi, maxDBs:MDB_dbi, mode:SystemPackage.FilePermissions) throws {
	
// 		// create the environment variable
// 		var environmentHandle:OpaquePointer? = nil;
// 		let envStatus = mdb_env_create(&environmentHandle)
// 		guard envStatus == 0 else {
// 			throw LMDBError(returnCode:envStatus)
// 		}
		
// 		// set the map size
// 		if mapSize != nil {
// 			let mdbSetResult = mdb_env_set_mapsize(environmentHandle, mapSize!)
// 			guard mdbSetResult == 0 else {
// 				throw LMDBError(returnCode:mdbSetResult)
// 			}
// 		}
		
// 		// set the maximum readers. this must be done between the `mdb_env_create` and `mdb_env_open` calls.
// 		let setReadersResult = mdb_env_set_maxreaders(environmentHandle, maxReaders)
// 		guard setReadersResult == 0 else {
// 			throw LMDBError(returnCode:setReadersResult)
// 		}
		
// 		// set maximum db count
// 		let mdbSetResult = mdb_env_set_maxdbs(environmentHandle, maxDBs)
// 		guard mdbSetResult == 0 else {
// 			throw LMDBError(returnCode:mdbSetResult)
// 		}
		
// 		// open the environment with the specified flags and file modes specified
// 		let openStatus = mdb_env_open(environmentHandle, path, UInt32(flags.rawValue), mode.rawValue)
// 		guard openStatus == 0 else {
// 			throw LMDBError(returnCode:openStatus)
// 		}
		
// 		self.MDB_env_handle = environmentHandle!
// 		self.MDB_env_flags = flags
//     }
//     #endif

// 	/// flags that can be used to open an environment.
// 	public struct Flags:Sendable, OptionSet {
		
// 		/// the raw integer value that can be used with the LMDB API directly.
// 		public let rawValue:UInt32
	
// 		/// initialize with the underlying LMDB integer value.
// 		public init(rawValue:UInt32) { self.rawValue = rawValue }
		
// 		/// experimental option that opens the memorymap at a fixed address.
// 		public static let fixedMap = Flags(rawValue:UInt32(MDB_FIXEDMAP))
		
// 		/// specify that the environment is a file instead of a directory.
// 		public static let noSubDir = Flags(rawValue:UInt32(MDB_NOSUBDIR))
		
// 		/// disables the `fsync` call that typically executes after a transaction is committed.
// 		public static let noSync = Flags(rawValue:UInt32(MDB_NOSYNC))
		
// 		/// open the environment as readonly.
// 		public static let readOnly = Flags(rawValue:UInt32(MDB_RDONLY))
		
// 		/// disables the `fsync` on the metapage that typically executes after a transaction is committed.
// 		public static let noMetaSync = Flags(rawValue:UInt32(MDB_NOMETASYNC))
		
// 		/// use a writable memorymap.
// 		public static let writeMap = Flags(rawValue:UInt32(MDB_WRITEMAP))
		
// 		/// sync the memorymap to disk asynchronously when used in combination with the ``Environment/Flags-swift.struct/writeMap`` flag.
// 		public static let mapAsync = Flags(rawValue:UInt32(MDB_MAPASYNC))
		
// 		/// associate reader locks with their respective ``Transaction`` objects instead of associating them with their current thread.
// 		public static let noTLS = Flags(rawValue:UInt32(MDB_NOTLS))
		
// 		/// disable all locking mechanisms for the database. Caller must manage their own locking.
// 		public static let noLock = Flags(rawValue:UInt32(MDB_NOLOCK))
		
// 		/// do not readahead (this flag has no effect on Windows).
// 		public static let noReadAhead = Flags(rawValue:UInt32(MDB_NORDAHEAD))
		
// 		/// do not initialize malloc'd memory before writing to the datafile.
// 		public static let noMemoryInit = Flags(rawValue:UInt32(MDB_NOMEMINIT))
// 	}
	
// 	/// this is an opaque pointer to the underlying `MDB_env` object for this environment.
// 	/// - this pointer can be used if you want to interop this Swift wrapper with the underlying LMDB library functions.
// 	public let MDB_env_handle:OpaquePointer
	
// 	/// the flags that were used to initialize the Environment.
// 	public let MDB_env_flags:Flags
	
// 	/// remove a database from the environment.
// 	/// - parameters:
// 	///   - database: The database that is to be removed from the environment.
// 	///   - tx: The transaction in which to apply this action. If `nil` is specified, a writable transaction is
//     /// - throws: This function will throw an ``LMDBError`` if the environment operation does not return `MDB_SUCCESS`.
// 	/// - WARNING: this function will remove all of the data in the database. call with caution.
// 	public func deleteDatabase<D:MDB_db, T:MDB_tx>(_ database:D, MDB_tx tx:UnsafePointer<T>) throws {
// 		#if QUICKLMDB_SHOULDLOG
// 		logger?.trace("ENTER>: deleteDatabase()", metadata:["mdb_db_name":"\(database.MDB_db_name)"])
// 		defer {
// 			logger?.trace("<EXIT: deleteDatabase()", metadata:["mdb_db_name":"\(database.MDB_db_name)"])
// 		}
// 		#endif
// 		let result = mdb_drop(tx.pointee.MDB_tx_handle, database.MDB_db_handle, 1)
// 		guard result == MDB_SUCCESS else {
// 			#if QUICKLMDB_SHOULDLOG
// 			logger?.error("failed to delete LMDB database", metadata:["mdb_return_code":"\(result)", "mdb_db_name":"\(database.MDB_db_name)"])
// 			#endif
// 			throw LMDBError(returnCode:result)
// 		}
// 		#if QUICKLMDB_SHOULDLOG
// 		logger?.info("successfully deleted LMDB database",  metadata:["mdb_db_name":"\(database.MDB_db_name)"])
// 		#endif
// 	}
	
// 	/// set the size of the memory map to use for this environment.
// 	/// - the size should be a multiple of the OS page size.
// 	/// - callers MUST explicitly ensure that no transactions are active in the process before calling this function.
// 	/// - the new size takes effect immediately for the calling process, but the change will not take effect for other processes until the current process commits a new write transaction.
// 	public func setMapSize(_ newMapSize:size_t) throws {
// 		#if QUICKLMDB_SHOULDLOG
// 		logger?.trace("ENTER>: setMapSize()", metadata:["mdb_env_mapsize":"\(newMapSize)"])
// 		defer {
// 			logger?.trace("<EXIT: setMapSize()", metadata:["mdb_env_mapsize":"\(newMapSize)"])
// 		}
// 		#endif
// 		let mdbSetResult = mdb_env_set_mapsize(MDB_env_handle, newMapSize)
// 		guard mdbSetResult == 0 else {
// 			#if QUICKLMDB_SHOULDLOG
// 			logger?.error("failed to set mapsize of LMDB environment", metadata:["mdb_return_code":"\(mdbSetResult)"])
// 			#endif
// 			throw LMDBError(returnCode:mdbSetResult)
// 		}
// 		#if QUICKLMDB_SHOULDLOG
// 		logger?.info("successfully set mapsize of LMDB environment", metadata:["mdb_env_mapsize":"\(newMapSize)"])
// 		#endif
// 	}
    
//     /// copy an LMDB environment to a specified path.
//     /// - parameters:
//     ///   - path: The path where the environment is to be copied.
//     ///   - performCompaction: If true, the operation preforms compation while copying (consumes more CPU and runs slower). If false, the operation does not preform compation.
//     /// - throws: this function will throw an ``LMDBError`` if the environment operation fails.
// 	public func copyTo(path:String, performCompaction:Bool) throws {
// 		#if QUICKLMDB_SHOULDLOG
// 		logger?.trace("ENTER>: copyTo()", metadata:["copy_destination_path":"'\(path)'"])
// 		defer {
// 			logger?.trace("<EXIT: copyTo()", metadata:["copy_destination_path":"'\(path)'"])
// 		}
// 		#endif
// 		let copyFlags:UInt32 = (performCompaction == true) ? UInt32(MDB_CP_COMPACT) : 0
// 		let copyResult = mdb_env_copy2(MDB_env_handle, path, copyFlags)
// 		guard copyResult == 0 else {
// 			#if QUICKLMDB_SHOULDLOG
// 			logger?.error("failed to copy LMDB environment", metadata:["mdb_return_code":"\(copyResult)"])
// 			#endif
// 			throw LMDBError(returnCode:copyResult)
// 		}
// 		#if QUICKLMDB_SHOULDLOG
// 		logger?.info("successfully copied LMDB environment", metadata:["copy_destination_path":"'\(path)'"])
// 		#endif
// 	}
    
//     /// flush the data buffers to disk. Useful for Environments with ``QuickLMDB/Environment/Flags-swift.struct/writeMap`` enabled.
//     /// - parameter force: if true, the operation forces a synchronus flush. If false, an asynchronus flush is preformed.
//     /// - throws: this function will throw an ``LMDBError`` if the environment operation fails.
// 	public func sync(force:Bool = true) throws {
// 		#if QUICKLMDB_SHOULDLOG
// 		logger?.trace("ENTER>: sync()", metadata:["sync_force":"'\(force)'"])
// 		defer {
// 			logger?.trace("<EXIT: sync()", metadata:["sync_force":"'\(force)'"])
// 		}
// 		#endif
// 		let syncStatus = mdb_env_sync(MDB_env_handle, (force == true ? 1 : 0))
// 		guard syncStatus == 0 else {
// 			#if QUICKLMDB_SHOULDLOG
// 			logger?.error("failed to sync LMDB environment", metadata:["mdb_return_code":"\(syncStatus)"])
// 			#endif
// 			throw LMDBError(returnCode:syncStatus)
// 		}
// 		#if QUICKLMDB_SHOULDLOG
// 		logger?.info("successfully synced LMDB environment with disk")
// 		#endif
// 	}
    
//     /// checks for stale entries in the reader lock table.
//     /// - throws: this function will throw an ``LMDBError`` if the environment operation fails.
//     /// - returns: the number of stale slots that were cleared.
// 	@discardableResult public func readerCheck() throws -> Int32 {
// 		#if QUICKLMDB_SHOULDLOG
// 		logger?.trace("ENTER>: readerCheck()")
// 		defer {
// 			logger?.trace("<EXIT: readerCheck()")
// 		}
// 		#endif
// 		var deadCheck:Int32 = 0
// 		let clearCheck = mdb_reader_check(MDB_env_handle, &deadCheck)
// 		guard clearCheck == MDB_SUCCESS else {
// 			#if QUICKLMDB_SHOULDLOG
// 			logger?.error("failed to check for readers", metadata:["mdb_return_code":"\(syncStatus)"])
// 			#endif
// 			throw LMDBError(returnCode:clearCheck)
// 		}
// 		#if QUICKLMDB_SHOULDLOG
// 		logger?.info("successfully checked LMDB environment for stale readers.", metadata:["dead_readers_found":"\(deadCheck)"])
// 		#endif
// 		return deadCheck
// 	}
	
// 	deinit {
// 		// close the environment handle when all references to this instance are released
// 		logger?.trace("deinitializing LMDB environment instance")
// 		mdb_env_close(MDB_env_handle)
// 		logger?.notice("deinitialized LMDB environment instance")
// 	}
// }

