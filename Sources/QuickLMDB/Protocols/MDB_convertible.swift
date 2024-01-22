/// This typealias defines a protocol that is both encodable and decodable from the database.
public typealias MDB_convertible = MDB_encodable & MDB_decodable

/// This protocol defines how data is deserialized from the database
public protocol MDB_decodable {
	/// Initialize a type by copying the data from a specified `MDB_val`. Types that are initialized in this way may be freely moved and copied independently of the `Transaction` in which they were created.
	init?(_ value:MDB_val)
}

/// This protocol defines how data is serialized into the database
public protocol MDB_encodable {
	/// Export a type into an `MDB_val`. The respective mutable `MDB_val` is passed into a function that is intended to handle the exported value.
	func asMDB_val<R>(_ valFunc:(inout MDB_val) throws -> R) rethrows -> R
}
