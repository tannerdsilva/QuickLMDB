import struct CLMDB.MDB_val

extension UnsafeMutableBufferPointer<UInt8> {
	internal init(_ mdbVal:MDB_val) {
		self.init(start:mdbVal.mv_data.assumingMemoryBound(to:UInt8.self), count:mdbVal.mv_size)
	}
}