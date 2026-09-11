import Testing
import Foundation
import QuickLMDB
@testable import QuickLMDB   // for the internal .dupSort flag on the raw Database

// direct unit tests for the `extension MDB_cursor` / `extension MDB_cursor_dupsort`
// protocol-extension bridges that call into the interop statics (get/set/contains/
// delete-current/dup-count/compare + the op* navigation family). driven through a
// RAW `Cursor` (basic) for core ops and the dupsort cursor for duplicate ops, so
// the MDB_val-level extension members are exercised exactly.

@Suite("MDB_cursor protocol extension (interop bridge)")
struct CursorProtocolExtensionTests {

	// a core plus a raw raw-value cursor-capable database handle
	private func seededCore(_ name:String = "rawcursor") throws -> (TestCore, Database) {
		let core = try TestHelpers.makeCore()
		let tx = try Transaction<Write>(env:core.env)
		let db = try Database(env:core.env, name:name, flags:[.create], tx:tx)
		try tx.commit()
		return (core, db)
	}

	private func seedRaw(_ db:Database, _ env:Environment, _ pairs:[(UInt8, UInt8)]) throws {
		try withWriteTxn(env) { tx in
			for (k, v) in pairs {
				try withMDBVal([k]) { key in
					try withMDBVal([v]) { value in
						try db.setEntry(key:key, value:value, flags:[], tx:tx)
					}
				}
			}
		}
	}

	// - MARK: navigation

	@Test func opFirstLastNextPreviousWalk() throws {
		let (core, db) = try seededCore()
		try seedRaw(db, core.env, [(1, 10), (2, 20), (3, 30)])
		let rtx = try Transaction<Read>(env:core.env)
		try db.cursor(tx:rtx) { c in
			var e = try c.opFirst(returning:(key:MDB_val, value:MDB_val).self)
			#expect(mdbValBytes(e.key) == [1])
			e = try c.opNext(returning:(key:MDB_val, value:MDB_val).self)
			#expect(mdbValBytes(e.key) == [2])
			e = try c.opNext(returning:(key:MDB_val, value:MDB_val).self)
			#expect(mdbValBytes(e.key) == [3])
			// stepping past the end throws notFound
			do {
				let _ = try c.opNext(returning:(key:MDB_val, value:MDB_val).self)
				Issue.record("expected notFound past the end")
			} catch let error {
				#expect(isMDBErr(error, .notFound))
			}
			e = try c.opPrevious(returning:(key:MDB_val, value:MDB_val).self)
			#expect(mdbValBytes(e.key) == [2])
			e = try c.opLast(returning:(key:MDB_val, value:MDB_val).self)
			#expect(mdbValBytes(e.key) == [3])
		}
	}

	@Test func opFirstOnEmptyThrowsNotFound() throws {
		let (core, db) = try seededCore("empty")
		let rtx = try Transaction<Read>(env:core.env)
		db.cursor(tx:rtx) { c in
			do {
				let _ = try c.opFirst(returning:(key:MDB_val, value:MDB_val).self)
				Issue.record("expected notFound for opFirst on an empty database")
			} catch let error {
				#expect(isMDBErr(error, .notFound))
			}
			do {
				let _ = try c.opLast(returning:(key:MDB_val, value:MDB_val).self)
				Issue.record("expected notFound for opLast on an empty database")
			} catch let error {
				#expect(isMDBErr(error, .notFound))
			}
		}
	}

	@Test func opSetAndOpSetKeyPositionExactly() throws {
		let (core, db) = try seededCore("setpos")
		try seedRaw(db, core.env, [(0x55, 0xAA)])
		let rtx = try Transaction<Read>(env:core.env)
		try db.cursor(tx:rtx) { c in
			try withMDBVal([0x55]) { key in
				let value = try c.opSet(returning:MDB_val.self, key:key)
				#expect(mdbValBytes(value) == [0xAA])
			}
			// opSetKey returns the exact key/value pair
			try withMDBVal([0x55]) { key in
				let pair = try c.opSetKey(returning:(key:MDB_val, value:MDB_val).self, key:key)
				#expect(mdbValBytes(pair.key) == [0x55])
				#expect(mdbValBytes(pair.value) == [0xAA])
			}
			// an exact-set on a missing key throws
			withMDBVal([0x56]) { key in
				do {
					let _ = try c.opSet(returning:MDB_val.self, key:key)
					Issue.record("expected notFound for an exact-set on a missing key")
				} catch let error {
					#expect(isMDBErr(error, .notFound))
				}
			}
		}
	}

