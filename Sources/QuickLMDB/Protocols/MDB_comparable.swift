public protocol MDB_comparable {
	typealias MDB_compare_ftype = @convention(c) (UnsafePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Int32 
	static var MDB_compare_f:MDB_compare_ftype { get }
}