import CLMDB

/// the phantom transaction-mode marker. a transaction's mode lives in its
/// type: `Transaction<Read>` can never commit and `Transaction<Write>` can.
/// write-only members are gated on the mode, so writing on a read transaction
/// is a type-checker error — across direct verbs, joined callees, helper
/// parameters, and cursor writes.
///
/// the mode space is sealed: conforming requires the internal
/// ``TransactionMode/_mdb_modeReadOnly`` witness, so only ``Read`` and
/// ``Write`` can ever exist.
public protocol TransactionMode: Sendable {
	static var _mdb_modeReadOnly: Bool { get }
}

/// read-only transaction mode — a transaction that can never commit.
public struct Read: TransactionMode, Sendable {
	public static var _mdb_modeReadOnly: Bool { true }
}

/// read-write transaction mode — a transaction that can commit.
public struct Write: TransactionMode, Sendable {
	public static var _mdb_modeReadOnly: Bool { false }
}

public struct Transaction<M: TransactionMode>: ~Copyable {
	// the underlying pointer handle that LMDB uses to represent this transaction
	private let _tx_handle:OpaquePointer
	// whether this instance owns the underlying transaction (always true for values created via the public initializers; kept for the deinit guard)
	private let _isConsumerOwned:Bool
	// set to true once the transaction has been committed or aborted. prevents deinit from aborting a closed transaction.
	private var _didClose:Bool

	// designated initializer shared by all owning creation paths
	private init(_tx_handle:OpaquePointer, _isConsumerOwned:Bool, _didClose:Bool) {
		self._tx_handle = _tx_handle
		self._isConsumerOwned = _isConsumerOwned
		self._didClose = _didClose
	}

	/// creates a ROOT transaction. the mode rides on the type:
	/// `Transaction<Read>(env:)` / `Transaction<Write>(env:)`.
	@available(*, noasync)
	public init(env:Environment) throws(LMDBError) {
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.envHandle(), nil, (M._mdb_modeReadOnly ? UInt32(MDB_RDONLY) : 0), &startHandle)
		guard createResult == 0 else {
			let errThrown = LMDBError(returnCode:createResult)
			throw errThrown
		}
		self.init(_tx_handle:startHandle!, _isConsumerOwned:true, _didClose:false)
	}

	@available(*, noasync)
	public consuming func abort() {
		mdb_txn_abort(_tx_handle)
		self._didClose = true
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
		// only abort the underlying transaction if this instance owns it and it has not already been closed
		if _isConsumerOwned && !_didClose {
			mdb_txn_abort(_tx_handle)
		}
	}
}

extension Transaction where M == Write {

	/// creates a CHILD transaction of `parent`. the engine permits one active
	/// child per parent; a child commit merges into the parent. children are
	/// write-capable only (read children are engine-invalid), so this
	/// initializer exists exclusively on ``Transaction``/``Write``.
	@available(*, noasync)
	public init(env:borrowing Environment, parent:borrowing Transaction<Write>) throws(LMDBError) {
		var startHandle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.envHandle(), parent._tx_handle, 0, &startHandle)
		guard createResult == 0 else {
			let errThrown = LMDBError(returnCode:createResult)
			throw errThrown
		}
		self.init(_tx_handle:startHandle!, _isConsumerOwned:true, _didClose:false)
	}

	/// commits the transaction. write-capable transactions only — a read
	/// transaction has no `commit()` member at all.
	@available(*, noasync)
	public consuming func commit() throws(LMDBError) {
		let commitResult = mdb_txn_commit(_tx_handle)
		guard commitResult == 0 else {
			discard self
			throw LMDBError(returnCode:commitResult)
		}
		// mark closed so deinit does not abort an already-committed transaction
		self._didClose = true
		discard self
	}
}
