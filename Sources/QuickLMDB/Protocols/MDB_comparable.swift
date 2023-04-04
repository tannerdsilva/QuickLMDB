
public protocol MDB_comparable {
	typealias MDB_conpare_function = @convention(c) (UnsafePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Int32 
	static var mdbCompareFunction: MDB_conpare_function { get }
}