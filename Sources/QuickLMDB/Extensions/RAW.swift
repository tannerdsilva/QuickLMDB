import RAW

extension RAW_decodable {

	init?(_ val:MDB_val) {
		self.init(RAW_decode:val.mv_data, count:val.mv_size)
	}
	
}