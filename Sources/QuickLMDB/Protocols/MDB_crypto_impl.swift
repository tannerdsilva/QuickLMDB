import RAW
import RAW_chachapoly

public protocol MDB_crypto_impl {
	typealias MDB_crypto_impl_ftype = @convention(c)(UnsafePointer<MDB_val>?, UnsafeMutablePointer<MDB_val>?, UnsafePointer<MDB_val>?, Int32) -> Int32
	static var MDB_crypto_f:MDB_crypto_impl_ftype { get }
}

public struct ChaChaPoly:MDB_crypto_impl {
	public static let MDB_crypto_f:MDB_crypto_impl_ftype = { (a,b,c,d) in
		return 0
	}
}

public protocol MDB_checksum_impl {
	typealias MDB_checksum_ftype = @convention(c)(UnsafePointer<MDB_val>?, UnsafeMutablePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Void
	static var MDB_sum_f:MDB_checksum_ftype { get }
}