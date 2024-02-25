import RAW

public typealias MDB_convertible = RAW_accessible & RAW_decodable

extension RAW_accessible {
	public borrowing func MDB_access<R>(_ aHandler:(consuming MDB_val) throws -> R) rethrows -> R {
		try RAW_access { byteBuffer in
			try aHandler(MDB_val(byteBuffer))
		}
	}
}

extension RAW_decodable {
	public init?(_ mdbVal:consuming MDB_val) {
		self.init(RAW_decode:mdbVal.mv_data, count:mdbVal.mv_size)
	}
}


extension RAW_encodable {
	public borrowing func MDB_encodable_reserved_val() -> MDB_val {
		return RAW_access { myByteBuffer in
			var newVal = MDB_val()
			newVal.mv_size = myByteBuffer.count
			return newVal
		}
	}

	public borrowing func MDB_encodable_write(reserved:consuming MDB_val) {
		RAW_access { myByteBuffer in
			_ = RAW_memcpy(reserved.mv_data, myByteBuffer.baseAddress!, reserved.mv_size)
		}
	}
}