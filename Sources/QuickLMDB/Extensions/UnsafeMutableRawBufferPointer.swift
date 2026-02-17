extension UnsafeMutableBufferPointer<UInt8> {
	public init(_ val:MDB_val) {
		self.init(start:val.mv_data?.assumingMemoryBound(to:UInt8.self), count:val.mv_size)
	}
	public func MDB_val() -> MDB_val {
		return .init(mv_size:count, mv_data:baseAddress)
	}
}

extension UnsafeMutableRawBufferPointer {
	public init(_ val:MDB_val) {
		self.init(start:val.mv_data, count:val.mv_size)
	}
	public func MDB_val() -> MDB_val {
		return .init(mv_size:count, mv_data:baseAddress)
	}
}

extension UnsafeRawBufferPointer {
	public init(_ val:MDB_val) {
		self.init(start:val.mv_data, count:val.mv_size)
	}
	public func MDB_val() -> MDB_val {
		return .init(mv_size:count, mv_data:UnsafeMutableRawPointer(mutating:baseAddress))
	}
}

extension UnsafeBufferPointer<UInt8> {
	public init(_ val:MDB_val) {
		self.init(start:val.mv_data?.assumingMemoryBound(to:UInt8.self), count:val.mv_size)
	}
	public func MDB_val() -> MDB_val {
		return .init(mv_size:count, mv_data:UnsafeMutableRawPointer(mutating:baseAddress))
	}
}