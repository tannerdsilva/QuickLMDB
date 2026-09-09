import Testing
import Foundation
import QuickLMDB

// Transaction relationship management — pinning LMDB's engine-default behavior for every
// parent/child and sibling combination under test, so that a future LMDB release that
// changes any of these semantics breaks this suite loudly.
//
// the policy baked into the macros is deliberately minimal: every boundary opens a
// TOP-LEVEL transaction of its requested mode; children are created only through the
// explicit `.readWriteChild(parent:)` route. everything else is the engine's own default,
// enforced here:
//
//   readWrite under read         -> sibling write (legal; commits independently)
//   readOnly  under write        -> sibling read (last-committed snapshot)
//   readOnly  under read (.noTLS)-> sibling read (legal because .noTLS owns the slot)
//   readOnly  under read (TLS)   -> badReaderSlot (engine default)
//   write child under write parent    -> merges into the parent
//   write child under read parent     -> invalidParameter (EINVAL, engine default)
//
// FORBIDDEN PATTERN (NOT a test — the engine deadlocks):
//   calling a `.readWrite` boundary inside another `.readWrite` boundary WITHOUT an
//   explicit `parent:` argument. lmdb's `mdb_txn_begin` has no guard for a second
//   top-level write on a thread — it reuses the preallocated `me_txn0` and blocks on the
//   thread's own non-recursive writer mutex. composition inside a write boundary MUST use
//   `.readWriteChild(parent:)`; this suite consequently never exercises the raw pattern.

@Suite("Transaction relationship management (engine defaults)")
struct TransactionRelationshipTests {

	private func makeEnv(_ extraFlags: Environment.Flags = []) throws -> Environment {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-rel-\(UUID().uuidString)", isDirectory:true)
		try FileManager.default.createDirectory(at:dir, withIntermediateDirectories:true)
		let path = dir.appendingPathComponent("rel.mdb", isDirectory:false)
		return try Environment(path:path.path, flags:Environment.Flags([.noSubDir]).union(extraFlags), mapSize:1024 * 1024, maxReaders:16, maxDBs:4, mode:[.ownerReadWriteExecute, .groupRead, .otherRead])
	}

	// - MARK: @MDB_environment contract

	@Test func environmentMacroForcesNoTLS() throws {
		let core = try TestHelpers.makeCore()
		#expect(core.env.flags.contains(.noTLS))
	}

	// - MARK: sibling relationships (the standing defaults)

	@Test func readOnlyInsideReadWriteIsSiblingReadOfCommittedData() throws {
		// the inner read is its own top-level read transaction: it sees the state as of
		// the LAST COMMIT, not the enclosing write's uncommitted view.
		let core = try TestCore.open(at: TestHelpers.tempDirPath())
		let key = TestKey(RAW_native: 51)
		let unseen = TestValue(RAW_native: 5151)
		let visible = TestValue(RAW_native: 777)

		// write+commit visible
		try core.writePrimary(key, visible)

		// inside one write boundary: set a value (uncommitted), then sibling-read — must NOT see it
		let observedMidWrite = try core.writeThenSiblingRead(key, uncommitted: unseen)
		#expect(observedMidWrite == visible, "sibling read must observe the last committed state, not the enclosing write's uncommitted data")

		// engine-default: sibling write under an open read is legal; the read boundary's
		// snapshot stays pre-write, and the sibling write persists beyond the read's abort
		let another = TestValue(RAW_native: 9999)
		let observedDuringWrite = try core.siblingReadThenWrite(key, committed: another)
		#expect(observedDuringWrite == unseen, "the outer read boundary's snapshot predates the sibling write (it sees the state committed before it)")
		let persisted = try core.primary.readCommitted(key: key)
		#expect(persisted == another, "the sibling write committed independently and survived the read boundary's close")
	}

	@Test func readOnlyInsideReadOnlyIsSiblingReadWithNoTLS() throws {
		let core = try TestCore.open(at: TestHelpers.tempDirPath())
		let key = TestKey(RAW_native: 52)
		try core.writePrimary(key, TestValue(RAW_native: 101))
		// inner read boundary inside an outer read boundary: both succeed because the
		// environment is .noTLS (each transaction owns its reader slot)
		let value = try core.outerReadThenInnerRead(key)
		#expect(value == TestValue(RAW_native: 101))
	}

	@Test func readOnlyInsideReadOnlyThrowsBadReaderSlotWithoutNoTLS() throws {
		// the TLS contrast: WITHOUT .noTLS, a thread has a single reader slot, so a second
		// top-level read throws badReaderSlot. pinned so a future LMDB change is spotted.
		let env = try makeEnv()   // default: no .noTLS
		let r1 = try Transaction(env:env, readOnly:true)
		do {
			_ = try Transaction(env:env, readOnly:true)
			Issue.record("expected a second read transaction to fail without .noTLS")
			r1.abort()
		} catch let error {
			#expect(error.returnCode == LMDBError.badReaderSlot.returnCode)
			r1.abort()
		}
	}

	// - MARK: child relationships (explicit parent)

	@Test func writeChildUnderWriteParentIsLegalAndMerges() throws {
		let core = try TestCore.open(at: TestHelpers.tempDirPath())
		let key = TestKey(RAW_native: 53)
		// existing `outerWrite`: parent boundary writes, then a .readWriteChild(& parent: tx)
		// writes the same key — the child merges into the parent on commit
		try core.outerWrite(key, TestValue(RAW_native: 414), key, TestValue(RAW_native: 515))
		let p = try core.primary.readCommitted(key: key)
		#expect(p == TestValue(RAW_native: 515))
	}

	@Test func writeChildUnderReadParentThrowsEngineDefault() throws {
		// LMDB's default for a write CHILD whose parent is a read transaction is EINVAL.
		let env = try makeEnv()
		let readParent = try Transaction(env:env, readOnly:true)
		do {
			_ = try Transaction(env:env, readOnly:false, parent:readParent)
			Issue.record("expected a write child under a read parent to fail")
			readParent.abort()
		} catch let error {
			#expect(error.returnCode == LMDBError.invalidParameter.returnCode)
			readParent.abort()
		}
	}
}
