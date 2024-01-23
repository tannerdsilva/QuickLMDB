import CLMDB

public protocol MDB_tx {
	/// the environment handle primitive that LMDB uses.
	var MDB_env_handle:OpaquePointer { get }
	/// the transaction handle primitive that LMDB uses.
	var MDB_tx_handle:OpaquePointer { get }
	/// indicates if the transaction is read-only.
	var MDB_tx_readOnly:Bool { get }

	/// creates a new instant transaction given the specified env handle and tx handle. the newly created transaction is accessible by a handler function.
	/// - parameters:
	/// 	- MDB_env: the environment handle primitive that LMDB uses.
	/// 	- readOnly: indicates if the newly created transaction shall be read-only.
	/// 	- parent: an optional parent transaction. if this is not nil, the transaction will be a child transaction. this is only evaluated if readOnly is false, since child transactions cannot be read-only.
	/// 	- handler: the handler function that will be called with the newly created transaction.
	static func MDB_tx_instant<E:MDB_env, R>(MDB_env:E, readOnly:Bool, parent:OpaquePointer?, _ handler:(UnsafePointer<Self>) throws -> R) rethrows -> R

	/// creates a new transaction given the specified env handle and tx handle.
	init(MDB_env_handle:OpaquePointer, readOnly:Bool, parent_tx_handle:OpaquePointer?) throws

	/// commits the transaction.
	func commit() throws
	/// resets the transaction.
	func reset()
	/// renews the transaction.
	func renew() throws
	/// aborts the transaction.
	func abort()
}

extension MDB_tx {
	public static func MDB_tx_instant<E:MDB_env, R>(MDB_env:E, readOnly:Bool, parent:OpaquePointer?, _ handler:(UnsafePointer<Self>) throws -> R) rethrows -> R {
		var newTransaction = try! Self.init(MDB_env_handle:MDB_env.MDB_env_handle, readOnly:readOnly, parent_tx_handle:parent)
		let captureReturn:R
		do {
			captureReturn = try handler(&newTransaction)
		} catch let error {
			if newTransaction.MDB_tx_readOnly == false {
				newTransaction.abort()
			}
			throw error
		}
		if newTransaction.MDB_tx_readOnly == false {
			try! newTransaction.commit()
		}
		return captureReturn
	}
}

public final class Transaction:MDB_tx {
	/// pointer to the `MDB_env` that an instance is associated with.
	public let MDB_env_handle:OpaquePointer
	
	/// pointer to the `MDB_txn` struct associated with a given instance.
	public let MDB_tx_handle:OpaquePointer
	
	/// indicates if a given instance is a read-only transaction.
	public let MDB_tx_readOnly:Bool
	
	/// tracks if the transaction is open or not.
	private var isOpen = true

	/// creates a new transaction from an Environment and optional parent.
	public required init(MDB_env_handle:OpaquePointer, readOnly:Bool, parent_tx_handle:OpaquePointer?) throws {
		self.MDB_env_handle = MDB_env_handle
		self.MDB_tx_readOnly = readOnly
		var start_handle:OpaquePointer? = nil
		let txnFlags = readOnly ? UInt32(MDB_RDONLY) : 0
		let createResult = mdb_txn_begin(MDB_env_handle, nil, txnFlags, &start_handle)
		guard createResult == 0 else {
			throw LMDBError(returnCode:createResult)
		}
		self.MDB_tx_handle = start_handle!
	}

    /// commit all the operations of a transaction into the database.
    /// - throws: this function will throw an ``LMDBError`` if the commit fails.
	public func commit() throws {
		let commitResult = mdb_txn_commit(MDB_tx_handle)
		guard commitResult == 0 else {
			throw LMDBError(returnCode:commitResult)
		}
		isOpen = false
	}
    
    /// Resets a read-only transaction so that it may be renewed for later use.
	public func reset() {
		mdb_txn_reset(MDB_tx_handle)
	}
    
    /// Renews a read-only transaction that has been previously reset. This must be called before a reset transaction can be used again.
    /// - Throws: This function will throw an ``LMDBError`` if renewing fails.
	public func renew() throws {
		let renewResult = mdb_txn_renew(MDB_tx_handle)
		guard renewResult == 0 else {
			throw LMDBError(returnCode:renewResult)
		}
    }
    
    /// Abandon all operations of the transaction. Frees the transaction.
	public func abort() {
		mdb_txn_abort(MDB_tx_handle)
		isOpen = false
	}
	
	deinit {
		if isOpen == true {
			mdb_txn_abort(MDB_tx_handle)
		}
	}
}
