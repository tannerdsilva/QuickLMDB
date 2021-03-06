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

extension MDB_val:Sequence {
	public struct Iterator:IteratorProtocol {
		public typealias Element = UInt8
		let memory:UnsafeMutablePointer<UInt8>
		var size:size_t
		var i:size_t = 0
		init(_ val:MDB_val) {
			self.memory = val.mv_data.assumingMemoryBound(to:UInt8.self)
			self.size = val.mv_size
		}
		public mutating func next() -> Self.Element? {
			if (i >= size) {
				return nil
			} else {
				defer {
					i += 1;
				}
				return memory[i]
			}
		}
	}
	public typealias Element = UInt8
	public func makeIterator() -> Iterator {
		return Iterator(self)
	}
}

extension MDB_val:Collection {
	public func index(after i:size_t) -> size_t {
		return i + 1;
	}
	
	public subscript(position:size_t) -> UInt8 {
		get {
			self.mv_data.assumingMemoryBound(to:UInt8.self)[position]
		}
	}
	
	public var startIndex:size_t {
		return 0
	}
	
	public var endIndex:size_t {
		return self.mv_size
	}
	
	public typealias Index = size_t
}
