import CLMDB

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

public struct Transaction:~Copyable {
	// the underlying pointer handle that LMDB uses to represent this transaction
	private let _tx_handle:OpaquePointer
	
	#if QUICKLMDB_SHOULDLOG
	// init no parent [LOGGED]
	public init(env:borrowing Environment, readOnly:Bool) throws(LMDBError) {
		let logger = env.logger()
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.envHandle(), nil, (readOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			let errThrown = LMDBError(returnCode:createResult)
			logger?.error("init", metadata:["type":"tx", "mdb_return_code": "\(createResult)", "_throwing":"\(String(describing:errThrown))"])
			throw errThrown
		}
		logger?.debug("init", metadata:["type":"tx", "id_tx":"\(startHandle!.hashValue)", "tx_readonly":"\(readOnly)"])
		self._tx_handle = startHandle!
	}
	// init with parent [LOGGED]
	public init(env:borrowing Environment, readOnly:Bool, parent:borrowing Transaction) throws(LMDBError) {
		var logger = env.logger()
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.envHandle(), parent._tx_handle, (readOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			let errThrown = LMDBError(returnCode:createResult)
			logger?.error("init", metadata:["type":"tx", "id_tx_parent":"\(parent._tx_handle.hashValue)", "mdb_return_code": "\(createResult)", "_throwing":"\(String(describing:errThrown))"])
			throw errThrown
		}
		logger?.debug("init", metadata:["type":"tx", "id_tx":"\(startHandle!.hashValue)", "id_tx_parent":"\(parent._tx_handle.hashValue)", "tx_readonly":"\(readOnly)"])
		self._tx_handle = startHandle!
	}
	#else
	// init no parent
	public init(env:borrowing Environment, readOnly:Bool) throws(LMDBError) {
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.envHandle(), nil, (readOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			throw LMDBError(returnCode:createResult)
		}
		self._tx_handle = startHandle!
	}
	// init with parent
	public init(env:borrowing Environment, readOnly:Bool, parent:borrowing Transaction) throws(LMDBError) {
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.envHandle(), parent._tx_handle, (readOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			throw LMDBError(returnCode:createResult)
		}
		self._tx_handle = startHandle!
	}
	#endif
	
	#if QUICKLMDB_SHOULDLOG
	public consuming func commit(logger _logger:Logger? = nil) throws(LMDBError) {
		_logger?.trace("committing...", metadata:["type":"tx", "id_tx":"\(_tx_handle.hashValue)"])
		let commitResult = mdb_txn_commit(_tx_handle)
		guard commitResult == 0 else {
			_logger?.error("commitment failed", metadata:["type":"tx", "id_tx":"\(_tx_handle.hashValue)", "mdb_return_code":"\(commitResult)"])
			discard self
			throw LMDBError(returnCode:commitResult)
		}
		_logger?.info("commitment successful", metadata:["type":"tx", "id_tx":"\(_tx_handle.hashValue)"])
		discard self
	}
	#else
	public consuming func commit() throws(LMDBError) {
		let commitResult = mdb_txn_commit(_tx_handle)
		guard commitResult == 0 else {
			discard self
			throw LMDBError(returnCode:commitResult)
		}
		discard self
	}
	#endif

	#if QUICKLMDB_SHOULDLOG
	public consuming func abort(logger _logger:Logger? = nil) {
		mdb_txn_abort(_tx_handle)
		_logger?.info("abort successful", metadata:["type":"tx", "id_tx":"\(_tx_handle.hashValue)"])
		discard self
	}
	#else
	public consuming func abort() {
		mdb_txn_abort(_tx_handle)
		discard self
	}
	#endif

	#if QUICKLMDB_SHOULDLOG
	public borrowing func reset(logger _logger:Logger? = nil) {
		mdb_txn_reset(_tx_handle)
		_logger?.debug("reset successful", metadata:["type":"tx", "id_tx":"\(_tx_handle.hashValue)"])
	}
	#else
	public borrowing func reset() {
		mdb_txn_reset(_tx_handle)
	}
	#endif
	
	#if QUICKLMDB_SHOULDLOG
	public borrowing func renew(logger _logger:Logger? = nil) throws(LMDBError) {
		_logger?.trace("renewing...")
		let renewResult = mdb_txn_renew(_tx_handle)
		guard renewResult == 0 else {
			_logger?.error("renewal failed", metadata:["mdb_return_code":"\(renewResult)"])
			throw LMDBError(returnCode:renewResult)
		}
		_logger?.debug("renewal successful")
    }
    #else
	public borrowing func renew() throws(LMDBError) {
		let renewResult = mdb_txn_renew(_tx_handle)
		guard renewResult == 0 else {
			throw LMDBError(returnCode:renewResult)
		}
    }
    #endif
    
    /// returns the LMDB primitive type that  
    internal borrowing func txHandle() -> OpaquePointer {
    	return _tx_handle
    }

	deinit {
		mdb_txn_abort(_tx_handle)
	}
}
