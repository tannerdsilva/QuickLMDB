import Testing
import QuickLMDB

// small MDB_val helpers for the protocol-extension tests: build raw MDB_val
// values from byte arrays (scoped to the call), read them back, run a write
// transaction, and check typed LMDBError codes.

@discardableResult
func withMDBVal<T>(_ bytes:[UInt8], _ body:(consuming MDB_val) throws -> T) rethrows -> T {
	try bytes.withUnsafeBytes { raw in
		var val = MDB_val()
		val.mv_size = raw.count
		val.mv_data = raw.baseAddress.map { UnsafeMutableRawPointer(mutating:$0) }
		return try body(val)
	}
}

func mdbValBytes(_ val:MDB_val) -> [UInt8] {
	guard let p = val.mv_data, val.mv_size > 0 else { return [] }
	return [UInt8](UnsafeRawBufferPointer(start:p, count:val.mv_size))
}

func isMDBErr(_ error:Error, _ expected:LMDBError) -> Bool {
	guard let lmdbError = error as? LMDBError else { return false }
	return lmdbError.returnCode == expected.returnCode
}

// run `body` on a write transaction, committing on success / aborting on throw
func withWriteTxn(_ env:Environment, _ body:(borrowing Transaction) throws -> Void) throws {
	let tx = try Transaction(env:env, readOnly:false)
	do {
		try body(tx)
	} catch let error {
		tx.abort()
		throw error
	}
	try tx.commit()
}

// reverse endian comparator, used to verify compare-assignment takes effect.
// compares the LAST byte so it works for raw 1-byte MDB_val values and big-endian
// fixed-width types alike.
let reverseByteCmp:MDB_cmp_func_t = { lhs, rhs in
	let l = lhs!.pointee.mv_data!.load(fromByteOffset:lhs!.pointee.mv_size - 1, as:UInt8.self)
	let r = rhs!.pointee.mv_data!.load(fromByteOffset:rhs!.pointee.mv_size - 1, as:UInt8.self)
	return Int32(r) - Int32(l)
}
