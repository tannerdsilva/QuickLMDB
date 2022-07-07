import CLMDB
import Foundation

extension MDB_val:Hashable {
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

extension MDB_val:ContiguousBytes {
	public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
		return try body(UnsafeRawBufferPointer(start:self.mv_data, count:self.mv_size))
	}
}

extension MDB_val:MDB_encodable {
	public func asMDB_val<R>(_ valFunc: (inout MDB_val) throws -> R) rethrows -> R {
		var copyVal = self
		return try valFunc(&copyVal)
	}
}
