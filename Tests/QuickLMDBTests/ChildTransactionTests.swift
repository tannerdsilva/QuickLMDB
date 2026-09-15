import Testing
import Foundation
import QuickLMDB
import RAW

// engine pins for NESTED (child) transactions — the composition relationship
// behind `#MDB_transacted`. an LMDB child:
//   - must be opened on the SAME environment as its WRITE parent;
//   - sees the parent's snapshot AND its uncommitted writes;
//   - on child.commit() FOLDS its writes into the parent (nothing durable yet);
//   - on child.abort() discards ONLY its own writes (the parent is unharmed);
//   - children may be parents in turn (arbitrary depth);
//   - a parent cannot be closed while a child is open.

@Suite("engine — child (nested) transactions")
struct ChildTransactionTests {

	private func freshCore() throws -> TestCore {
		try TestCore.open(at: TestHelpers.tempDirPath())
	}

	@Test func childFoldsIntoParentOnCommitNothingDurable() throws {
		let core = try freshCore()
		let parent = try Transaction<Write>(env: core.env)
		try core.primary.store(key: TestKey(RAW_native: 1), value: TestValue(RAW_native: 10), tx: parent)

		let child = try Transaction<Write>(env: core.env, parent: parent)
		try core.primary.store(key: TestKey(RAW_native: 2), value: TestValue(RAW_native: 20), tx: child)
		try child.commit()   // folds INTO the parent

		// the folded child write is visible through the STILL-OPEN parent...
		let viaParent = core.primary.load(key: TestKey(RAW_native: 2), tx: parent)
		#expect(viaParent == TestValue(RAW_native: 20))
		// ...but is NOT durable yet (parent uncommitted — a committed-only read sees nothing)
		let notDurable = try core.primary.readCommitted(key: TestKey(RAW_native: 2))
		#expect(notDurable == nil)

		try parent.commit()
		let after1 = try core.primary.readCommitted(key: TestKey(RAW_native: 1))
		let after2 = try core.primary.readCommitted(key: TestKey(RAW_native: 2))
		#expect(after1 == TestValue(RAW_native: 10))
		#expect(after2 == TestValue(RAW_native: 20))
	}

	@Test func childSeesParentUncommittedWrites() throws {
		let core = try freshCore()
		let parent = try Transaction<Write>(env: core.env)
		try core.primary.store(key: TestKey(RAW_native: 7), value: TestValue(RAW_native: 70), tx: parent)

		let child = try Transaction<Write>(env: core.env, parent: parent)
		let seen = core.primary.load(key: TestKey(RAW_native: 7), tx: child)
		#expect(seen == TestValue(RAW_native: 70))
		child.abort()
		parent.abort()
	}

	@Test func childAbortDiscardsOnlyTheChild() throws {
		let core = try freshCore()
		let parent = try Transaction<Write>(env: core.env)
		try core.primary.store(key: TestKey(RAW_native: 1), value: TestValue(RAW_native: 10), tx: parent)

		let child = try Transaction<Write>(env: core.env, parent: parent)
		try core.primary.store(key: TestKey(RAW_native: 2), value: TestValue(RAW_native: 20), tx: child)
		child.abort()   // selective rollback: only the child's write is discarded

		// the parent's own write survives, the child's is gone
		let parent1 = core.primary.load(key: TestKey(RAW_native: 1), tx: parent)
		let parent2 = core.primary.load(key: TestKey(RAW_native: 2), tx: parent)
		#expect(parent1 == TestValue(RAW_native: 10))
		#expect(parent2 == nil)

		try parent.commit()
		let after1 = try core.primary.readCommitted(key: TestKey(RAW_native: 1))
		let after2 = try core.primary.readCommitted(key: TestKey(RAW_native: 2))
		#expect(after1 == TestValue(RAW_native: 10))
		#expect(after2 == nil)
	}

	@Test func parentAbortDiscardsTheFoldedChildToo() throws {
		let core = try freshCore()
		let parent = try Transaction<Write>(env: core.env)
		let child = try Transaction<Write>(env: core.env, parent: parent)
		try core.primary.store(key: TestKey(RAW_native: 5), value: TestValue(RAW_native: 50), tx: child)
		try child.commit()   // folds into parent
		parent.abort()       // parent abort discards parent + everything folded in

		let after = try core.primary.readCommitted(key: TestKey(RAW_native: 5))
		#expect(after == nil)
	}

	@Test func grandChildNestingFoldsDurably() throws {
		let core = try freshCore()
		let parent = try Transaction<Write>(env: core.env)
		let child = try Transaction<Write>(env: core.env, parent: parent)
		let grandchild = try Transaction<Write>(env: core.env, parent: child)
		try core.primary.store(key: TestKey(RAW_native: 3), value: TestValue(RAW_native: 30), tx: grandchild)
		try grandchild.commit()   // folds into child
		try child.commit()        // folds into parent
		try parent.commit()       // durable
		let after = try core.primary.readCommitted(key: TestKey(RAW_native: 3))
		#expect(after == TestValue(RAW_native: 30))
	}

	/// NOTE: this LMDB build does NOT guard the close order — committing a
	/// parent while a child is open silently succeeds (empirically verified,
	/// CLMDB here). the macro therefore guarantees ordering by construction
	/// (every child closes before the parent commits); the raw surface must
	/// honor the same rule. this pin asserts the SHAPE our generated code
	/// produces: abort a child, CONTINUE writing on the parent, then commit.
	@Test func abortedChildThenParentContinuesAndCommits() throws {
		let core = try freshCore()
		let parent = try Transaction<Write>(env: core.env)
		try core.primary.store(key: TestKey(RAW_native: 1), value: TestValue(RAW_native: 10), tx: parent)

		let child = try Transaction<Write>(env: core.env, parent: parent)
		try core.primary.store(key: TestKey(RAW_native: 2), value: TestValue(RAW_native: 20), tx: child)
		child.abort()                    // the child's portion is discarded

		// the parent keeps working AFTER the child closed and commits durably
		try core.primary.store(key: TestKey(RAW_native: 3), value: TestValue(RAW_native: 30), tx: parent)
		try parent.commit()
		let a = try core.primary.readCommitted(key: TestKey(RAW_native: 1))
		let b = try core.primary.readCommitted(key: TestKey(RAW_native: 2))
		let c = try core.primary.readCommitted(key: TestKey(RAW_native: 3))
		#expect(a == TestValue(RAW_native: 10))
		#expect(b == nil)   // the aborted child's write never landed
		#expect(c == TestValue(RAW_native: 30))
	}

	@Test func childTxnIsClosedByDeinitWithoutTouchingTheParent() throws {
		let core = try freshCore()
		let parent = try Transaction<Write>(env: core.env)
		do {
			let child = try Transaction<Write>(env: core.env, parent: parent)
			try core.primary.store(key: TestKey(RAW_native: 9), value: TestValue(RAW_native: 90), tx: child)
			// child leaves scope unclosed — deinit aborts it; the parent stays usable
		}
		try core.primary.store(key: TestKey(RAW_native: 8), value: TestValue(RAW_native: 80), tx: parent)
		try parent.commit()
		let after8 = try core.primary.readCommitted(key: TestKey(RAW_native: 8))
		let after9 = try core.primary.readCommitted(key: TestKey(RAW_native: 9))
		#expect(after8 == TestValue(RAW_native: 80))
		#expect(after9 == nil)
	}
}
