import RAW
import struct CLMDB.MDB_val

extension RAW_decodable {
	init?(RAW_decode val:MDB_val) {
		self.init(RAW_decode:val.mv_data, count:val.mv_size)
	}
}