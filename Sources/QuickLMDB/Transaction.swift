import CLMDB

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

public protocol MDB_tx:CustomDebugStringConvertible {
	/// the environment handle primitive that LMDB uses.
	var envHandle:OpaquePointer { get }
	/// the transaction handle primitive that LMDB uses.
	var txHandle:OpaquePointer { get }
	/// indicates if the transaction is read-only.
	var readOnly:Bool { get }

	#if QUICKLMDB_SHOULDLOG
	/// logging facilites for the transaction instance
	var logger:Logger?
	
	/// creates a new child transaction given the specified env handle and parent tx handle.
	init<E:MDB_env, T:MDB_tx>(env:UnsafePointer<E>, readOnly:Bool, txParent:UnsafePointer<T>, logger:Logger?) throws
	/// creates a new root transaction given the specified env handle.
	init<E:MDB_env>(env:UnsafePointer<E>, readOnly:Bool, logger:Logger?) throws
	
	#else
	
	/// creates a new child transaction given the specified env handle and parent tx handle.
	init<E:MDB_env, T:MDB_tx>(env:UnsafePointer<E>, readOnly:Bool, txParent:UnsafeMutablePointer<T>) throws
	/// creates a new root transaction given the specified env handle.
	init<E:MDB_env>(env:UnsafePointer<E>, readOnly:Bool) throws
	
	#endif
	
	
	/// commits the transaction.
	mutating func commit() throws
	/// resets the transaction.
	mutating func reset()
	/// renews the transaction.
	mutating func renew() throws
	/// aborts the transaction.
	mutating func abort()
}

// default implementation of debug descriptions for the environment
extension MDB_tx where Self:CustomDebugStringConvertible {
	/// the debug description of the LMDB transaction instance
	public var debugDescription:String {
		return "[\(String(describing:type(of:self)))](\(txHandle.hashValue))"
	}
}

public final class Transaction:MDB_tx, Sendable {
    public init<E, T>(env: UnsafePointer<E>, readOnly: Bool, txParent: UnsafeMutablePointer<T>) throws where E : MDB_env, T : MDB_tx {
        
    }

	/// pointer to the `MDB_env` that an instance is associated with.
	public let envHandle:OpaquePointer
	/// pointer to the `MDB_txn` struct associated with a given instance.
	public let txHandle:OpaquePointer
	/// indicates if a given instance is a read-only transaction.
	public let readOnly:Bool
	
	/// tracks if the transaction is open or not.
	internal var isOpen = true

