import CLMDB

extension MDB_val:MDB_encodable {
	public func asMDB_val<R>(_ valFunc: (inout MDB_val) throws -> R) rethrows -> R {
		var copyVal = self
		return try valFunc(&copyVal)
	}
}
