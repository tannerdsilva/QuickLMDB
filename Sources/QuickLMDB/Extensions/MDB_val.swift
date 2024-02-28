import struct CLMDB.MDB_val
import RAW



extension MDB_val {

	/// returns a new MDB_val with an unspecified (garbage) pointer and a length specified as the encoded count of the given encodable type.
	internal static func reserved<E:RAW_encodable>(RAW_encodable encodable:borrowing E) -> MDB_val {
		var newEncodable = MDB_val()
		encodable.RAW_encode(count:&newEncodable.mv_size)
		return newEncodable
	}
	
	internal static func uninitialized() -> MDB_val {
		var makeVal = MDB_val()
		makeVal.mv_size = -1
		return makeVal
	}

	/// returns a new MDB_val with an unspecified (garbage) pointer and specified length.
	internal static func reserved(capacity:size_t) -> MDB_val {
		var makeVal = MDB_val()
		makeVal.mv_size = capacity
		return makeVal
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

extension MDB_val:Sequence {
	public typealias Element = UInt8
	public typealias Iterator = UnsafeBufferPointer<UInt8>.Iterator
	public func makeIterator() -> Iterator {
		return UnsafeBufferPointer(start:mv_data.assumingMemoryBound(to:UInt8.self), count:mv_size).makeIterator()
	}
}

extension MDB_val:CustomDebugStringConvertible {
	public var debugDescription:String {
		return "[MDB_val](\(hashValue % Int(UInt16.max)){ \(mv_size)b }"
	}
}

extension MDB_val:Hashable {
	public func hash(into hasher:inout Hasher) {
		hasher.combine(mv_size)
		hasher.combine(mv_data)
	}
}

extension MDB_val:Equatable {
	public static func == (lhs:MDB_val, rhs:MDB_val) -> Bool {
		return lhs.mv_size == rhs.mv_size && lhs.mv_data == rhs.mv_data
	}
}