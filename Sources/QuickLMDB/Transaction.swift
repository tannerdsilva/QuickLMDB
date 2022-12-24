import CLMDB

public class Transaction:Transactable {

	///Pointer to the `MDB_env` that an instance is associated with.
	public let env_handle:OpaquePointer?
	
	///Pointer to the `MDB_txn` struct associated with a given instance.
	public var txn_handle:OpaquePointer?
	
	/// Indicates if a given instance is a read-only transaction.
	public let readOnly:Bool
	
	internal var isOpen = true
	
	internal static func instantTransaction<R>(environment:OpaquePointer?, readOnly:Bool, parent:OpaquePointer?, _ handler:(Transaction) throws -> R) throws -> R {
		let newTransaction = try Transaction(environment:environment, readOnly:readOnly, parent:parent)
		let captureReturn:R
		do {
			captureReturn = try handler(newTransaction)
		} catch let error {
			if newTransaction.isOpen == true {
				newTransaction.abort()
			}
			throw error
		}
		if newTransaction.isOpen == true {
			try newTransaction.commit()
		}
		return captureReturn
	}
	
	/// Creates a new transaction from an Environment and optional parent.
	convenience init(environment:Environment, readOnly:Bool, parent:Transaction? = nil) throws {
		try self.init(environment:environment.env_handle, readOnly:readOnly, parent:parent?.env_handle)
	}
	
	required internal init(environment env_handle:OpaquePointer?, readOnly:Bool, parent:OpaquePointer? = nil) throws {
		self.env_handle = env_handle
		self.readOnly = readOnly
		var start_handle:OpaquePointer? = nil
		var flags:UInt32  = 0
		if (readOnly == true) {
			flags = UInt32(MDB_RDONLY)
		}
		let createResult = mdb_txn_begin(env_handle, parent, flags, &start_handle)
		guard createResult == 0 else {
			throw LMDBError(returnCode:createResult)
		}
		self.txn_handle = start_handle
	}
	
	///Transactable conformance
	@discardableResult public func transact<R>(readOnly: Bool, _ txFunc: (Transaction) throws -> R) throws -> R {
		let newTransaction = try Transaction(environment:self.env_handle, readOnly:readOnly, parent:self.txn_handle)
		let captureReturn:R
		do {
			captureReturn = try txFunc(newTransaction)
		} catch let error {
			if newTransaction.isOpen == true {
				newTransaction.abort()
			}
			throw error
		}
		if newTransaction.isOpen == true {
			try newTransaction.commit()
		}
		return captureReturn
	}
	
    /// Commit all the operations of a transaction into the database.
    /// - Throws: This function will throw an ``LMDBError`` if the commit fails.
	public func commit() throws {
		let commitResult = mdb_txn_commit(txn_handle)
		guard commitResult == 0 else {
			throw LMDBError(returnCode:commitResult)
		}
		self.isOpen = false
	}
    
    /// Resets a read-only transaction so that it may be renewed for later use.
	public func reset() {
		mdb_txn_reset(txn_handle)
	}
    
    /// Renews a read-only transaction that has been previously reset. This must be called before a reset transaction can be used again.
    /// - Throws: This function will throw an ``LMDBError`` if renewing fails.
	public func renew() throws {
		let renewResult = mdb_txn_renew(txn_handle)
		guard renewResult == 0 else {
			throw LMDBError(returnCode:renewResult)
		}
    }
    
    /// Abandon all operations of the transaction. Frees the transaction.
	public func abort() {
		mdb_txn_abort(txn_handle)
		self.isOpen = false
	}
	
	deinit {
		if self.isOpen == true {
			mdb_txn_abort(txn_handle)
		}
	}
}
