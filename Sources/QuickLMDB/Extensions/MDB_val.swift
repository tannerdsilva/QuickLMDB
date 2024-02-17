import struct CLMDB.MDB_val
import RAW

extension MDB_val {

	/// returns a new MDB_val with an unspecified (garbage) pointer and a length specified as the encoded count of the given encodable type.
	internal static func reserved<E:RAW_encodable>(forRAW_encodable encodable:inout E) -> MDB_val {
		var newEncodable = MDB_val()
		encodable.RAW_encode(count:&newEncodable.mv_size)
		return newEncodable
	}

	/// returns a new MDB_val with an unspecified (garbage) pointer and specified length.
	internal static func reserved(capacity:size_t) -> MDB_val {
		var newVal = MDB_val()
		newVal.mv_size = capacity
		return newVal
	}

	/// initializes a new MDB_val that overlaps with the contents of an UnsafeMutableBufferPointer.
	internal init(_ buffer:UnsafeMutableBufferPointer<UInt8>) {
		self = MDB_val(mv_size:buffer.count, mv_data:buffer.baseAddress)
	}
}