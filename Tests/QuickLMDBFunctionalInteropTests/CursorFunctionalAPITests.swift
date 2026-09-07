import Testing
import CLMDB
import QuickLMDBFunctionalInterop

// comprehensive coverage of the cursor-level functional interop surface,
// driven against real LMDB through raw CLMDB handles.

@Suite("Cursor functional interop")
struct CursorFunctionalAPITests {

	// - MARK: positioning

	@Test func firstAndLastOnEmptyThrowNotFound() throws {
		let env = try RawEnv()
		defer { env.close() }
		try withCursorTxn(env, db:env.mainDB) { cursor in
			var key = MDB_val()
			var value = MDB_val()
			do {
				let _ = try MDB_cursor_get_entry(cursor:cursor, op:MDB_FIRST, key:key, value:value)
				Issue.record("expected notFound for first on an empty database")
			} catch let error {
				#expect(isErr(error, .notFound))
			}
			key = MDB_val()
			value = MDB_val()
			do {
				let _ = try MDB_cursor_get_entry(cursor:cursor, op:MDB_LAST, key:key, value:value)
				Issue.record("expected notFound for last on an empty database")
			} catch let error {
				#expect(isErr(error, .notFound))
			}
		}
	}

	@Test func forwardAndBackwardIteration() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "iter")
		try withTxn(env) { tx in
			for i in [UInt8(0), 1, 2] {
				try withVal([i]) { key in
					try withVal([i]) { value in
						try MDB_db_set_entry(db:db, key:key, value:value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			var key = MDB_val()
			var value = MDB_val()
			var entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_FIRST, key:key, value:value)
			#expect(bytes(from:entry.key) == [0])
			key = MDB_val()
			value = MDB_val()
			entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_NEXT, key:key, value:value)
			#expect(bytes(from:entry.key) == [1])
			key = MDB_val()
			value = MDB_val()
			entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_NEXT, key:key, value:value)
			#expect(bytes(from:entry.key) == [2])
			// stepping past the end throws notFound
			key = MDB_val()
			value = MDB_val()
			do {
				let _ = try MDB_cursor_get_entry(cursor:cursor, op:MDB_NEXT, key:key, value:value)
				Issue.record("expected notFound past the end")
			} catch let error {
				#expect(isErr(error, .notFound))
			}
			key = MDB_val()
			value = MDB_val()
			entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_PREV, key:key, value:value)
			#expect(bytes(from:entry.key) == [1])
			key = MDB_val()
			value = MDB_val()
			entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_PREV, key:key, value:value)
			#expect(bytes(from:entry.key) == [0])
		}
	}

	@Test func setRangeFindsNearestKey() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "range")
		try withTxn(env) { tx in
			for i in [UInt8(10), 20, 30] {
				try withVal([i]) { key in
					try withVal([i]) { value in
						try MDB_db_set_entry(db:db, key:key, value:value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			try withVal([15]) { seek in
				let value = MDB_val()
				let entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_SET_RANGE, key:seek, value:value)
				#expect(bytes(from:entry.key) == [20])
			}
			try withVal([30]) { seek in
				let value = MDB_val()
				let entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_SET_RANGE, key:seek, value:value)
				#expect(bytes(from:entry.key) == [30])
			}
			withVal([99]) { seek in
				let value = MDB_val()
				do {
					let _ = try MDB_cursor_get_entry(cursor:cursor, op:MDB_SET_RANGE, key:seek, value:value)
					Issue.record("expected notFound when seeking beyond the last key")
				} catch let error {
					#expect(isErr(error, .notFound))
				}
			}
		}
	}

	@Test func setPositionsExactly() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "set")
		try withTxn(env) { tx in
			try withVal([0x55]) { key in
				try withVal([0xAA]) { value in
					try MDB_db_set_entry(db:db, key:key, value:value, flags:0, tx:tx)
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			try withVal([0x55]) { key in
				let value = MDB_val()
				let entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_SET, key:key, value:value)
				#expect(bytes(from:entry.value) == [0xAA])
			}
			withVal([0x56]) { key in
				let value = MDB_val()
				do {
					let _ = try MDB_cursor_get_entry(cursor:cursor, op:MDB_SET, key:key, value:value)
					Issue.record("expected notFound for an exact-set on a missing key")
				} catch let error {
					#expect(isErr(error, .notFound))
				}
			}
		}
	}

	@Test func getCurrentAfterPositioning() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "current")
		try withTxn(env) { tx in
			for i in [UInt8(1), 2] {
				try withVal([i]) { key in
					try withVal([i]) { value in
						try MDB_db_set_entry(db:db, key:key, value:value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			var key = MDB_val()
			var value = MDB_val()
			var entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_FIRST, key:key, value:value)
			key = MDB_val()
			value = MDB_val()
			entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_GET_CURRENT, key:key, value:value)
			#expect(bytes(from:entry.key) == [1])
			key = MDB_val()
			value = MDB_val()
			entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_NEXT, key:key, value:value)
			key = MDB_val()
			value = MDB_val()
			entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_GET_CURRENT, key:key, value:value)
			#expect(bytes(from:entry.key) == [2])
		}
	}

	// - MARK: pointer provenance

	@Test func getEntryReturnsMapPointersDistinctFromInputs() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "prov")
		try withTxn(env) { tx in
			for i in [UInt8(1), 2] {
				try withVal([i]) { key in
					try withVal([UInt8(i * 10)]) { value in
						try MDB_db_set_entry(db:db, key:key, value:value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			// zeroed input buffers — the returned pointers must come from the memory map
			let keyIn = MDB_val()
			let valueIn = MDB_val()
			let keyInPtr = keyIn.mv_data
			let valueInPtr = valueIn.mv_data
			let entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_FIRST, key:keyIn, value:valueIn)
			#expect(entry.key.mv_data != nil, "cursor key must be a live map pointer")
			#expect(entry.value.mv_data != nil, "cursor value must be a live map pointer")
			#expect(entry.key.mv_data != keyInPtr, "cursor key must not be the passed-in key pointer")
			#expect(entry.value.mv_data != valueInPtr, "cursor value must not be the passed-in value pointer")
		}
	}

	@Test func setRangeReturnsMapPointersDistinctFromSeekInput() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "provrange")
		try withTxn(env) { tx in
			for i in [UInt8(10), 20] {
				try withVal([i]) { key in
					try withVal([i]) { value in
						try MDB_db_set_entry(db:db, key:key, value:value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			// SET_RANGE rewrites the caller's seek key with the map entry's own pointer
			try withVal([15]) { seek in
				let seekPtr = seek.mv_data
				let valueIn = MDB_val()
				let valueInPtr = valueIn.mv_data
				let entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_SET_RANGE, key:seek, value:valueIn)
				#expect(bytes(from:entry.key) == [20])
				#expect(entry.key.mv_data != nil, "seek result key must be a live map pointer")
				#expect(entry.key.mv_data != seekPtr, "seek result key must not be the caller-provided seek pointer")
				#expect(entry.value.mv_data != nil, "seek result value must be a live map pointer")
				#expect(entry.value.mv_data != valueInPtr, "seek result value must not be the passed-in value pointer")
			}
		}
	}

	// - MARK: cursor writes

	@Test func setEntryThroughCursorPersists() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "cwrite")
		try withCursorTxn(env, db:db) { cursor in
			try withVal([0x70]) { key in
				try withVal([0x71]) { value in
					try MDB_cursor_set_entry(cursor:cursor, key:key, value:value, flags:0)
				}
			}
		}
		// the write committed with the cursor's transaction — verified through a fresh read
		try withCursorTxn(env, db:db) { cursor in
			try withVal([0x70]) { key in
				let value = MDB_val()
				let entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_SET, key:key, value:value)
				#expect(bytes(from:entry.value) == [0x71])
			}
		}
	}

	@Test func deleteCurrentEntryRemovesOnlyCurrent() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "cdel")
		try withTxn(env) { tx in
			for i in [UInt8(1), 2] {
				try withVal([i]) { key in
					try withVal([i]) { value in
						try MDB_db_set_entry(db:db, key:key, value:value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			let key = MDB_val()
			let value = MDB_val()
			let entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_FIRST, key:key, value:value)
			#expect(bytes(from:entry.key) == [1])
			try MDB_cursor_delete_current_entry(cursor:cursor, flags:0)
		}
		// key [1] is gone, key [2] remains
		try withCursorTxn(env, db:db) { cursor in
			withVal([1]) { key in
				let value = MDB_val()
				do {
					let _ = try MDB_cursor_get_entry(cursor:cursor, op:MDB_SET, key:key, value:value)
					Issue.record("expected the deleted key to be gone")
				} catch let error {
					#expect(isErr(error, .notFound))
				}
			}
			try withVal([2]) { key in
				let value = MDB_val()
				let entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_SET, key:key, value:value)
				#expect(bytes(from:entry.value) == [2])
			}
		}
	}

	// - MARK: contains via cursor

	@Test func containsEntryThroughCursor() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "ccontain", flags:UInt32(MDB_CREATE) | UInt32(MDB_DUPSORT))
		try withTxn(env) { tx in
			for v in [UInt8(1), 2, 3] {
				try withVal([0x60]) { key in
					try withVal([v]) { value in
						try MDB_db_set_entry(db:db, key:key, value:value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			try withVal([0x60]) { key in
				let presentKey = try MDB_cursor_contains_entry(cursor:cursor, key:key)
				#expect(presentKey == true)
			}
			try withVal([0x61]) { key in
				let absentKey = try MDB_cursor_contains_entry(cursor:cursor, key:key)
				#expect(absentKey == false)
			}
			try withVal([0x60]) { key in
				try withVal([2]) { present in
					let presentPair = try MDB_cursor_contains_entry(cursor:cursor, key:key, value:present)
					#expect(presentPair == true)
				}
			}
			try withVal([0x60]) { key in
				try withVal([9]) { absent in
					let absentPair = try MDB_cursor_contains_entry(cursor:cursor, key:key, value:absent)
					#expect(absentPair == false)
				}
			}
		}
	}

	// - MARK: duplicates

	@Test func dupCountReflectsDuplicates() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "dups", flags:UInt32(MDB_CREATE) | UInt32(MDB_DUPSORT))
		try withTxn(env) { tx in
			for v in [UInt8(1), 2, 3, 4] {
				try withVal([0x01]) { key in
					try withVal([v]) { value in
						try MDB_db_set_entry(db:db, key:key, value:value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			try withVal([0x01]) { key in
				let value = MDB_val()
				let _ = try MDB_cursor_get_entry(cursor:cursor, op:MDB_SET_KEY, key:key, value:value)
			}
			let count = try MDB_cursor_get_dupcount(cursor:cursor)
			#expect(count == 4)
			// walk every duplicate via FIRST_DUP then NEXT_DUP
			var seen:[UInt8] = []
			var op = MDB_FIRST_DUP
			while true {
				let dupKey = MDB_val()
				let dupValue = MDB_val()
				do {
					let entry = try MDB_cursor_get_entry(cursor:cursor, op:op, key:dupKey, value:dupValue)
					seen.append(bytes(from:entry.value)[0])
					op = MDB_NEXT_DUP
				} catch let error where isErr(error, .notFound) {
					break
				}
			}
			#expect(seen == [1, 2, 3, 4])
		}
	}

	@Test func nextNoDupSkipsDuplicates() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "nodup", flags:UInt32(MDB_CREATE) | UInt32(MDB_DUPSORT))
		try withTxn(env) { tx in
			for v in [UInt8(1), 2, 3] {  // three dups under key 1
				try withVal([0x01]) { key in
					try withVal([v]) { value in
						try MDB_db_set_entry(db:db, key:key, value:value, flags:0, tx:tx)
					}
				}
			}
			try withVal([0x02]) { key in  // one entry under key 2
				try withVal([4]) { value in
					try MDB_db_set_entry(db:db, key:key, value:value, flags:0, tx:tx)
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			var key = MDB_val()
			var value = MDB_val()
			var entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_FIRST, key:key, value:value)
			#expect(bytes(from:entry.key) == [0x01])
			key = MDB_val()
			value = MDB_val()
			entry = try MDB_cursor_get_entry(cursor:cursor, op:MDB_NEXT_NODUP, key:key, value:value)
			#expect(bytes(from:entry.key) == [0x02])
		}
	}

	// - MARK: comparisons

	@Test func compareKeysAndValues() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "cmp", flags:UInt32(MDB_CREATE) | UInt32(MDB_DUPSORT))
		let tx = try env.txn()
		defer { mdb_txn_abort(tx) }

		withVal([3]) { lhs in
			withVal([5]) { rhs in
				#expect(MDB_cursor_compare_keys(tx:tx, db:db, lhs:lhs, rhs:rhs) < 0)
			}
		}
		withVal([3]) { lhs in
			withVal([5]) { rhs in
				#expect(MDB_cursor_compare_values(tx:tx, db:db, lhs:lhs, rhs:rhs) < 0)
			}
		}
		withVal([3]) { lhs in
			withVal([3]) { equal in
				#expect(MDB_cursor_compare_keys(tx:tx, db:db, lhs:lhs, rhs:equal) == 0)
			}
		}
		withVal([3]) { lhs in
			withVal([3]) { equal in
				#expect(MDB_cursor_compare_values(tx:tx, db:db, lhs:lhs, rhs:equal) == 0)
			}
		}
		withVal([3]) { lhs in
			withVal([9]) { rhs in
				#expect(MDB_cursor_compare_keys(tx:tx, db:db, lhs:lhs, rhs:rhs) < 0)
			}
		}
		withVal([9]) { lhs in
			withVal([3]) { rhs in
				#expect(MDB_cursor_compare_keys(tx:tx, db:db, lhs:lhs, rhs:rhs) > 0)
			}
		}
	}
}
