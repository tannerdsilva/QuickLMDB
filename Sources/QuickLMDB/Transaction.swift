import CLMDB

public struct Transaction:~Copyable {
	// the underlying pointer handle that LMDB uses to represent this transaction
	private let _tx_handle:OpaquePointer
	
	// init no parent
	@available(*, noasync)
	public init(env:Environment, readOnly:Bool) throws(LMDBError) {
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.envHandle(), nil, (readOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			let errThrown = LMDBError(returnCode:createResult)
			throw errThrown
		}
		self._tx_handle = startHandle!
	}
	
	// init with parent [LOGGED]
	@available(*, noasync)
	public init(env:borrowing Environment, readOnly:Bool, parent:borrowing Transaction) throws(LMDBError) {
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.envHandle(), parent._tx_handle, (readOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			let errThrown = LMDBError(returnCode:createResult)
			throw errThrown
		}
		self._tx_handle = startHandle!
	}
	
	@available(*, noasync)
	public consuming func commit() throws(LMDBError) {
		let commitResult = mdb_txn_commit(_tx_handle)
		guard commitResult == 0 else {
			discard self
			throw LMDBError(returnCode:commitResult)
		}
		discard self
	}

	@available(*, noasync)
	public consuming func abort() {
		mdb_txn_abort(_tx_handle)
		discard self
	}

	@available(*, noasync)
	public borrowing func reset() {
		mdb_txn_reset(_tx_handle)
	}

	
	@available(*, noasync)
	public borrowing func renew() throws(LMDBError) {
		let renewResult = mdb_txn_renew(_tx_handle)
		guard renewResult == 0 else {
			throw LMDBError(returnCode:renewResult)
		}
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
