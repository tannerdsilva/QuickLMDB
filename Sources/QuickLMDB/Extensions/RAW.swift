import RAW
import struct CLMDB.MDB_val

extension RAW_decodable {
	internal init?(RAW_decode val:MDB_val) {
		self.init(RAW_decode:val.mv_data, count:val.mv_size)
	}
	public init?(RAW_decode:UnsafeMutableBufferPointer<UInt8>) {
		self.init(RAW_decode:RAW_decode.baseAddress!, count:RAW_decode.count)
	}
}