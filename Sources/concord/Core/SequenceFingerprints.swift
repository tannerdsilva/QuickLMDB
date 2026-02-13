import RAW
import QuickLMDB

extension Sequence where Element == (key:MDB_val, value:MDB_val) {
	internal func fingerprint<H>(hasher _:H.Type) throws -> H.RAW_hasher_outputtype where H:RAW_hasher {
		var hasher = try H()
		for (key, _) in self {
			try hasher.update(key.mv_data, count:key.mv_size)
		}
		var returnData = H.RAW_hasher_outputtype(RAW_staticbuff:H.RAW_hasher_outputtype.RAW_staticbuff_zeroed())
		try returnData.RAW_access_staticbuff_mutating { outputData in
			try hasher.finish(into:outputData)
		}
		return returnData
	}
}