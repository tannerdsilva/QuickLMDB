import RAW

public protocol MDB_checksum_impl {
	associatedtype MDB_checksum_outputtype:RAW_staticbuff
	typealias MDB_checksum_ftype = @convention(c)(UnsafePointer<MDB_val>?, UnsafeMutablePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Void
	static var MDB_sum_f:MDB_checksum_ftype { get }
}