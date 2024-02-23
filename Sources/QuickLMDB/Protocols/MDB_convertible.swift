import RAW

public typealias MDB_convertible = MDB_decodable & MDB_encodable

public protocol MDB_encodable {
	func MDB_encodable_access<R>(_:(UnsafeMutablePointer<MDB_val>) throws -> R) rethrows -> R
	func MDB_encodable_reserved_val() -> MDB_val
	func MDB_encodable_write(reserved:UnsafePointer<MDB_val>)
}

public protocol MDB_decodable {
	init?(_:MDB_val)
}

extension RAW_decodable where Self:MDB_decodable {
	public init?(_ mdbVal:MDB_val) {
		self.init(RAW_decode:mdbVal.mv_data, count:mdbVal.mv_size)
	}
}

extension RAW_accessible where Self:MDB_encodable {
	public func MDB_encodable_access<R>(_ handler:(UnsafeMutablePointer<MDB_val>) throws -> R) rethrows -> R {
		return try RAW_access { myByteBuffer in
			var mdbVal = MDB_val(myByteBuffer)
			return try handler(&mdbVal)
		}
	}

	public func MDB_encodable_reserved_val() -> MDB_val {
		var newVal = MDB_val()
		RAW_access { myByteBuffer in
			newVal.mv_size = myByteBuffer.count
		}
		return newVal
	}

	public func MDB_encodable_write(reserved:UnsafePointer<MDB_val>) {
		RAW_access { myByteBuffer in
			_ = RAW_memcpy(reserved.pointee.mv_data, myByteBuffer.baseAddress!, reserved.pointee.mv_size)
		}
	}
}

extension RAW_encodable where Self:MDB_encodable {
	public func MDB_encodable_access<R>(_ handler:(UnsafeMutablePointer<MDB_val>) throws -> R) rethrows -> R {
		var encCount:size_t = 0
		RAW_encode(count:&encCount)
		let makeBuffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity:encCount)
		defer {
			makeBuffer.deallocate()
		}
		RAW_encode(dest:makeBuffer.baseAddress!)
		var mdbVal = MDB_val(makeBuffer)
		return try handler(&mdbVal)
	}

	public func MDB_encodable_prereserved_val() -> MDB_val {
		var newVal = MDB_val()
		RAW_encode(count:&newVal.mv_size)
		return newVal
	}

	public func MDB_encodable_write(reserved:UnsafePointer<MDB_val>) {
		RAW_encode(dest:reserved.pointee.mv_data.assumingMemoryBound(to:UInt8.self))
	}
}