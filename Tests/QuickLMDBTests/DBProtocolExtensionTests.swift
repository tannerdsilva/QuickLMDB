import Testing
import Foundation
import QuickLMDB
#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif
@testable import QuickLMDB   // for the internal assignCompareKey/assignCompareVal bridges + the .dupSort flag

// direct unit tests for the `extension MDB_db` protocol-extension bridge that
// calls into the interop statics (get/set/contains/delete/delete-all/delete-db/
// statistics/flags/compare-assign). driven through a RAW `Database` handle so
// the MDB_val-level extension members are exercised exactly — not the typed
// macro-generated handles.

@Suite("MDB_db protocol extension (interop bridge)")
struct DBProtocolExtensionTests {

	// a core plus a raw MDB_val database handle (plain or dupsort)
	private func rawCore(_ name:String = "rawproto", flags:MDB_db_flags = [.create]) throws -> (TestCore, Database) {
		let core = try TestHelpers.makeCore()
		let tx = try Transaction(env:core.env, readOnly:false)
		let db = try Database(env:core.env, name:name, flags:flags, tx:tx)
		try tx.commit()
		return (core, db)
	}

	// - MARK: get / set

	@Test func setEntryThenLoadEntryRoundTrips() throws {
		let (core, db) = try rawCore()
		try withWriteTxn(core.env) { tx in
			try withMDBVal([0xAA, 0xBB]) { key in
				try withMDBVal([1, 2, 3, 4]) { value in
					try db.setEntry(key:key, value:value, flags:[], tx:tx)
				}
			}
			try withMDBVal([0xAA, 0xBB]) { key in
				let out = try db.loadEntry(key:key, as:MDB_val.self, tx:tx)
				#expect(mdbValBytes(out) == [1, 2, 3, 4])
			}
		}
	}

	@Test func loadEntryMissingThrowsNotFound() throws {
		let (core, db) = try rawCore()
		try withWriteTxn(core.env) { tx in
			withMDBVal([0x01]) { key in
				do {
					_ = try db.loadEntry(key:key, as:MDB_val.self, tx:tx)
					Issue.record("expected notFound for a missing key")
				} catch let error {
					#expect(isMDBErr(error, .notFound))
				}
			}
		}
	}

	// - MARK: contains

	@Test func containsEntryReportsPresence() throws {
		let (core, db) = try rawCore()
		try withWriteTxn(core.env) { tx in
			try withMDBVal([0x10]) { key in
				try withMDBVal([9]) { value in
					try db.setEntry(key:key, value:value, flags:[], tx:tx)
				}
				let presentResult = try db.containsEntry(key:key, tx:tx)
				#expect(presentResult == true)
				try withMDBVal([0x11]) { missing in
					let missingResult = try db.containsEntry(key:missing, tx:tx)
					#expect(missingResult == false)
				}
			}
		}
	}

	// - MARK: delete

	@Test func deleteEntryRemovesKey() throws {
		let (core, db) = try rawCore()
		try withWriteTxn(core.env) { tx in
			try withMDBVal([0x30]) { key in
				try withMDBVal([1]) { value in
					try db.setEntry(key:key, value:value, flags:[], tx:tx)
				}
				try db.deleteEntry(key:key, tx:tx)
				do {
					_ = try db.loadEntry(key:key, as:MDB_val.self, tx:tx)
					Issue.record("expected notFound after delete")
				} catch let error {
					#expect(isMDBErr(error, .notFound))
				}
			}
		}
	}

	@Test func deleteEntryKeyValueRemovesSingleDup() throws {
		let (core, db) = try rawCore("dupdel", flags:[.create, .dupSort])
		try withWriteTxn(core.env) { tx in
			try withMDBVal([0x32]) { key in
				try withMDBVal([1]) { value in
					try db.setEntry(key:key, value:value, flags:[], tx:tx)
				}
				try withMDBVal([2]) { value in
					try db.setEntry(key:key, value:value, flags:[], tx:tx)
				}
				try withMDBVal([1]) { value in
					try db.deleteEntry(key:key, value:value, tx:tx)
				}
				// the [1] duplicate is gone; the first remaining is [2]
				let out = try db.loadEntry(key:key, as:MDB_val.self, tx:tx)
				#expect(mdbValBytes(out) == [2])
			}
		}
	}

	// - MARK: table-wide

	@Test func deleteAllEntriesEmptiesTheTable() throws {
		let (core, db) = try rawCore()
		try withWriteTxn(core.env) { tx in
			for i in 0..<3 {
				try withMDBVal([UInt8(i)]) { key in
					try withMDBVal([1]) { value in
						try db.setEntry(key:key, value:value, flags:[], tx:tx)
					}
				}
			}
			try db.deleteAllEntries(tx:tx)
			let stats = try db.dbStatistics(tx:tx)
			#expect(stats.ms_entries == 0)
		}
	}

