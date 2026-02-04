import RAW

public protocol MDB_crypto_impl {
	associatedtype MDB_crypto_impl_keytype:RAW_staticbuff
	associatedtype MDB_crypto_impl_authtype:RAW_staticbuff
	typealias MDB_crypto_impl_ftype = @convention(c)(UnsafePointer<MDB_val>?, UnsafeMutablePointer<MDB_val>?, UnsafePointer<MDB_val>?, Int32) -> Int32
	static var MDB_crypto_f:MDB_crypto_impl_ftype { get }
}