import RAW

/// the type of function that LMDB uses to combine keys and values in the database.
public typealias MDB_compare_ftype = @convention(c) (UnsafePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Int32 

/// a protocol that specifies a type that can be compared using LMDB's comparison functions.
public protocol MDB_comparable:RAW_comparable {
	
	/// the LMDB comparison function for this type. as a c convention function, it cannot be defined in a protocol as a normal function, so it must be expressed as a static stored variable of a function type.
	static var MDB_compare_f:MDB_compare_ftype { get }
}