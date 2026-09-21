import Testing
import Foundation
import QuickLMDB
import RAW

// runtime pins for the CHILD composition semantics of `#MDB_transacted`:
// a joined write runs in a CHILD transaction of the caller's current tx —
// success FOLDS into the caller; failure aborts ONLY the child, so a catching
// caller keeps its prior writes (selective rollback). an uncaught join failure
// still aborts the whole boundary (atomicity preserved). joins nest as
// child-of-child; multi-environment joins spawn one child per environment.

enum ChildSemanticsError: Error {
	case boom
}

@MDB_environment(file: "child.mdb", flags: [.noSubDir])
public struct ChildSemanticsCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>

	@MDB_transact(.readWrite)
	public func put(_ key: TestKey, _ value: TestValue) throws {
		try #store(ChildSemanticsCore.self, database: \.primary, key: key, value: value)
	}

	@MDB_transact(.readWrite)
	public func putOrFail(_ key: TestKey, _ value: TestValue, fail: Bool) throws {
		try #store(ChildSemanticsCore.self, database: \.primary, key: key, value: value)
		if fail { throw ChildSemanticsError.boom }
	}

	// the selective-rollback shape: write A, JOIN a failing write B inside a
	// catch, continue, then finish. the joined child aborts alone; A survives.
	@MDB_transact(.readWrite)
	public func selective(_ aKey: TestKey, _ bKey: TestKey, bFails: Bool) throws {
		try #store(ChildSemanticsCore.self, database: \.primary, key: aKey, value: TestValue(RAW_native: 10))
		do {
			try #MDB_transacted(putOrFail(bKey, TestValue(RAW_native: 20), fail: bFails))
		} catch {
			// the joined child was discarded — our uncommitted write remains
		}
		try #store(ChildSemanticsCore.self, database: \.primary, key: TestKey(RAW_native: 99), value: TestValue(RAW_native: 90))
	}

	// uncaught join failure → the whole boundary (root) aborts: all-or-nothing.
	@MDB_transact(.readWrite)
	public func allOrNothing(_ aKey: TestKey) throws {
		try #store(ChildSemanticsCore.self, database: \.primary, key: aKey, value: TestValue(RAW_native: 1))
		try #MDB_transacted(putOrFail(TestKey(RAW_native: 2), TestValue(RAW_native: 2), fail: true))
	}

	// written before the join with no failure — folding is invisible at commit
	@MDB_transact(.readWrite)
	public func joinedWriteFoldsDurably(_ key: TestKey) throws {
		try #MDB_transacted(put(key, TestValue(RAW_native: 7)))
		try #store(ChildSemanticsCore.self, database: \.primary, key: TestKey(RAW_native: 3), value: TestValue(RAW_native: 3))
	}

	// depth two: outer joins middle, middle joins put — child of a child
	@MDB_transact(.readWrite)
	public func outer(_ key: TestKey) throws {
		_ = try #stats(ChildSemanticsCore.self, database: \.primary)   // anchors the env set
		try #MDB_transacted(middle(key))
	}

	@MDB_transact(.readWrite)
	public func middle(_ key: TestKey) throws {
		_ = try #stats(ChildSemanticsCore.self, database: \.primary)   // anchors the env set
		try #MDB_transacted(put(key, TestValue(RAW_native: 77)))
	}
}

@MDB_environment(file: "childb.mdb", flags: [.noSubDir])
public struct ChildSemanticsSide: Sendable {
	public let env: Environment
	public let table: Database.Strict<TestKey, TestValue>

	@MDB_transact(.readWrite)
	public func put(_ key: TestKey, _ value: TestValue) throws {
		try #store(ChildSemanticsSide.self, database: \.table, key: key, value: value)
	}
}

@MDB_environment(file: "childa.mdb", flags: [.noSubDir])
public struct ChildSemanticsMain: Sendable {
	public let env: Environment
	public let table: Database.Strict<TestKey, TestValue>

	// a multi-environment callee (env set == caller's {Main, Side}): writes both
	@MDB_transact(.readWrite)
	public func both(_ key: TestKey, side: ChildSemanticsSide) throws {
		try #store(ChildSemanticsMain.self, database: \.table, key: key, value: TestValue(RAW_native: 1))
		try #store(ChildSemanticsSide.self, database: \.table, key: key, value: TestValue(RAW_native: 2))
	}

