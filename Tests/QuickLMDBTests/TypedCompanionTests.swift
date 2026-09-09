import Testing
import Foundation
import QuickLMDB

// runtime verification for the typed-handle companions that the verb-macro
// vocabulary lowers to (see Source/QuickLMDB/Database/DBTypedConvenience.swift):
//   store(key:value:flags:tx:) / load(key:tx:) / delete(key:tx:) /
//   delete(key:value:tx:) (dupsort) / contains(key:tx:)
// the companions are protocol-extension members of MDB_db, so they apply to
// every typed handle (Strict/DupSort/DupFixed) plus the raw Database.

@Suite("MDB_db typed companions (verb-lowering surface)")
struct TypedCompanionTests {

	private func makeCore() throws -> TestCore {
		// the @MDB_environment-generated open(at:) creates the directory as needed
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-comp-\(UUID().uuidString)", isDirectory:true)
		return try TestCore.open(at: dir.path)
	}

	@Test func storeThenLoadRoundTrip() throws {
		// store via the companion, read back with the same companion through a raw tx
		let core = try makeCore()
		let key = TestKey(RAW_native: 1)
		let value = TestValue(RAW_native: 100)
		let write = try Transaction(env:core.env, readOnly:false)
		try core.primary.store(key:key, value:value, tx:write)
		try write.commit()

		let read = try Transaction(env:core.env, readOnly:true)
		let loaded = core.primary.load(key:key, tx:read)
		read.abort()
		#expect(loaded == value)
	}

	@Test func loadMissingKeyReturnsNil() throws {
		let core = try makeCore()
		let read = try Transaction(env:core.env, readOnly:true)
		let loaded = core.primary.load(key:TestKey(RAW_native: 2), tx:read)
		read.abort()
		#expect(loaded == nil)
	}

	@Test func deleteRemovesEntry() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 3)
		try core.writePrimary(key, TestValue(RAW_native: 300))
		#expect(try core.primary.readCommitted(key:key) == TestValue(RAW_native: 300))

		let write = try Transaction(env:core.env, readOnly:false)
		try core.primary.delete(key:key, tx:write)
		try write.commit()

		#expect(try core.primary.readCommitted(key:key) == nil)
	}

	@Test func containsReflectsPresence() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 4)
		let read = try Transaction(env:core.env, readOnly:true)
		let firstResult = try core.primary.contains(key:key, tx:read)
		#expect(firstResult == false)
		read.abort()

		try core.writePrimary(key, TestValue(RAW_native: 400))

		let read2 = try Transaction(env:core.env, readOnly:true)
		let secondResult = try core.primary.contains(key:key, tx:read2)
		#expect(secondResult == true)
		read2.abort()
	}

	@Test func storeHonorsNoOverwriteFlag() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 5)
		let write = try Transaction(env:core.env, readOnly:false)
		try core.primary.store(key:key, value:TestValue(RAW_native: 500), tx:write)
		try write.commit()

		// the same key with .noOverwrite must reject as keyExists (default flags would overwrite)
		let write2 = try Transaction(env:core.env, readOnly:false)
		do {
			try core.primary.store(key:key, value:TestValue(RAW_native: 501), flags:[.noOverwrite], tx:write2)
			Issue.record("expected .noOverwrite on an existing key to throw keyExists")
		} catch let error as LMDBError {
			#expect(error.returnCode == LMDBError.keyExists.returnCode)
		}
		write2.abort()
	}

	@Test func dupsortPairDeleteRemovesOnlyThePairing() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 6)
		let valueA = TestValue(RAW_native: 601)
		let valueB = TestValue(RAW_native: 602)

		// two dups under one key
		let write = try Transaction(env:core.env, readOnly:false)
		try core.secondary.store(key:key, value:valueA, tx:write)
		try core.secondary.store(key:key, value:valueB, tx:write)
		try write.commit()

		// delete exactly one pairing
		let write2 = try Transaction(env:core.env, readOnly:false)
		try core.secondary.delete(key:key, value:valueA, tx:write2)
		try write2.commit()

		// the other dup survives; the deleted one is gone. the pair check is
		// cursor-only (real MDB_GET_BOTH — the DB-level pair contains was removed
		// as a silent no-op), so assert through the cursor.
		let read = try Transaction(env:core.env, readOnly:true)
		var pairFound = false
		try core.secondary.cursor(tx:read) { cursor in
			pairFound = try cursor.containsEntry(key:key, value:valueB)
		}
		read.abort()
		#expect(pairFound == true, "the surviving pairing must be found via GET_BOTH")
		let dups = try core.secondary.readCommittedDups(key:key)
		#expect(dups == [valueB], "only the surviving dup remains")
	}

	@Test func committedReadsReflectCommittedState() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 7)
		let value = TestValue(RAW_native: 700)
		try core.writePrimary(key, value)

		// readCommitted: self-scoped read txn, last-committed value, missing key -> nil
		#expect(try core.primary.readCommitted(key:key) == value)
		#expect(try core.primary.readCommitted(key:TestKey(RAW_native: 99)) == nil)
		#expect(try core.primary.containsCommitted(key:key) == true)
		#expect(try core.primary.containsCommitted(key:TestKey(RAW_native: 99)) == false)

		// readCommittedDups: dupsort table, absent key -> empty
		let writeTX = try Transaction(env:core.env, readOnly:false)
		try core.secondary.store(key:key, value:TestValue(RAW_native: 701), tx:writeTX)
		try writeTX.commit()
		#expect(try core.secondary.readCommittedDups(key:key) == [TestValue(RAW_native: 701)])
		#expect(try core.secondary.readCommittedDups(key:TestKey(RAW_native: 99)) == [])
	}
}
