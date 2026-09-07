import struct CLMDB.MDB_val

extension MDB_val {

	internal static func uninitialized() -> MDB_val {
		var makeVal = MDB_val()
		makeVal.mv_size = -1
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

extension MDB_val:@retroactive Sequence {
	public typealias Element = UInt8
	public typealias Iterator = UnsafeBufferPointer<UInt8>.Iterator
	public func makeIterator() -> Iterator {
		return UnsafeBufferPointer(start:mv_data.assumingMemoryBound(to:UInt8.self), count:mv_size).makeIterator()
	}
}

extension MDB_val:@retroactive CustomDebugStringConvertible {
	public var debugDescription:String {
		return "[MDB_val](\(hashValue % Int(UInt16.max)){ \(mv_size)b }"
	}
}

extension MDB_val:@retroactive Hashable {
	public func hash(into hasher:inout Hasher) {
		hasher.combine(mv_size)
		hasher.combine(mv_data)
	}
}

extension MDB_val:@retroactive Equatable {
	public static func == (lhs:MDB_val, rhs:MDB_val) -> Bool {
		return lhs.mv_size == rhs.mv_size && lhs.mv_data == rhs.mv_data
	}
}