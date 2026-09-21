import CLMDB
import SystemPackage
import RAW

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
		
		/// use encrypted on the environment (LMDB 1.0). set automatically by the
		/// `Environment.init(..., encrypt:)` initializer when encryption is configured.
		public static let encrypt = Flags(rawValue:UInt32(MDB_ENCRYPT))
		
		/// keep the memory map in 16-page chunks, remapping on demand (LMDB 1.0).
		public static let remapChunks = Flags(rawValue:UInt32(MDB_REMAP_CHUNKS))
		
		/// open the environment with the previous snapshot of its data (LMDB 1.0).
		public static let previousSnapshot = Flags(rawValue:UInt32(MDB_PREVSNAPSHOT))
	}

	/// configuration for an encrypted environment: the encryption implementation
	/// (its C callback) plus the raw cipher key bytes. handed to
	/// `Environment.init(..., encrypt:)`, which registers it with the engine before
	/// the environment is opened.
	public struct EncryptionConfiguration {
		/// the encryption implementation that provides the `mdb_env_set_encrypt` callback.
		public let implementation: MDB_crypto_impl.Type
		/// the raw encryption key bytes.
		public let key: [UInt8]
		/// build a configuration wrapping the given implementation and key.
		public init<A>(_ impl: MDB_crypto_impl.Type, key inKey: A) where A: RAW_accessible {
			self.implementation = impl
			self.key = inKey.RAW_access_immutable(UnsafeRawBufferPointer.self) { keyBuf in
				return [UInt8](keyBuf)
			}
		}
	}

	private let _env_handle:OpaquePointer
	
	/// returns the primitive that LMDB uses to convey this instance
	internal borrowing func envHandle() -> OpaquePointer { 
		return _env_handle
	}

	/// the flags that were used to open the environment
	public let flags:Flags

	/// create a new environment given the specified path and flags.
	/// - parameter encrypt: an optional encryption configuration. when provided,
	///   `mdb_env_set_encrypt` is called before the environment opens and the
	///   environment is created with encryption enabled (the engine additionally
	///   enables chunked remapping, which authenticated encryption requires).
	/// - parameter checksum: an optional checksum implementation. when provided,
	///   `mdb_env_set_checksum` is called before the environment opens.
	public init(path:String, flags:Environment.Flags, mapSize:Int?, maxReaders:MDB_dbi, maxDBs:MDB_dbi, mode:FilePermissions, encrypt:EncryptionConfiguration? = nil, checksum:any MDB_checksum_impl.Type? = nil) throws {

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

		// if encryption is configured, register the encrypt callback + cipher key
		// before the environment opens. `mdb_env_set_encrypt` implicitly enables
		// chunked remapping and the encrypt flag on the environment — they must
		// NOT be passed again in the open flags (the engine rejects them as
		// read-only); they are reflected in the stored `flags` for introspection.
		var effectiveFlags = flags
		if let encrypt {
			try encrypt.key.RAW_access_immutable(UnsafeRawBufferPointer.self) { encKeyBuff in
				var passKey = MDB_val(mv_size: encKeyBuff.count, mv_data: UnsafeMutableRawPointer(mutating: encKeyBuff.baseAddress))
				let rc = mdb_env_set_encrypt(environmentHandle, encrypt.implementation.MDB_crypto_f, &passKey, encrypt.implementation.MDB_esumsize)
				guard rc == 0 else {
					throw LMDBError(returnCode: rc)
				}
			}
			effectiveFlags = effectiveFlags.union(.encrypt).union(.remapChunks)
		}
		if let checksum {
			let rc = mdb_env_set_checksum(environmentHandle, checksum.MDB_sum_f, checksum.MDB_sumsize)
			guard rc == 0 else {
				throw LMDBError(returnCode: rc)
			}
		}

		// open the environment with the original user flags — `mdb_env_set_encrypt`
		// already set the encrypt + remap-chunks bits on the env handle
		let openStatus = mdb_env_open(environmentHandle, path, UInt32(flags.rawValue), mode.rawValue)
		guard openStatus == 0 else {
			throw LMDBError(returnCode:openStatus)
		}
		
		self._env_handle = environmentHandle!
		self.flags = effectiveFlags
	}
	
	/// flush the data buffers to disk. needed for environments that are operating with ``QuickLMDB/Environment/Flags/writeMap`` or ``QuickLMDB/Environment/Flags/noSync`` enabled.
	public func sync(force:Bool = true) throws {
		let syncStatus = mdb_env_sync(envHandle(), (force == true ? 1 : 0))
		guard syncStatus == 0 else {
			throw LMDBError(returnCode:syncStatus)
		}
	}
	
	@discardableResult public func readerCheck() throws -> Int32 {
		var deadCheck:Int32 = 0
		let clearCheck = mdb_reader_check(envHandle(), &deadCheck)
		guard clearCheck == MDB_SUCCESS else {
			throw LMDBError(returnCode:clearCheck)
		}
		return deadCheck
	}


	deinit {
		// close the environment handle when all references to this instance are released
		mdb_env_close(envHandle())
	}

}