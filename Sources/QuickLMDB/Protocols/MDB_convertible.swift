import RAW


public typealias MDB_convertible = RAW_accessible & RAW_decodable & RAW_encodable

extension RAW_accessible {
	public borrowing func MDB_access<R, E>(_ aHandler:(consuming MDB_val) throws(E) -> R) throws(E) -> R where E:Swift.Error {
		try RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { (byteBuffer:UnsafeBufferPointer<UInt8>) throws(E) -> R in
			try aHandler(MDB_val(byteBuffer))
		}
	}
}

extension RAW_decodable {
	public init?(_ mdbVal:consuming MDB_val) {
		self.init(RAW_decode: UnsafeRawBufferPointer(start:mdbVal.mv_data, count:mdbVal.mv_size))
	}
}

