import CLMDB
import Foundation
import QuickLMDBFunctionalInterop

// raw CLMDB harness for QuickLMDBFunctionalInteropTests. drives the C surface
// directly (no QuickLMDB types) so the interop layer is exercised exactly as
// its contract promises: primitive handles in, raw LMDB results out.

enum RawError:Error {
	case setup(String)
}

func throwRaw(_ rc:Int32, _ what:String) throws {
	guard rc == MDB_SUCCESS else {
		throw RawError.setup("\(what) failed: \(rc)")
	}
}

// an open LMDB environment (MDB_env*) with a unique temp file backing it
final class RawEnv {
	let env:OpaquePointer
	let path:String
	let mainDB:MDB_dbi

	init(name:String = "test.mdb") throws {
		var createOut:OpaquePointer? = nil
		guard mdb_env_create(&createOut) == MDB_SUCCESS, let created = createOut else {
			throw RawError.setup("mdb_env_create")
		}
		guard mdb_env_set_mapsize(created, 4 * 1024 * 1024) == MDB_SUCCESS,
			  mdb_env_set_maxdbs(created, 8) == MDB_SUCCESS
		else {
			mdb_env_close(created)
			throw RawError.setup("mdb_env sizing")
		}
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-interop-\(UUID().uuidString)", isDirectory:true)
		try FileManager.default.createDirectory(at:dir, withIntermediateDirectories:true)
		let fullPath = dir.appendingPathComponent(name, isDirectory:false).path
		let flags = UInt32(MDB_NOSUBDIR) | UInt32(MDB_NOTLS)
		let openRC = fullPath.withCString { mdb_env_open(created, $0, flags, 0o600) }
		guard openRC == MDB_SUCCESS else {
			mdb_env_close(created)
			throw RawError.setup("mdb_env_open \(openRC)")
		}
		// open the main database handle once, in a committed setup transaction
		var setupTx:OpaquePointer? = nil
		guard mdb_txn_begin(created, nil, 0, &setupTx) == MDB_SUCCESS, let setupTx else {
			mdb_env_close(created)
			throw RawError.setup("setup txn")
		}
		var mainDB = MDB_dbi()
		let openMain = mdb_dbi_open(setupTx, nil, UInt32(MDB_CREATE), &mainDB)
		let commitMain = mdb_txn_commit(setupTx)
		guard openMain == MDB_SUCCESS, commitMain == MDB_SUCCESS else {
			mdb_env_close(created)
			throw RawError.setup("main db open")
		}
		self.env = created
		self.path = fullPath
		self.mainDB = mainDB
	}

	var _closed = false
	deinit {
		close()
	}

	func close() {
		guard _closed == false else { return }
		_closed = true
		mdb_env_close(env)
	}

	func txn() throws -> OpaquePointer {
		var txn:OpaquePointer? = nil
		guard mdb_txn_begin(env, nil, 0, &txn) == MDB_SUCCESS, let txn else {
			throw RawError.setup("mdb_txn_begin")
		}
		return txn
	}

	func db(_ name:String?, flags:UInt32 = UInt32(MDB_CREATE), tx:OpaquePointer) throws -> MDB_dbi {
		var dbi = MDB_dbi()
		let rc:Int32
		if let name {
			rc = name.withCString { mdb_dbi_open(tx, $0, flags, &dbi) }
		} else {
			rc = mdb_dbi_open(tx, nil, flags, &dbi)
		}
		guard rc == MDB_SUCCESS else {
			throw RawError.setup("mdb_dbi_open \(rc)")
		}
		return dbi
	}

	func cursor(in tx:OpaquePointer, db:MDB_dbi) throws -> OpaquePointer {
		var cursor:OpaquePointer? = nil
		guard mdb_cursor_open(tx, db, &cursor) == MDB_SUCCESS, let cursor else {
			throw RawError.setup("mdb_cursor_open")
		}
		return cursor
	}
}

// open a named (or unnamed) database handle in its own committed setup transaction,
// so the returned handle is safe to use across any subsequent transaction
func openDB(_ env:RawEnv, _ name:String?, flags:UInt32 = UInt32(MDB_CREATE)) throws -> MDB_dbi {
	let tx = try env.txn()
	let dbi = try env.db(name, flags:flags, tx:tx)
	try throwRaw(mdb_txn_commit(tx), "setup db commit")
	return dbi
}

// run a body on a write transaction, committing on success / aborting on throw
func withTxn(_ env:RawEnv, _ body:(OpaquePointer) throws -> Void) throws {
	let tx = try env.txn()
	do {
		try body(tx)
	} catch let error {
		mdb_txn_abort(tx)
		throw error
	}
	try throwRaw(mdb_txn_commit(tx), "mdb_txn_commit")
}

// run a body on a cursor opened against a fresh write transaction (closed on exit)
func withCursorTxn(_ env:RawEnv, db:MDB_dbi, _ body:(OpaquePointer) throws -> Void) throws {
	try withTxn(env) { tx in
		let cursor = try env.cursor(in:tx, db:db)
		defer { mdb_cursor_close(cursor) }
		try body(cursor)
	}
}

// - MARK: MDB_val helpers (raw)

@discardableResult
func withVal<T>(_ bytes:[UInt8], _ body:(inout MDB_val) throws -> T) rethrows -> T {
	try bytes.withUnsafeBytes { raw in
		var val = MDB_val()
		val.mv_size = raw.count
		val.mv_data = raw.baseAddress.map { UnsafeMutableRawPointer(mutating:$0) }
		return try body(&val)
	}
}

func bytes(from val:MDB_val) -> [UInt8] {
	guard let p = val.mv_data, val.mv_size > 0 else { return [] }
	return [UInt8](UnsafeRawBufferPointer(start:p, count:val.mv_size))
}

func keyBytes(from val:MDB_val) -> [UInt8] {
	return bytes(from:val)
}

// error-code comparison for LMDBError cases
func isErr(_ error:Error, _ expected:LMDBError) -> Bool {
	guard let lmdbError = error as? LMDBError else { return false }
	return lmdbError.returnCode == expected.returnCode
}
