import CLMDB

/// `Transactable` protocol defines how transactions and subtransactions are created.
public protocol Transactable {
	var env_handle:OpaquePointer? { get }
	func transact<R>(readOnly:Bool, _ txFunc:(Transaction) throws -> R) throws -> R
}
