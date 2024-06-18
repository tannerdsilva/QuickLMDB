import CLMDB
import SystemPackage
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

public final class Environment:@unchecked Sendable {
	/// flags that can be used to open an environment
	public struct Flags:OptionSet, Sendable {
		public let rawValue:UInt32
		public init(rawValue:UInt32) {
			self.rawValue = rawValue
		}
		
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

	private let _env_handle:OpaquePointer
	
	/// returns the primitive that LMDB uses to convey this instance
	internal borrowing func envHandle() -> OpaquePointer { 
		return _env_handle
	}

	/// the flags that were used to open the environment
	public let flags:Flags

	public struct EncryptionConfiguration {
		public let implementation:MDB_crypto_impl.Type
		public let key:[UInt8]
		public init<A>(_ impl:MDB_crypto_impl.Type, key inKey:A) where A:RAW_accessible {
			self.implementation = impl
			self.key = inKey.RAW_access({
				return [UInt8]($0)
			})
		}
	}
	public init(path:String, flags:Environment.Flags, mapSize:size_t?, maxReaders:MDB_dbi, maxDBs:MDB_dbi, mode:FilePermissions, encrypt:EncryptionConfiguration? = nil, checksum:MDB_checksum_impl.Type? = nil) throws {

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

		if let encrypt = encrypt {
			try encrypt.key.RAW_access { encKeyBuff in
				var passKey = MDB_val(mv_size:encKeyBuff.count, mv_data:UnsafeMutableRawPointer(mutating:encKeyBuff.baseAddress))
				let rc = mdb_env_set_encrypt(environmentHandle, encrypt.implementation.MDB_crypto_f, &passKey, 16)
				guard rc == 0 else {
					throw LMDBError(returnCode:rc)
				}
			}	
		}
		if let checksum = checksum {
			mdb_env_set_checksum(environmentHandle, checksum.MDB_sum_f, UInt32(Blake2.outputLength))
		}
		
		// open the environment with the specified flags and file modes specified
		let openStatus = mdb_env_open(environmentHandle, path, UInt32(flags.rawValue), mode.rawValue)
		guard openStatus == 0 else {
			throw LMDBError(returnCode:openStatus)
		}
		
		self._env_handle = environmentHandle!
		self.flags = flags
	}
	
	/// flush the data buffers to disk. needed for environments that are operating with ``QuickLMDB/Environment/Flags/writeMap`` or ``QuickLMDB/Environment/Flags/noSync`` enabled.
	public func sync(force:Bool = true) throws {
		#if QUICKLMDB_SHOULDLOG
		logger()?.trace(">", metadata:["_func":"sync()", "type":"Environment", "sync_force":"'\(force)'"])
		defer {
			logger()?.trace("<", metadata:["_func":"sync()", "type":"Environment", "sync_force":"'\(force)'"])
		}
		#endif
		let syncStatus = mdb_env_sync(envHandle(), (force == true ? 1 : 0))
		guard syncStatus == 0 else {
			#if QUICKLMDB_SHOULDLOG
			logger()?.error("failed to sync LMDB environment", metadata:["mdb_return_code":"\(syncStatus)"])
			#endif
			throw LMDBError(returnCode:syncStatus)
		}
		#if QUICKLMDB_SHOULDLOG
		logger()?.info("successfully synced LMDB environment with disk")
		#endif
	}
	
	@discardableResult public func readerCheck() throws -> Int32 {
		#if QUICKLMDB_SHOULDLOG
		logger?.trace(">", metadata:["_func":"readerCheck()"])
		defer {
			logger?.trace("<", metadata:["_func":"readerCheck()"])
		}
		#endif
		var deadCheck:Int32 = 0
		let clearCheck = mdb_reader_check(envHandle(), &deadCheck)
		guard clearCheck == MDB_SUCCESS else {
			#if QUICKLMDB_SHOULDLOG
			logger?.error("failed to check for readers", metadata:["_func":"readerCheck()", "mdb_return_code":"\(syncStatus)"])
			#endif
			throw LMDBError(returnCode:clearCheck)
		}
		#if QUICKLMDB_SHOULDLOG
		logger?.info("successfully checked LMDB environment for stale readers.", metadata:["_func":"readerCheck()", "dead_readers_found":"\(deadCheck)"])
		#endif
		return deadCheck
	}


	deinit {
		// close the environment handle when all references to this instance are released
		#if QUICKLMDB_SHOULDLOG
		logger()?.trace("deinitializing LMDB environment instance")
		#endif
		mdb_env_close(envHandle())
		#if QUICKLMDB_SHOULDLOG
		logger()?.notice("deinitialized LMDB environment instance")
		#endif
	}

}