import CLMDB

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

public struct Transaction:~Copyable {
	// the underlying pointer handle that LMDB uses to represent this transaction
	private let _tx_handle:OpaquePointer
	
	#if QUICKLMDB_SHOULDLOG
	let logger:Logger?
	#endif
	
	// init no parent [LOGGED]
	@available(*, noasync)
	public init(env:borrowing Environment, readOnly:Bool) throws(LMDBError) {
		#if QUICKLMDB_SHOULDLOG
		var logger = env.logger()
		logger?[metadataKey:"type"] = "\(String(describing:Self.self))"
		#endif
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.envHandle(), nil, (readOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			let errThrown = LMDBError(returnCode:createResult)
			#if QUICKLMDB_SHOULDLOG
			logger?.error("init", metadata:["mdb_return_code": "\(createResult)", "throwing":"\(String(describing:errThrown))"])
			#endif
			throw errThrown
		}
		#if QUICKLMDB_SHOULDLOG
		logger?[metadataKey:"tx_id"] = "\(startHandle!.hashValue)"
		logger?[metadataKey:"tx_readonly"] = "\(readOnly)"
		logger?.debug("init")
		self.logger = logger
		#endif
		self._tx_handle = startHandle!
	}
	// init with parent [LOGGED]
	@available(*, noasync)
	public init(env:borrowing Environment, readOnly:Bool, parent:borrowing Transaction) throws(LMDBError) {
		#if QUICKLMDB_SHOULDLOG
		var logger = env.logger()
		logger?[metadataKey:"type"] = "\(String(describing:Self.self))"
		logger?[metadataKey:"id_tx_parent"] = "\(parent._tx_handle.hashValue)"
		#endif
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.envHandle(), parent._tx_handle, (readOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			let errThrown = LMDBError(returnCode:createResult)
			#if QUICKLMDB_SHOULDLOG
			logger?.error("init", metadata:["mdb_return_code": "\(createResult)", "throwing":"\(String(describing:errThrown))"])
			#endif 
			throw errThrown
		}
		#if QUICKLMDB_SHOULDLOG
		logger?[metadataKey:"tx_id"] = "\(startHandle!.hashValue)"
		logger?[metadataKey:"tx_readonly"] = "\(readOnly)"
		logger?.debug("init")
		self.logger = logger
		#endif
		self._tx_handle = startHandle!
	}
	
	@available(*, noasync)
	public consuming func commit() throws(LMDBError) {
		#if QUICKLMDB_SHOULDLOG
		logger?.trace("committing...")
		#endif
		let commitResult = mdb_txn_commit(_tx_handle)
		guard commitResult == 0 else {
			#if QUICKLMDB_SHOULDLOG
			logger?.error("commit failed")
			#endif
			discard self
			throw LMDBError(returnCode:commitResult)
		}
		#if QUICKLMDB_SHOULDLOG
		logger?.info("commit successful")
		#endif
		discard self
	}

	@available(*, noasync)
	public consuming func abort() {
		mdb_txn_abort(_tx_handle)
		#if QUICKLMDB_SHOULDLOG
		logger?.info("abort successful")
		#endif
		discard self
	}

	@available(*, noasync)
	public borrowing func reset() {
		mdb_txn_reset(_tx_handle)
		#if QUICKLMDB_SHOULDLOG
		logger?.debug("reset successful")
		#endif
	}

	
	@available(*, noasync)
	public borrowing func renew() throws(LMDBError) {
		#if QUICKLMDB_SHOULDLOG
		logger?.trace("renewing...")
		#endif
		let renewResult = mdb_txn_renew(_tx_handle)
		guard renewResult == 0 else {
			#if QUICKLMDB_SHOULDLOG
			logger?.error("renewal failed")
			#endif
			throw LMDBError(returnCode:renewResult)
		}
		#if QUICKLMDB_SHOULDLOG
		logger?.debug("renewal successful")
		#endif
    }
    
    /// returns the LMDB primitive type that LMDB uses to reference this transaction
    @available(*, noasync)
    internal borrowing func txHandle() -> OpaquePointer {
    	return _tx_handle
    }

	deinit {
		mdb_txn_abort(_tx_handle)
	}
}
