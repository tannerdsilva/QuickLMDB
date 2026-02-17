extension UnsafeMutableBufferPointer<UInt8> {
	public init(_ val:MDB_val) {
		self.init(start:val.mv_data?.assumingMemoryBound(to:UInt8.self), count:val.mv_size)
	}
}

extension UnsafeMutableRawBufferPointer {
	public init(_ val:MDB_val) {
		self.init(start:val.mv_data, count:val.mv_size)
	}
}

extension UnsafeRawBufferPointer {
	public init(_ val:MDB_val) {
		self.init(start:val.mv_data, count:val.mv_size)
	}
}

extension UnsafeBufferPointer<UInt8> {
	public init(_ val:MDB_val) {
		self.init(start:val.mv_data?.assumingMemoryBound(to:UInt8.self), count:val.mv_size)
	}
}