	#if QUICKLMDB_SHOULDLOG
	internal let logger:Logger?
	/// creates a new transaction from an Environment and optional parent.
	public required init<E:MDB_env, T:MDB_tx>(env:UnsafePointer<E>, readOnly:Bool, txParent parent:UnsafePointer<T>, logger:Logger?) throws {
		var mutateLogger = logger
		mutateLogger?[metadataKey:"type"] = "Transaction"
		
		let eh = env.pointer(to:.envHandle)!.pointee
		envHandle = eh
		readOnly = readOnly
		
		var start_handle:OpaquePointer? = nil
		let txnFlags = readOnly ? UInt32(MDB_RDONLY) : 0
		mutateLogger?.trace("initializing LMDB tx instance (from parent)", metadata:["mdb_txi_parent_id":"\(parent.pointee)", "mdb_txi_readonly":"\(readOnly)"])
		
		let createResult = mdb_txn_begin(eh, parent.pointer(to:.txHandle).pointee, txnFlags, &start_handle)
		guard createResult == 0 else {
			mutateLogger?.critical("unable to create LMDB tx instance (from parent)", metadata:["mdb_txi_parent_id":"\(parent.pointee)", "mdb_return_code":"\(createResult)", "mdb_txi_readonly":"\(readOnly)"])
			throw LMDBError(returnCode:createResult)
		}

		#if DEBUG
		assert(start_handle != nil, "a LMDB tx pointer should have been created")
		#endif

		mutateLogger[metadataKey:"mdb_txi_id"] = "[Transaction](\(start_handle!.hashValue))"
		mutateLogger?.info("init", metadata:["mdb_txi_parent_id":"\(parent.pointee)", "mdb_txi_readonly":"\(readOnly)"]) 
		txHandle = start_handle!
		logger = mutateLogger
	}
	public required init<E:MDB_env>(env:UnsafePointer<E>, readOnly:Bool, logger:Logger?) throws {
		var mutateLogger = logger
		mutateLogger?[metadataKey:"type"] = "Transaction"
		
		let eh = env.pointer(to:.envHandle)!.pointee
		envHandle = eh
		readOnly = readOnly
		
		var start_handle:OpaquePointer? = nil
		let txnFlags = readOnly ? UInt32(MDB_RDONLY) : 0
		mutateLogger?.trace("initializing LMDB tx instance (no parent)", metadata:["mdb_txi_parent_id":"n/a", "mdb_txi_readonly":"\(readOnly)"])
		
		let createResult = mdb_txn_begin(eh, nil, txnFlags, &start_handle)
		guard createResult == 0 else {
			mutateLogger?.critical("unable to create LMDB tx instance (no parent)", metadata:["mdb_txi_parent_id":"n/a", "mdb_return_code":"\(createResult)", "mdb_txi_readonly":"\(readOnly)"])
			throw LMDBError(returnCode:createResult)
		}

		#if DEBUG
		assert(start_handle != nil, "a LMDB tx pointer should have been created")
		#endif
		
		mutateLogger[metadataKey:"mdb_txi_id"] = "[Transaction](\(start_handle!.hashValue))"
		mutateLogger?.info("init", metadata:["mdb_txi_parent_id":"n/a", "mdb_txi_readonly":"\(readOnly)"]) 
		txHandle = start_handle!
		logger = mutateLogger
	}
	#else
	/// creates a new transaction from an Environment and optional parent.
	public required init<E:MDB_env, T:MDB_tx>(env:UnsafePointer<E>, readOnly:Bool, txParent parent:UnsafePointer<T>) throws {
		let eh = env.pointer(to:.envHandle)!.pointee
		envHandle = eh
		readOnly = readOnly

		var start_handle:OpaquePointer? = nil
		let txnFlags = readOnly ? UInt32(MDB_RDONLY) : 0
		let createResult = mdb_txn_begin(eh, parent.pointer(to:.txHandle).pointee, txnFlags, &start_handle)
		guard createResult == 0 else {
			throw LMDBError(returnCode:createResult)
		}

		#if DEBUG
		assert(start_handle != nil, "a LMDB tx pointer should have been created")
		#endif
		txHandle = start_handle!
	}
	public required init<E:MDB_env>(env:UnsafePointer<E>, readOnly:Bool) throws {
		let eh = env.pointer(to:.envHandle)!.pointee
		envHandle = eh
		readOnly = readOnly

		var start_handle:OpaquePointer? = nil
		let txnFlags = readOnly ? UInt32(MDB_RDONLY) : 0
		let createResult = mdb_txn_begin(eh, nil, txnFlags, &start_handle)
		guard createResult == 0 else {
			throw LMDBError(returnCode:createResult)
		}

		#if DEBUG
		assert(start_handle != nil, "a LMDB tx pointer should have been created")
		#endif
		txHandle = start_handle!
	}
	#endif

    /// commit all the operations of a transaction into the database.
    /// - throws: this function will throw an ``LMDBError`` if the commit fails.
	public func commit() throws {
		#if QUICKLMDB_SHOULDLOG
		logger?.trace("committing...")
		#endif
		let commitResult = mdb_txn_commit(MDB_tx_handle)
		guard commitResult == 0 else {
			#if QUICKLMDB_SHOULDLOG
			logger?.error("commitment failed", metadata:["mdb_return_code":"\(commitResult)"])
			#endif
			throw LMDBError(returnCode:commitResult)
		}
		#if QUICKLMDB_SHOULDLOG
		logger?.info("commitment successful")
		#endif
		isOpen = false
	}
    
    /// resets a read-only transaction so that it may be renewed for later use.
	public func reset() {
		mdb_txn_reset(MDB_tx_handle)
		#if QUICKLMDB_SHOULDLOG
		logger?.debug("reset successful")
		#endif
	}
    
    /// Renews a read-only transaction that has been previously reset. This must be called before a reset transaction can be used again.
    /// - Throws: This function will throw an ``LMDBError`` if renewing fails.
	public func renew() throws {
		#if QUICKLMDB_SHOULDLOG
		logger?.trace("renewing...")
		#endif
		let renewResult = mdb_txn_renew(MDB_tx_handle)
		guard renewResult == 0 else {
			#if QUICKLMDB_SHOULDLOG
			logger?.error("renewal failed", metadata:["mdb_return_code":"\(commitResult)"])
			#endif
			throw LMDBError(returnCode:renewResult)
		}
		#if QUICKLMDB_SHOULDLOG
		logger?.debug("newal successful")
		#endif
    }
    
    /// Abandon all operations of the transaction.
	public func abort() {
		mdb_txn_abort(MDB_tx_handle)
		isOpen = false
		#if QUICKLMDB_SHOULDLOG
		logger?.info("abort successful")
		#endif
	}
	
	deinit {
		if isOpen == true {
			#if QUICKLMDB_SHOULDLOG
			logger?.notice("instance deinit but transaction was left open. the transaction will now be aborted")
			#endif
			mdb_txn_abort(MDB_tx_handle)
		} else {
			#if QUICKLMDB_SHOULDLOG
			logger?.trace("instance deinit")
			#endif
		}
	}
}
