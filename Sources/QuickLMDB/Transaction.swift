import CLMDB

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

public struct Transaction:~Copyable {
	// the underlying pointer handle that LMDB uses to represent this transaction
	private let _handle:OpaquePointer
	
	#if QUICKLMDB_SHOULDLOG
	// init no parent [LOGGED]
	internal init(env:borrowing Environment, readOnly:Bool, logger:Logger?) throws {
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.handle(), nil, (readOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			let errThrown = LMDBError(returnCode:createResult)
			logger?.error("init", metadata:["type":"tx", "mdb_return_code": "\(createResult)", "_throwing":"\(String(describing:errThrown))"])
			throw errThrown
		}
		logger?.debug("init", metadata:["type":"tx", "id_tx":"\(startHandle!.hashValue)", "tx_readonly":"\(readOnly)"])
		self._handle = startHandle!
	}
	// init with parent [LOGGED]
	internal init(env:borrowing Environment, readOnly:Bool, parent:borrowing Transaction, logger:Logger?) throws {
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.handle(), parent._handle, (readOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			let errThrown = LMDBError(returnCode:createResult)
			logger?.error("init", metadata:["type":"tx", "id_tx_parent":"\(parent._handle.hashValue)", "mdb_return_code": "\(createResult)", "_throwing":"\(String(describing:errThrown))"])
			throw errThrown
		}
		logger?.debug("init", metadata:["type":"tx", "id_tx":"\(startHandle!.hashValue)", "id_tx_parent":"\(parent._handle.hashValue)", "tx_readonly":"\(readOnly)"])
		self._handle = startHandle!
	}
	#else
	// init no parent
	internal init(env:borrowing Environment, readOnly:Bool) throws {
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.handle(), nil, (readOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			throw LMDBError(returnCode:createResult)
		}
		self._handle = startHandle!
	}
	// init with parent
	internal init(env:borrowing Environment, readOnly:Bool, parent:borrowing Transaction) throws {
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.handle(), parent._handle, (readOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			throw LMDBError(returnCode:createResult)
		}
		self._handle = startHandle!
	}
	#endif
	
	#if QUICKLMDB_SHOULDLOG
	public consuming func commit(logger _logger:Logger?) throws {
		_logger?.trace("committing...", metadata:["type":"tx", "id_tx":"\(_handle.hashValue)"])
		let commitResult = mdb_txn_commit(_handle)
		guard commitResult == 0 else {
			_logger?.error("commitment failed", metadata:["type":"tx", "id_tx":"\(_handle.hashValue)", "mdb_return_code":"\(commitResult)"])
			discard self
			throw LMDBError(returnCode:commitResult)
		}
		_logger?.info("commitment successful", metadata:["type":"tx", "id_tx":"\(_handle.hashValue)"])
		discard self
	}
	#else
	public consuming func commit() throws {
		let commitResult = mdb_txn_commit(_handle)
		guard commitResult == 0 else {
			discard self
			throw LMDBError(returnCode:commitResult)
		}
		discard self
	}
	#endif

	#if QUICKLMDB_SHOULDLOG
	public consuming func abort(logger _logger:Logger?) {
		mdb_txn_abort(_handle)
		_logger?.info("abort successful", metadata:["type":"tx", "id_tx":"\(_handle.hashValue)"])
		discard self
	}
	#else
	public consuming func abort() {
		mdb_txn_abort(_handle)
		discard self
	}
	#endif

	#if QUICKLMDB_SHOULDLOG
	public borrowing func reset(logger _logger:Logger?) {
		mdb_txn_reset(_handle)
		_logger?.debug("reset successful", metadata:["type":"tx", "id_tx":"\(_handle.hashValue)"])
	}
	#else
	public borrowing func reset() {
		mdb_txn_reset(_handle)
	}
	#endif
	
	#if QUICKLMDB_SHOULDLOG
	public borrowing func renew(logger _logger:Logger?) throws {
		_logger?.trace("renewing...")
		let renewResult = mdb_txn_renew(_handle)
		guard renewResult == 0 else {
			_logger?.error("renewal failed", metadata:["mdb_return_code":"\(renewResult)"])
			throw LMDBError(returnCode:renewResult)
		}
		_logger?.debug("renewal successful")
    }
    #else
	public borrowing func renew() throws {
		let renewResult = mdb_txn_renew(_handle)
		guard renewResult == 0 else {
			throw LMDBError(returnCode:renewResult)
		}
    }
    #endif
    
    internal borrowing func handle() -> OpaquePointer {
    	return _handle
    }

	deinit {
		mdb_txn_abort(_handle)
	}
}
