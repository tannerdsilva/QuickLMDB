
public protocol MDB_comparable {
	typealias MDB_compare_function = @convention(c) (UnsafePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Int32 
	static var mdbCompareFunction: MDB_compare_function { get }
}