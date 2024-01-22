import CLMDB
import Foundation

// MARK: Static functions
extension MDB_val {
	/// Returns an MDB_val that represents a null value.
	/// - Returned value is a zero-length value with a nil pointer.
	public static func nullValue() -> MDB_val {
		return MDB_val(mv_size:0, mv_data:nil)
	}

	public init(_ buffer:UnsafeMutableBufferPointer<UInt8>) {
		self = MDB_val(mv_size:buffer.count, mv_data:buffer.baseAddress)
	}
}

// MARK: Hashable & Equatable
extension MDB_val:Hashable, Equatable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(bytes:UnsafeRawBufferPointer(start:self.mv_data, count:self.mv_size))
	}
	
	public static func == (lhs: MDB_val, rhs: MDB_val) -> Bool {
		if (lhs.mv_size == rhs.mv_size) {
			return memcmp(lhs.mv_data, rhs.mv_data, lhs.mv_size) == 0
		} else {
			return false
		}
	}
}