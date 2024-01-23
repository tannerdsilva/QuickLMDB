import struct CLMDB.MDB_val
import RAW

// MARK: Static functions
extension MDB_val {
	/// Returns an MDB_val that represents a null value.
	/// - Returned value is a zero-length value with a nil pointer.
	public static func nullValue() -> MDB_val {
		return MDB_val(mv_size:0, mv_data:nil)
	}

	internal init(_ buffer:UnsafeMutableBufferPointer<UInt8>) {
		self = MDB_val(mv_size:buffer.count, mv_data:buffer.baseAddress)
	}
}