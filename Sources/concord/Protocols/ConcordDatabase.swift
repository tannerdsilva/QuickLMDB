import QuickLMDB
import RAW

/// a protocol used to express databases that can be automatically synced by way of a shared type of key.
public protocol ConcordDatabase:MDB_db_strict, Sendable where Self.MDB_db_key_type:IndexVector {}

extension MDB_cursor {
	internal func fingerprint<H>(begin:consuming MDB_val, bucketSize:Int, hasher:H.Type) throws -> H.RAW_hasher_outputtype where H:RAW_hasher {
		var hasher = try H()
		for (key, _) in view(begin:begin, steps:bucketSize) {
			try hasher.update(key.mv_data, count:key.mv_size)
		}
		var returnData = H.RAW_hasher_outputtype(RAW_staticbuff:H.RAW_hasher_outputtype.RAW_staticbuff_zeroed())
		try returnData.RAW_access_staticbuff_mutating { outputData in
			try hasher.finish(into:outputData)
		}
		return returnData
	}
	
	internal func fingerprint<H>(begin:consuming MDB_val, end:consuming MDB_val, hasher:H.Type) throws -> H.RAW_hasher_outputtype where H:RAW_hasher {
		var hasher = try H()
		for (key, _) in view(begin:begin, end:end) {
			try hasher.update(key.mv_data, count:key.mv_size)
		}
		var returnData = H.RAW_hasher_outputtype(RAW_staticbuff:H.RAW_hasher_outputtype.RAW_staticbuff_zeroed())
		try returnData.RAW_access_staticbuff_mutating { outputData in
			try hasher.finish(into:outputData)
		}
		return returnData
	}
}

extension MDB_cursor {
	public consuming func view(begin:consuming MDB_val, steps:Int) -> EnumeratedStepView<Self> {
		return EnumeratedStepView(cursor:self, begin:begin, steps:steps)
	}

	public consuming func view(begin:consuming MDB_val) -> OpenEndedView<Self> {
		return OpenEndedView(cursor:self, begin:begin)
	}
	
	public consuming func view(begin:consuming MDB_val, end:consuming MDB_val) -> DiscreteRangeView<Self> {
		return DiscreteRangeView(cursor:self, begin:begin, end:end)
	}
}