	@Test func dbStatisticsReflectsEntryCount() throws {
		let (core, db) = try rawCore()
		try withWriteTxn(core.env) { tx in
			for i in 0..<3 {
				try withMDBVal([UInt8(i)]) { key in
					try withMDBVal([1]) { value in
						try db.setEntry(key:key, value:value, flags:[], tx:tx)
					}
				}
			}
			let stats = try db.dbStatistics(tx:tx)
			#expect(stats.ms_entries == 3)
		}
	}

	@Test func deleteDatabaseInvalidatesHandle() throws {
		let (core, db) = try rawCore("dropsub", flags:[.create])
		try withWriteTxn(core.env) { tx in
			try withMDBVal([0x40]) { key in
				try withMDBVal([1]) { value in
					try db.setEntry(key:key, value:value, flags:[], tx:tx)
				}
			}
			try db.deleteDatabase(tx:tx)
			withMDBVal([0x40]) { key in
				do {
					_ = try db.loadEntry(key:key, as:MDB_val.self, tx:tx)
					Issue.record("expected the dropped database handle to be invalid")
				} catch let error {
					guard let lmdbError = error as? LMDBError else {
						Issue.record("expected LMDBError but got \(error)")
						return
					}
					#expect(lmdbError.returnCode == Int32(EINVAL), "actual returnCode: \(lmdbError.returnCode)")
				}
			}
		}
	}

	// - MARK: metadata

	@Test func dbFlagsReported() throws {
		let (core, plainDB) = try rawCore("flagsplain", flags:[.create])
		let setup = try Transaction(env:core.env, readOnly:false)
		let dupDB = try Database(env:core.env, name:"flagsdup", flags:[.create, .dupSort], tx:setup)
		try setup.commit()
		try withWriteTxn(core.env) { tx in
			let plainFlags = try plainDB.dbFlags(tx:tx)
			#expect(plainFlags.contains(.dupSort) == false)
			let dupFlags = try dupDB.dbFlags(tx:tx)
			#expect(dupFlags.contains(.dupSort) == true)
		}
	}

	// - MARK: cursor handler + compare bridges

	@Test func cursorHandlerReceivesLiveCursor() throws {
		let (core, db) = try rawCore()
		try withWriteTxn(core.env) { tx in
			try withMDBVal([0x05]) { key in
				try withMDBVal([0xAA]) { value in
					try db.setEntry(key:key, value:value, flags:[], tx:tx)
				}
			}
		}
		let rtx = try Transaction(env:core.env, readOnly:true)
		let entry = try db.cursor(tx:rtx) { cursor in
			return try cursor.opFirst(returning:(key:MDB_val, value:MDB_val).self)
		}
		#expect(mdbValBytes(entry.key) == [0x05])
		#expect(mdbValBytes(entry.value) == [0xAA])
	}

	@Test func assignCompareKeyRoutesThroughExtension() throws {
		let (core, db) = try rawCore("cmpkey", flags:[.create])
		try withWriteTxn(core.env) { tx in
			db.assignCompareKey(reverseByteCmp, tx:tx)
			for i in [UInt8(1), 2, 3] {
				try withMDBVal([i]) { key in
					try withMDBVal([0]) { value in
						try db.setEntry(key:key, value:value, flags:[], tx:tx)
					}
				}
			}
		}
		// a reversed key order must be visible through a cursor scan
		let rtx = try Transaction(env:core.env, readOnly:true)
		var seen:[UInt8] = []
		db.cursor(tx:rtx) { cursor in
			for (k, _) in cursor {
				seen.append(mdbValBytes(k)[0])
			}
		}
		#expect(seen == [3, 2, 1])
	}

	@Test func assignCompareValRoutesThroughExtension() throws {
		let (core, db) = try rawCore("cmpval", flags:[.create, .dupSort])
		try withWriteTxn(core.env) { tx in
			db.assignCompareVal(reverseByteCmp, tx:tx)
			try withMDBVal([0x50]) { key in
				for v in [UInt8(1), 2, 3] {
					try withMDBVal([v]) { value in
						try db.setEntry(key:key, value:value, flags:[], tx:tx)
					}
				}
			}
			// reversed dup order: the FIRST duplicate is now [3]
			try withMDBVal([0x50]) { key in
				let first = try db.loadEntry(key:key, as:MDB_val.self, tx:tx)
				#expect(mdbValBytes(first) == [3])
			}
			try withMDBVal([0x50]) { key in
				try withMDBVal([3]) { value in
					try db.deleteEntry(key:key, value:value, tx:tx)
				}
			}
			try withMDBVal([0x50]) { key in
				let next = try db.loadEntry(key:key, as:MDB_val.self, tx:tx)
				#expect(mdbValBytes(next) == [2])
			}
		}
	}
}
