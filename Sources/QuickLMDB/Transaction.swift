import CLMDB

public class Transaction:Transactable {
	public let env_handle:OpaquePointer?
	public var txn_handle:OpaquePointer?
	
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
			try! newTransaction.commit()
		}
		return captureReturn
	}
	
	internal init(environment env_handle:OpaquePointer?, readOnly:Bool, parent:OpaquePointer? = nil) throws {
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
	public func transact<R>(readOnly: Bool, _ txFunc: (Transaction) throws -> R) throws -> R {
		let newTransaction = try Transaction(environment:self.env_handle, readOnly:readOnly, parent: self.txn_handle)
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
	
	/*
	Actions that can be taken on a transaction object.
	*/
	public func commit() throws {
		let commitResult = mdb_txn_commit(txn_handle)
		guard commitResult == 0 else {
			throw LMDBError(returnCode:commitResult)
		}
		self.isOpen = false
	}
	public func reset() {
		mdb_txn_reset(txn_handle)
	}
	public func renew() throws {
		let renewResult = mdb_txn_renew(txn_handle)
		guard renewResult == 0 else {
			throw LMDBError(returnCode:renewResult)
		}
	}
	public func abort() {
		mdb_txn_abort(txn_handle)
		self.isOpen = false
	}
}
