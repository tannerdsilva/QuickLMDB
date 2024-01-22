extension UnsafeMutableRawBufferPointer {
	public init(_ mdbVal:MDB_val) {
		self.init(start:mdbVal.mv_data, count:mdbVal.mv_size)
	}
}