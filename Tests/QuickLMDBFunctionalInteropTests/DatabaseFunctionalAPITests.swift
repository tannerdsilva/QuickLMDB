import Testing
import CLMDB
import QuickLMDBFunctionalInterop
#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

// comprehensive coverage of the database-level functional interop surface,
// driven against real LMDB through raw CLMDB handles.

@Suite("Database functional interop")
struct DatabaseFunctionalAPITests {

	private func withEnv<T>(_ body:(RawEnv) throws -> T) throws -> T {
		let env = try RawEnv()
		defer { env.close() }
		return try body(env)
	}

	// - MARK: get / set

	@Test func setThenGetRoundTrips() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db(nil, tx:tx)
				try withVal([0xAA, 0xBB]) { key in
					try withVal([1, 2, 3, 4]) { value in
						try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
					}
				}
				try withVal([0xAA, 0xBB]) { key in
					let out = try MDB_db_get_entry(db:dbi, key:key, tx:tx)
					#expect(bytes(from:out) == [1, 2, 3, 4])
				}
			}
		}
	}

	@Test func getMissingKeyThrowsNotFound() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db(nil, tx:tx)
				withVal([0x01]) { key in
					do {
						_ = try MDB_db_get_entry(db:dbi, key:key, tx:tx)
						Issue.record("expected notFound for a missing key")
					} catch let error {
						#expect(isErr(error, .notFound))
					}
				}
			}
		}
	}

	@Test func setOverwritesByDefault() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db(nil, tx:tx)
				try withVal([0x07]) { key in
					try withVal([1]) { value in
						try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
					}
				}
				try withVal([0x07]) { key in
					try withVal([2]) { value in
						try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
					}
				}
				try withVal([0x07]) { key in
					let out = try MDB_db_get_entry(db:dbi, key:key, tx:tx)
					#expect(bytes(from:out) == [2])
				}
			}
		}
	}

	@Test func setNoOverwriteThrowsKeyExists() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db(nil, tx:tx)
				try withVal([0x08]) { key in
					try withVal([1]) { value in
						try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
					}
				}
				withVal([0x08]) { key in
					withVal([2]) { value in
						do {
							try MDB_db_set_entry(db:dbi, key:key, value:value, flags:UInt32(MDB_NOOVERWRITE), tx:tx)
							Issue.record("expected keyExists for a repeated no-overwrite put")
						} catch let error {
							#expect(isErr(error, .keyExists))
						}
					}
				}
			}
		}
	}

	// - MARK: pointer provenance

	@Test func getReturnsMapPointerDistinctFromInput() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db(nil, tx:tx)
				try withVal([0xAA, 0xBB]) { key in
					try withVal([1, 2, 3, 4]) { value in
						try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
					}
				}
				// the returned value must point into the memory map, never at the caller's key buffer
				try withVal([0xAA, 0xBB]) { key in
					let keyPtr = key.mv_data
					let out = try MDB_db_get_entry(db:dbi, key:key, tx:tx)
					#expect(out.mv_data != nil, "get must return a live value pointer")
					#expect(out.mv_data != keyPtr, "get must not return the caller-provided key pointer")
					#expect(bytes(from:out) == [1, 2, 3, 4])
				}
			}
		}
	}

	// - MARK: contains

	@Test func containsEntryReportsPresence() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db(nil, tx:tx)
				try withVal([0x10]) { key in
					try withVal([9]) { value in
						try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
					}
				}
				try withVal([0x10]) { key in
					let presentResult = try MDB_db_contains_entry(db:dbi, key:key, tx:tx)
					#expect(presentResult == true)
				}
				try withVal([0x11]) { missing in
					let missingResult = try MDB_db_contains_entry(db:dbi, key:missing, tx:tx)
					#expect(missingResult == false)
				}
			}
		}
	}

	// - MARK: delete

	@Test func deleteByKeyRemovesEntry() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db(nil, tx:tx)
				try withVal([0x30]) { key in
					try withVal([1]) { value in
						try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
					}
				}
				try withVal([0x30]) { key in
					try MDB_db_delete_entry(db:dbi, key:key, tx:tx)
				}
				withVal([0x30]) { key in
					do {
						_ = try MDB_db_get_entry(db:dbi, key:key, tx:tx)
						Issue.record("expected notFound after delete")
					} catch let error {
						#expect(isErr(error, .notFound))
					}
				}
			}
		}
	}

	@Test func deleteMissingKeyThrowsNotFound() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db(nil, tx:tx)
				withVal([0x31]) { key in
					do {
						try MDB_db_delete_entry(db:dbi, key:key, tx:tx)
						Issue.record("expected notFound when deleting a missing key")
					} catch let error {
						#expect(isErr(error, .notFound))
					}
				}
			}
		}
	}

	@Test func deleteKeyValueRemovesSingleDup() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db("dupdel", flags:UInt32(MDB_CREATE) | UInt32(MDB_DUPSORT), tx:tx)
				try withVal([0x32]) { key in
					try withVal([1]) { value in
						try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
					}
				}
				try withVal([0x32]) { key in
					try withVal([2]) { value in
						try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
					}
				}
				// delete exactly one duplicate; mdb_get then returns the FIRST remaining dup
				try withVal([0x32]) { key in
					try withVal([1]) { value in
						try MDB_db_delete_entry(db:dbi, key:key, value:value, tx:tx)
					}
				}
				try withVal([0x32]) { key in
					let out = try MDB_db_get_entry(db:dbi, key:key, tx:tx)
					let remaining = bytes(from:out)
					#expect(remaining == [2], "the [1] duplicate should be deleted, leaving [2] first")
				}
				// deleting the remaining [2] leaves nothing for the key
				try withVal([0x32]) { key in
					try withVal([2]) { value in
						try MDB_db_delete_entry(db:dbi, key:key, value:value, tx:tx)
					}
				}
				withVal([0x32]) { key in
					do {
						_ = try MDB_db_get_entry(db:dbi, key:key, tx:tx)
						Issue.record("expected notFound after deleting the last duplicate")
					} catch let error {
						#expect(isErr(error, .notFound))
					}
				}
			}
		}
	}

	// - MARK: table-wide

	@Test func deleteAllEntriesEmptiesTheTable() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db(nil, tx:tx)
				for i in 0..<5 {
					try withVal([UInt8(i)]) { key in
						try withVal([1]) { value in
							try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
						}
					}
				}
				try MDB_db_delete_all_entries(db:dbi, tx:tx)
				let stats = try MDB_db_get_statistics(db:dbi, tx:tx)
				#expect(stats.ms_entries == 0)
				withVal([0x00]) { key in
					do {
						_ = try MDB_db_get_entry(db:dbi, key:key, tx:tx)
						Issue.record("expected notFound after deleteAllEntries")
					} catch let error {
						#expect(isErr(error, .notFound))
					}
				}
			}
		}
	}

	@Test func deleteDatabaseInvalidatesHandle() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db("subtable", flags:UInt32(MDB_CREATE), tx:tx)
				try withVal([0x40]) { key in
					try withVal([1]) { value in
						try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
					}
				}
				try withVal([0x40]) { key in
					let size = try MDB_db_get_entry(db:dbi, key:key, tx:tx).mv_size
					#expect(size == 1)
				}
				try MDB_db_delete_database(db:dbi, tx:tx)
				withVal([0x40]) { key in
					do {
						_ = try MDB_db_get_entry(db:dbi, key:key, tx:tx)
						Issue.record("expected the dropped database handle to be invalid")
					} catch let error {
						// LMDB returns EINVAL for reads through a dropped database handle — pinned
						// so a future LMDB release that changes this surfaces loudly.
						guard let lmdbError = error as? LMDBError else {
							Issue.record("expected LMDBError but got \(error)")
							return
						}
						#expect(lmdbError.returnCode == Int32(EINVAL), "actual returnCode: \(lmdbError.returnCode)")
					}
				}
			}
		}
	}

	// - MARK: metadata

	@Test func statisticsReflectEntryCount() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db(nil, tx:tx)
				for i in 0..<7 {
					try withVal([UInt8(i)]) { key in
						try withVal([1]) { value in
							try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
						}
					}
				}
				let stats = try MDB_db_get_statistics(db:dbi, tx:tx)
				#expect(stats.ms_entries == 7)
				try withVal([0x03]) { key in
					try MDB_db_delete_entry(db:dbi, key:key, tx:tx)
				}
				let after = try MDB_db_get_statistics(db:dbi, tx:tx)
				#expect(after.ms_entries == 6)
			}
		}
	}

	@Test func dbFlagsReported() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let plain = try env.db(nil, flags:UInt32(MDB_CREATE), tx:tx)
				let plainFlags = try MDB_db_get_flags(db:plain, tx:tx)
				#expect(plainFlags & UInt32(MDB_DUPSORT) == 0)

				let dup = try env.db("dups", flags:UInt32(MDB_CREATE) | UInt32(MDB_DUPSORT), tx:tx)
				let dupFlags = try MDB_db_get_flags(db:dup, tx:tx)
				#expect(dupFlags & UInt32(MDB_DUPSORT) != 0)
			}
		}
	}

	// - MARK: compare functions

	private let reverseByteCmp:MDB_cmp_func_t = { lhs, rhs in
		let left = lhs!.pointee.mv_data!.load(as:UInt8.self)
		let right = rhs!.pointee.mv_data!.load(as:UInt8.self)
		return Int32(right) - Int32(left)
	}

	@Test func assignCompareKeyReversesIterationOrder() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db(nil, flags:UInt32(MDB_CREATE), tx:tx)
				MDB_db_assign_compare_key(db:dbi, compare:reverseByteCmp, tx:tx)
				for i in [UInt8(1), 2, 3] {
					try withVal([i]) { key in
						try withVal([0]) { value in
							try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
						}
					}
				}
				let cursor = try env.cursor(in:tx, db:dbi)
				defer { mdb_cursor_close(cursor) }
				var seen:[UInt8] = []
				var keyVal = MDB_val()
				var valueVal = MDB_val()
				var op = MDB_FIRST
				var rc = mdb_cursor_get(cursor, &keyVal, &valueVal, op)
				while rc == MDB_SUCCESS {
					seen.append(bytes(from:keyVal)[0])
					op = MDB_NEXT
					keyVal = MDB_val()
					valueVal = MDB_val()
					rc = mdb_cursor_get(cursor, &keyVal, &valueVal, op)
				}
				#expect(seen == [3, 2, 1])
			}
		}
	}

	@Test func assignCompareValReversesDupOrder() throws {
		try withEnv { env in
			try withTxn(env) { tx in
				let dbi = try env.db("dupval", flags:UInt32(MDB_CREATE) | UInt32(MDB_DUPSORT), tx:tx)
				MDB_db_assign_compare_val(db:dbi, compare:reverseByteCmp, tx:tx)
				for v in [UInt8(1), 2, 3] {
					try withVal([0x50]) { key in
						try withVal([v]) { value in
							try MDB_db_set_entry(db:dbi, key:key, value:value, flags:0, tx:tx)
						}
					}
				}
				let cursor = try env.cursor(in:tx, db:dbi)
				defer { mdb_cursor_close(cursor) }
				// FIRST_DUP requires a positioned cursor — position at the key first
				let positionValue = MDB_val()
				try withVal([0x50]) { key in
					let positioned = try MDB_cursor_get_entry(cursor:cursor, op:MDB_SET_KEY, key:key, value:positionValue)
					_ = positioned
				}
				var seen:[UInt8] = []
				var keyVal = MDB_val()
				var valueVal = MDB_val()
				var op = MDB_FIRST_DUP
				var rc = mdb_cursor_get(cursor, &keyVal, &valueVal, op)
				while rc == MDB_SUCCESS {
					seen.append(bytes(from:valueVal)[0])
					op = MDB_NEXT_DUP
					keyVal = MDB_val()
					valueVal = MDB_val()
					rc = mdb_cursor_get(cursor, &keyVal, &valueVal, op)
				}
				#expect(seen == [3, 2, 1])
			}
		}
	}
}
