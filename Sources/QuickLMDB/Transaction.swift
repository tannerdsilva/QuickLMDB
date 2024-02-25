import CLMDB

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

// public protocol MDB_tx:CustomDebugStringConvertible {
// 	associatedtype MDB_tx_env_type:MDB_env

// 	/// the environment handle primitive that LMDB uses.
// 	var env:MDB_tx_env_type { get }
// 	/// the transaction handle primitive that LMDB uses to represent this instance.
// 	var handle:OpaquePointer { get }
// 	/// indicates if the transaction is read-only.
// 	var readOnly:Bool { get }

// 	#if QUICKLMDB_SHOULDLOG
// 	/// logging facilites for the transaction instance
// 	var logger:Logger? { get }
// 	/// creates a new child transaction given the specified env handle and parent tx handle.
// 	init(env:borrowing MDB_tx_env_type, readOnly:Bool, parent:borrowing Self, logger:consuming Logger?) throws
// 	/// creates a new root transaction given the specified env handle.
// 	init(env:borrowing MDB_tx_env_type, readOnly:Bool, logger:consuming Logger?) throws
	
// 	#else
	
// 	/// creates a new child transaction given the specified env handle and parent tx handle.
// 	init(env:borrowing MDB_tx_env_type, readOnly:Bool, parent:borrowing Self) throws
// 	/// creates a new root transaction given the specified env handle.
// 	init(env:borrowing MDB_tx_env_type, readOnly:Bool) throws
	
// 	#endif
	
// 	/// commits the transaction.
// 	mutating func commit() throws
// 	/// resets the transaction.
// 	mutating func reset()
// 	/// renews the transaction.
// 	mutating func renew() throws
// 	/// aborts the transaction.
// 	mutating func abort()
// }

// // default implementation of debug descriptions for the environment
// extension MDB_tx where Self:CustomDebugStringConvertible {
// 	/// the debug description of the LMDB transaction instance
// 	public var debugDescription:String {
// 		return "[\(String(describing:type(of:self)))](\(handle.hashValue))"
// 	}
// }

// extension MDB_tx {
// 	public typealias MDB_tx_parent_type = Self

// 	/// borrows the contents of the transactions and returns a copy of the primitive handle pointer that represents this instance.
// 	public borrowing func handle() -> OpaquePointer {
// 		return handle
// 	}
// }

public struct MDB_tx:~Copyable {
	public let handle:OpaquePointer
}

public final class Transaction {

	/// pointer to the `MDB_env` that an instance is associated with.
	public let env:Environment
	/// pointer to the `MDB_txn` struct associated with a given instance.
	public let handle:MDB_tx
	/// indicates if a given instance is a read-only transaction.
	public let readOnly:Bool

	private let parent:ChildType
	
	/// tracks if the transaction is open or not.
	private var isOpen = true

}

extension Transaction {
	public init(env:borrowing Environment, readOnly:Bool, parent:consuming Transaction) throws {
		var start_handle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.handle, nil, (readOnly ? UInt32(MDB_RDONLY) : 0), &start_handle)
		guard createResult == 0 else {
			throw LMDBError(returnCode:createResult)
		}
		self.handle = start_handle!
		self.env = copy env
		self.readOnly = readOnly
		self.parent = (parent.handle, parent.readOnly)
	}
}
	public init(env:borrowing Environment, readOnly:Bool) throws {
		var start_handle:OpaquePointer? = nil
		let createResult = mdb_txn_begin(env.handle, nil, (readOnly ? UInt32(MDB_RDONLY) : 0), &start_handle)
		guard createResult == 0 else {
			throw LMDBError(returnCode:createResult)
		}
		self.handle = start_handle!
		self.env = copy env
		self.readOnly = readOnly
		self.parent = nil
	}

	deinit {
		if isOpen == true {
			#if QUICKLMDB_SHOULDLOG
			logger?.notice("instance deinit but transaction was left open. the transaction will now be aborted")
			#endif
			mdb_txn_abort(handle)
		} else {
			#if QUICKLMDB_SHOULDLOG
			logger?.trace("instance deinit")
			#endif
		}
	}
}

	// #if QUICKLMDB_SHOULDLOG
	// internal let logger:Logger?
	// public init(env:borrowing Environment, readOnly:Bool, logger mutateLogger:consuming Logger? = nil) throws {
	// 	mutateLogger?[metadataKey:"type"] = "Transaction"
		
	// 	var start_handle:OpaquePointer? = nil
	// 	mutateLogger?.trace("initializing LMDB tx instance (no parent)", metadata:["mdb_txi_parent_id":"n/a", "mdb_txi_readonly":"\(readOnly)"])
		
	// 	let createResult = mdb_txn_begin(env.handle, nil, (readOnly ? UInt32(MDB_RDONLY) : 0), &start_handle)
	// 	guard createResult == 0 else {
	// 		mutateLogger?.critical("unable to create LMDB tx instance (no parent)", metadata:["mdb_txi_parent_id":"n/a", "mdb_return_code":"\(createResult)", "mdb_txi_readonly":"\(readOnly)"])
	// 		throw LMDBError(returnCode:createResult)
	// 	}

	// 	#if DEBUG
	// 	assert(start_handle != nil, "a LMDB tx pointer should have been created")
	// 	#endif
		
	// 	mutateLogger?[metadataKey:"mdb_txi_id"] = "[Transaction](\(start_handle!.hashValue))"
	// 	mutateLogger?.info("init", metadata:["mdb_txi_parent_id":"n/a", "mdb_txi_readonly":"\(readOnly)"]) 
		
	// 	self.handle = start_handle!
	// 	self.logger = mutateLogger
	// 	self.parent = nil
	// 	self.env = copy env
	// 	self.readOnly = readOnly
	// }
	// #else

extension Transaction {

    /// commit all the operations of a transaction into the database.
    /// - throws: this function will throw an ``LMDBError`` if the commit fails.
	public mutating func commit() throws {
		#if QUICKLMDB_SHOULDLOG
		logger?.trace("committing...")
		#endif
		let commitResult = mdb_txn_commit(handle)
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
	public borrowing func reset() {
		guard isOpen == true else {
			#if QUICKLMDB_SHOULDLOG
			logger?.warning("reset called on a closed transaction. this is a no-op")
			#endif
			fatalError("cannot reset a closed transaction")
		}
		guard readOnly == true else {
			#if QUICKLMDB_SHOULDLOG
			logger?.warning("reset called on a read-write transaction. this is a no-op")
			#endif
			fatalError("cannot reset a read-write transaction")
		}
		mdb_txn_reset(handle)
		#if QUICKLMDB_SHOULDLOG
		logger?.debug("reset successful")
		#endif
	}
    
    /// Renews a read-only transaction that has been previously reset. This must be called before a reset transaction can be used again.
    /// - Throws: This function will throw an ``LMDBError`` if renewing fails.
	public borrowing func renew() throws {
		#if QUICKLMDB_SHOULDLOG
		logger?.trace("renewing...")
		#endif
		let renewResult = mdb_txn_renew(handle)
		guard renewResult == 0 else {
			#if QUICKLMDB_SHOULDLOG
			logger?.error("renewal failed", metadata:["mdb_return_code":"\(commitResult)"])
			#endif
			throw LMDBError(returnCode:renewResult)
		}
		#if QUICKLMDB_SHOULDLOG
		logger?.debug("renewal successful")
		#endif
    }
    
    /// Abandon all operations of the transaction.
	public mutating func abort() {
		isOpen = false
		mdb_txn_abort(handle)
		#if QUICKLMDB_SHOULDLOG
		logger?.info("abort successful")
		#endif
	}
}