	@Test func opSetRangeFindsNearestKey() throws {
		let (core, db) = try seededCore("range")
		try seedRaw(db, core.env, [(10, 1), (20, 2), (30, 3)])
		let rtx = try Transaction<Read>(env:core.env)
		try db.cursor(tx:rtx) { c in
			try withMDBVal([15]) { key in
				let pair = try c.opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:key)
				#expect(mdbValBytes(pair.key) == [20])
			}
			// seeking beyond the last key throws
			withMDBVal([99]) { key in
				do {
					let _ = try c.opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:key)
					Issue.record("expected notFound beyond the last key")
				} catch let error {
					#expect(isMDBErr(error, .notFound))
				}
			}
		}
	}

	@Test func opGetCurrentAfterPositioning() throws {
		let (core, db) = try seededCore("current")
		try seedRaw(db, core.env, [(1, 10), (2, 20)])
		let rtx = try Transaction<Read>(env:core.env)
		try db.cursor(tx:rtx) { c in
			let _ = try c.opFirst(returning:(key:MDB_val, value:MDB_val).self)
			let pair = try c.opGetCurrent(returning:(key:MDB_val, value:MDB_val).self)
			#expect(mdbValBytes(pair.key) == [1])
			#expect(mdbValBytes(pair.value) == [10])
		}
	}

	@Test func noArgConvenienceReturnsTypedPair() throws {
		let (core, db) = try seededCore("convenience")
		try seedRaw(db, core.env, [(7, 70)])
		let rtx = try Transaction<Read>(env:core.env)
		let pair = try db.cursor(tx:rtx) { c in
			return try c.opFirst()   // the no-arg convenience (MDB_db_key_type/MDB_db_val_type)
		}
		#expect(mdbValBytes(pair.key) == [7])
		#expect(mdbValBytes(pair.value) == [70])
	}

	// - MARK: cursor writes + contains

	@Test func cursorSetEntryAndDeleteCurrent() throws {
		let (core, db) = try seededCore("cwrite")
		let wt = try Transaction<Write>(env:core.env)
		try db.cursor(tx:wt) { c in
			try withMDBVal([0x70]) { key in
				try withMDBVal([0x71]) { value in
					try c.setEntry(key:key, value:value, flags:[], tx: wt)
				}
				let present = try c.containsEntry(key:key)
				#expect(present == true)
				try c.deleteCurrentEntry(flags:[], tx: wt)
				let absent = try c.containsEntry(key:key)
				#expect(absent == false)
			}
		}
	}

	// - MARK: duplicates (dupsort cursor)

	private func seedDups(_ core:TestCore, key: UInt32, values:[UInt64]) throws {
		try withWriteTxn(core.env) { tx in
			for v in values {
				try core.secondary.setEntry(key:TestKey(RAW_native: key), value:TestValue(RAW_native: v), flags:[], tx:tx)
			}
		}
	}

	@Test func dupWalkAndDupCount() throws {
		let core = try TestHelpers.makeCore()
		try seedDups(core, key: 1, values: [10, 20, 30])
		try seedDups(core, key: 2, values: [99])
		let rtx = try Transaction<Read>(env:core.env)
		try core.secondary.cursor(tx:rtx) { c in
			let _ = try c.opSetKey(returning:(key:TestKey, value:TestValue).self, key:TestKey(RAW_native: 1))
			let count = try c.dupCount()
			#expect(count == 3)
			var seen:[TestValue] = []
			var first = try c.opFirstDup(returning:TestValue.self)
			seen.append(first)
			while true {
				do {
					first = try c.opNextDup(returning:TestValue.self)
					seen.append(first)
				} catch let error where isMDBErr(error, .notFound) {
					break
				}
			}
			#expect(seen == [TestValue(RAW_native: 10), TestValue(RAW_native: 20), TestValue(RAW_native: 30)])
			// backwards
			let last = try c.opLastDup(returning:TestValue.self)
			#expect(last == TestValue(RAW_native: 30))
			let prev = try c.opPreviousDup(returning:TestValue.self)
			#expect(prev == TestValue(RAW_native: 20))
			// nextNoDup jumps past the key's duplicates to the next key
			let nextKey = try c.opNextNoDup(returning:(key:TestKey, value:TestValue).self)
			#expect(nextKey.key == TestKey(RAW_native: 2))
			#expect(nextKey.value == TestValue(RAW_native: 99))
		}
	}

	@Test func containsEntryKeyValueAndGetBothOnDups() throws {
		let core = try TestHelpers.makeCore()
		try seedDups(core, key: 1, values: [10, 20])
		let rtx = try Transaction<Read>(env:core.env)
		try core.secondary.cursor(tx:rtx) { c in
			let _ = try c.opSetKey(returning:(key:TestKey, value:TestValue).self, key:TestKey(RAW_native: 1))
			let present = try c.containsEntry(key:TestKey(RAW_native: 1), value:TestValue(RAW_native: 20))
			#expect(present == true)
			let absent = try c.containsEntry(key:TestKey(RAW_native: 1), value:TestValue(RAW_native: 99))
			#expect(absent == false)
			let got = try c.opGetBoth(returning:TestValue.self, key:TestKey(RAW_native: 1), value:TestValue(RAW_native: 20))
			#expect(got == TestValue(RAW_native: 20))
			do {
				let _ = try c.opGetBoth(returning:TestValue.self, key:TestKey(RAW_native: 1), value:TestValue(RAW_native: 99))
				Issue.record("expected notFound for a missing exact pair")
			} catch let error {
				#expect(isMDBErr(error, .notFound))
			}
			// getBothRange finds the nearest duplicate value
			let ranged = try c.opGetBothRange(returning:TestValue.self, key:TestKey(RAW_native: 1), value:TestValue(RAW_native: 15))
			#expect(ranged == TestValue(RAW_native: 20))
		}
	}

	@Test func compareEntryKeysAndValues() throws {
		let core = try TestHelpers.makeCore()
		let setup = try Transaction<Write>(env:core.env)
		// mdb_dcmp requires a dupsort database (plain DBs have no dup comparator)
		let db = try Database(env:core.env, name:"cmp", flags:[.create, .dupSort], tx:setup)
		try setup.commit()
		let rtx = try Transaction<Read>(env:core.env)
		db.cursor(tx:rtx) { c in
			withMDBVal([3]) { lhs in
				withMDBVal([5]) { rhs in
					#expect(c.compareEntryKeys(lhs, rhs) < 0)
					#expect(c.compareEntryValues(lhs, rhs) < 0)
				}
				withMDBVal([3]) { equal in
					#expect(c.compareEntryKeys(lhs, equal) == 0)
				}
			}
		}
	}
}
