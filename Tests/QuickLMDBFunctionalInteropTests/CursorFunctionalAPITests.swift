import Testing
import CLMDB
import QuickLMDBFunctionalInterop

// comprehensive coverage of the cursor-level functional interop statics,
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
				try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_FIRST, key:&key, value:&value)
				Issue.record("expected notFound for first on an empty database")
			} catch let error {
				#expect(isErr(error, .notFound))
			}
			do {
				try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_LAST, key:&key, value:&value)
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
						try MDB_db_set_entry_static(db:db, key:&key, value:&value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			var key = MDB_val()
			var value = MDB_val()
			try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_FIRST, key:&key, value:&value)
			#expect(bytes(from:key) == [0])
			try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_NEXT, key:&key, value:&value)
			#expect(bytes(from:key) == [1])
			try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_NEXT, key:&key, value:&value)
			#expect(bytes(from:key) == [2])
			// stepping past the end throws notFound
			do {
				try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_NEXT, key:&key, value:&value)
				Issue.record("expected notFound past the end")
			} catch let error {
				#expect(isErr(error, .notFound))
			}
			try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_PREV, key:&key, value:&value)
			#expect(bytes(from:key) == [1])
			try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_PREV, key:&key, value:&value)
			#expect(bytes(from:key) == [0])
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
						try MDB_db_set_entry_static(db:db, key:&key, value:&value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			var value = MDB_val()
			try withVal([15]) { seek in
				var seekKey = seek
				try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_SET_RANGE, key:&seekKey, value:&value)
				#expect(bytes(from:seekKey) == [20])
			}
			try withVal([30]) { seek in
				var seekKey = seek
				try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_SET_RANGE, key:&seekKey, value:&value)
				#expect(bytes(from:seekKey) == [30])
			}
			withVal([99]) { seek in
				var seekKey = seek
				do {
					try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_SET_RANGE, key:&seekKey, value:&value)
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
					try MDB_db_set_entry_static(db:db, key:&key, value:&value, flags:0, tx:tx)
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			var value = MDB_val()
			try withVal([0x55]) { key in
				try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_SET, key:&key, value:&value)
				#expect(bytes(from:value) == [0xAA])
			}
			withVal([0x56]) { key in
				do {
					try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_SET, key:&key, value:&value)
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
						try MDB_db_set_entry_static(db:db, key:&key, value:&value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			var key = MDB_val()
			var value = MDB_val()
			try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_FIRST, key:&key, value:&value)
			try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_GET_CURRENT, key:&key, value:&value)
			#expect(bytes(from:key) == [1])
			try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_NEXT, key:&key, value:&value)
			try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_GET_CURRENT, key:&key, value:&value)
			#expect(bytes(from:key) == [2])
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
					try MDB_cursor_set_entry_static(cursor:cursor, key:&key, value:&value, flags:0)
				}
			}
		}
		// the write committed with the cursor's transaction — verified through a fresh read
		try withCursorTxn(env, db:db) { cursor in
			var value = MDB_val()
			try withVal([0x70]) { key in
				try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_SET, key:&key, value:&value)
				#expect(bytes(from:value) == [0x71])
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
						try MDB_db_set_entry_static(db:db, key:&key, value:&value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			var key = MDB_val()
			var value = MDB_val()
			try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_FIRST, key:&key, value:&value)
			#expect(bytes(from:key) == [1])
			try MDB_cursor_delete_current_entry_static(cursor:cursor, flags:0)
		}
		// key [1] is gone, key [2] remains
		try withCursorTxn(env, db:db) { cursor in
			var value = MDB_val()
			withVal([1]) { key in
				do {
					try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_SET, key:&key, value:&value)
					Issue.record("expected the deleted key to be gone")
				} catch let error {
					#expect(isErr(error, .notFound))
				}
			}
			try withVal([2]) { key in
				try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_SET, key:&key, value:&value)
				#expect(bytes(from:value) == [2])
			}
		}
	}

	// - MARK: contains via cursor

	@Test func containsEntryThroughCursor() throws {
		let env = try RawEnv()
		defer { env.close() }
		let db = try openDB(env, "ccontain", flags:UInt32(MDB_CREATE) | UInt32(MDB_DUPSORT))
		try withTxn(env) { tx in
			try withVal([0x60]) { key in
				for v in [UInt8(1), 2, 3] {
					try withVal([v]) { value in
						try MDB_db_set_entry_static(db:db, key:&key, value:&value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			try withVal([0x60]) { key in
				let presentKey = try MDB_cursor_contains_entry_static(cursor:cursor, key:&key)
				#expect(presentKey == true)
			}
			try withVal([0x61]) { key in
				let absentKey = try MDB_cursor_contains_entry_static(cursor:cursor, key:&key)
				#expect(absentKey == false)
			}
			try withVal([0x60]) { key in
				try withVal([2]) { present in
					let presentPair = try MDB_cursor_contains_entry_static(cursor:cursor, key:&key, value:&present)
					#expect(presentPair == true)
				}
				try withVal([9]) { absent in
					let absentPair = try MDB_cursor_contains_entry_static(cursor:cursor, key:&key, value:&absent)
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
			try withVal([0x01]) { key in
				for v in [UInt8(1), 2, 3, 4] {
					try withVal([v]) { value in
						try MDB_db_set_entry_static(db:db, key:&key, value:&value, flags:0, tx:tx)
					}
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			var key = MDB_val()
			var value = MDB_val()
			try withVal([0x01]) { key in
				try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_SET_KEY, key:&key, value:&value)
			}
			let count = try MDB_cursor_get_dupcount_static(cursor:cursor)
			#expect(count == 4)
			// walk every duplicate via FIRST_DUP then NEXT_DUP
			var seen:[UInt8] = []
			var op = MDB_FIRST_DUP
			while true {
				key = MDB_val()
				value = MDB_val()
				do {
					try MDB_cursor_get_entry_static(cursor:cursor, op:op, key:&key, value:&value)
					seen.append(bytes(from:value)[0])
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
			try withVal([0x01]) { key in  // three dups under key 1
				for v in [UInt8(1), 2, 3] {
					try withVal([v]) { value in
						try MDB_db_set_entry_static(db:db, key:&key, value:&value, flags:0, tx:tx)
					}
				}
			}
			try withVal([0x02]) { key in  // one entry under key 2
				try withVal([4]) { value in
					try MDB_db_set_entry_static(db:db, key:&key, value:&value, flags:0, tx:tx)
				}
			}
		}
		try withCursorTxn(env, db:db) { cursor in
			var key = MDB_val()
			var value = MDB_val()
			try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_FIRST, key:&key, value:&value)
			#expect(bytes(from:key) == [0x01])
			try MDB_cursor_get_entry_static(cursor:cursor, op:MDB_NEXT_NODUP, key:&key, value:&value)
			#expect(bytes(from:key) == [0x02])
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
				#expect(MDB_cursor_compare_keys_static(tx:tx, db:db, lhs:&lhs, rhs:&rhs) < 0)
				#expect(MDB_cursor_compare_values_static(tx:tx, db:db, lhs:&lhs, rhs:&rhs) < 0)
			}
			withVal([3]) { equal in
				#expect(MDB_cursor_compare_keys_static(tx:tx, db:db, lhs:&lhs, rhs:&equal) == 0)
				#expect(MDB_cursor_compare_values_static(tx:tx, db:db, lhs:&lhs, rhs:&equal) == 0)
			}
			withVal([9]) { rhs in
				#expect(MDB_cursor_compare_keys_static(tx:tx, db:db, lhs:&lhs, rhs:&rhs) < 0)
				#expect(MDB_cursor_compare_keys_static(tx:tx, db:db, lhs:&rhs, rhs:&lhs) > 0)
			}
		}
	}
}
