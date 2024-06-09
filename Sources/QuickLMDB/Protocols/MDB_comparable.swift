import RAW

public protocol MDB_comparable:RAW_comparable {
	// (const MDB_val *a, const MDB_val *b)
	typealias MDB_compare_ftype = @convention(c) (UnsafePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Int32 
	static var MDB_compare_f:MDB_compare_ftype { get }
}

public protocol MDB_encryption_provider {
	// (const MDB_val *src, MDB_val *dst, const MDB_val *key, int encdec);
	typealias MDB_encrypt_ftype = @convention(c) (UnsafePointer<MDB_val>?, UnsafeMutablePointer<MDB_val>?, UnsafePointer<MDB_val>?, Int32) -> Int32
	static var MDB_encrypt_f:MDB_encrypt_ftype { get }
}

public protocol MDB_checksum_provider {
	// (const MDB_val *src, MDB_val *dst, const MDB_val *key);
	typealias MDB_checksum_ftype = @convention(c) (UnsafePointer<MDB_val>?, UnsafeMutablePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Int32
	static var MDB_checksum_f:MDB_checksum_ftype { get }
}