import CLMDB

/// `Transactable` protocol defines how transactions and subtransactions are created.
public protocol Transactable {
	func transact<R>(readOnly:Bool, _ txFunc:(Transaction) throws -> R) throws -> R
}
