import RAW


public typealias MDB_convertible = RAW_accessible & RAW_decodable & RAW_encodable

extension RAW_accessible {
	public borrowing func MDB_access<R, E>(_ aHandler:(consuming MDB_val) throws(E) -> R) throws(E) -> R where E:Swift.Error {
		try RAW_access { (byteBuffer:UnsafeBufferPointer<UInt8>) throws(E) -> R in
			try aHandler(MDB_val(byteBuffer))
		}
	}
}

extension RAW_encodable {
	public borrowing func MDB_encodable_reserved_val() -> MDB_val {
		var myVar = MDB_val()
		RAW_encode(count:&myVar.mv_size)
		return myVar
	}
	public borrowing func MDB_encodable_write(reserved:consuming MDB_val) {
		RAW_encode(dest:reserved.mv_data.assumingMemoryBound(to: UInt8.self))
	}
}

extension RAW_decodable {
	public init?(_ mdbVal:consuming MDB_val) {
		self.init(RAW_decode:mdbVal.mv_data, count:mdbVal.mv_size)
	}
}

