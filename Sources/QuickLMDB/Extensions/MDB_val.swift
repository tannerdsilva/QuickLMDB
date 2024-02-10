import struct CLMDB.MDB_val
import RAW

extension MDB_val {

	/// returns a new MDB_val with a null data pointer and a length specified as the encoded count of the given encodable type.
	internal static func reserved<E:RAW_encodable>(forRAW_encodable encodable:inout E) -> MDB_val {
		var newEncodable = MDB_val(mv_size:0, mv_data:nil)
		encodable.RAW_encode(count:&newEncodable.mv_size)
		return newEncodable
	}

	/// returns a new MDB_val with a null data pointer and specified length.
	internal static func reserved(capacity:size_t) -> MDB_val {
		return MDB_val(mv_size:capacity, mv_data:nil)
	}

	/// returns an MDB_val with a null data pointer and a length of zero.
	internal static func nullValue() -> MDB_val {
		return MDB_val(mv_size:0, mv_data:nil)
	}

	/// initializes a new MDB_val that overlaps with the contents of an UnsafeMutableBufferPointer.
	internal init(_ buffer:UnsafeMutableBufferPointer<UInt8>) {
		self = MDB_val(mv_size:buffer.count, mv_data:buffer.baseAddress)
	}
}