	// caller holds BOTH env labels (verbs anchor the set) and joins `both` —
	// one child per environment, both folding into the caller's txns
	@MDB_transact(.readWrite)
	public func joinBoth(_ key: TestKey, side: ChildSemanticsSide) throws {
		try #store(ChildSemanticsMain.self, database: \.table, key: key, value: TestValue(RAW_native: 0))
		try #store(ChildSemanticsSide.self, database: \.table, key: key, value: TestValue(RAW_native: 0))
		try #MDB_transacted(both(key, side: side))
	}
}

@Suite("child semantics — #MDB_transacted composition")
struct ChildSemanticsRuntimeTests {

	@Test func selectiveRollbackCatchingCallerKeepsPriorWrites() throws {
		let core = try ChildSemanticsCore.open(at: TestHelpers.tempDirPath())
		// the joined write FAILS → its child is discarded; the caller's writes survive
		try core.selective(TestKey(RAW_native: 1), TestKey(RAW_native: 2), bFails: true)
		let present = try core.primary.readCommitted(key: TestKey(RAW_native: 1))
		let absent = try core.primary.readCommitted(key: TestKey(RAW_native: 2))
		let tail = try core.primary.readCommitted(key: TestKey(RAW_native: 99))
		#expect(present == TestValue(RAW_native: 10))
		#expect(absent == nil)   // the failed joined child's write never landed
		#expect(tail == TestValue(RAW_native: 90))
	}

	@Test func successfulJoinFoldsIntoTheBoundary() throws {
		let core = try ChildSemanticsCore.open(at: TestHelpers.tempDirPath())
		try core.selective(TestKey(RAW_native: 1), TestKey(RAW_native: 2), bFails: false)
		let both = try core.primary.readCommitted(key: TestKey(RAW_native: 2))
		#expect(both == TestValue(RAW_native: 20))   // the joined child committed → folded → durable
	}

	@Test func uncaughtJoinFailureStillAbortsTheBoundary() throws {
		let core = try ChildSemanticsCore.open(at: TestHelpers.tempDirPath())
		var didThrow = false
		do {
			try core.allOrNothing(TestKey(RAW_native: 1))
		} catch {
			didThrow = true
		}
		#expect(didThrow)
		let a = try core.primary.readCommitted(key: TestKey(RAW_native: 1))
		let b = try core.primary.readCommitted(key: TestKey(RAW_native: 2))
		#expect(a == nil)   // atomicity preserved: the boundary's own write is gone too
		#expect(b == nil)
	}

	@Test func joinedWriteFoldsDurably() throws {
		let core = try ChildSemanticsCore.open(at: TestHelpers.tempDirPath())
		try core.joinedWriteFoldsDurably(TestKey(RAW_native: 1))
		let folded = try core.primary.readCommitted(key: TestKey(RAW_native: 1))
		let own = try core.primary.readCommitted(key: TestKey(RAW_native: 3))
		#expect(folded == TestValue(RAW_native: 7))
		#expect(own == TestValue(RAW_native: 3))
	}

	@Test func nestedJoinDepthTwoFoldsDurably() throws {
		let core = try ChildSemanticsCore.open(at: TestHelpers.tempDirPath())
		try core.outer(TestKey(RAW_native: 5))
		let v = try core.primary.readCommitted(key: TestKey(RAW_native: 5))
		#expect(v == TestValue(RAW_native: 77))   // grandchild → child → root, all folded
	}

	@Test func multiEnvJoinSpawnsChildrenPerEnvironment() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-child-multi-\(UUID().uuidString)", isDirectory: true)
		var step = "open main"
		do {
			let main = try ChildSemanticsMain.open(at: root.appendingPathComponent("main").path)
			step = "open side"
			let side = try ChildSemanticsSide.open(at: root.appendingPathComponent("side").path)
			step = "joinBoth"
			try main.joinBoth(TestKey(RAW_native: 4), side: side)
			step = "read main"
			let mainV = try main.table.readCommitted(key: TestKey(RAW_native: 4))
			step = "read side"
			let sideV = try side.table.readCommitted(key: TestKey(RAW_native: 4))
			step = "assert"
			#expect(mainV == TestValue(RAW_native: 1))    // written inside the joined child on Main
			#expect(sideV == TestValue(RAW_native: 2))    // written inside the joined child on Side
		} catch {
			Issue.record("multiEnv failed at step '\(step)': \(error)")
			throw error
		}
	}
}
