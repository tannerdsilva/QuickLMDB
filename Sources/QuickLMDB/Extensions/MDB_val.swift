import struct CLMDB.MDB_val
import RAW

extension MDB_val {

	/// returns a new MDB_val with an unspecified (garbage) pointer and a length specified as the encoded count of the given encodable type.
	internal static func reserved<E:RAW_encodable>(forRAW_encodable encodable:UnsafePointer<E>) -> MDB_val {
		var newEncodable = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
		encodable.pointee.RAW_encode(count:&newEncodable.mv_size)
		return newEncodable
	}
	
	internal static func nullValue() -> MDB_val {
		return MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
	}

	/// returns a new MDB_val with an unspecified (garbage) pointer and specified length.
	internal static func reserved(capacity:size_t) -> MDB_val {
		return MDB_val(mv_size:capacity, mv_data:UnsafeMutableRawPointer(mutating:nil))
	}

	/// initializes a new MDB_val that overlaps with the contents of an UnsafeMutableBufferPointer.
	internal init(_ buffer:UnsafeMutableBufferPointer<UInt8>) {
		self = MDB_val(mv_size:buffer.count, mv_data:buffer.baseAddress)
	}
	
	/// initializes a new MDB_val that overlaps with the contents of the UnsafeBufferPointer.
	internal init(_ buffer:UnsafeBufferPointer<UInt8>) {
		self = MDB_val(mv_size:buffer.count, mv_data:UnsafeMutableRawPointer(mutating:buffer.baseAddress))
	}
}