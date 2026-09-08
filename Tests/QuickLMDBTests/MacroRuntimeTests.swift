import Testing
import Foundation
import SystemPackage
import QuickLMDB
import RAW

// runtime verification for the @MDB_environment and @MDB_transact macros in the
// body-macro architecture: `@MDB_transact` is an attached body macro that rewrites the
// method body in place (no ambient storage); `@MDB_environment` generates the schema
// `open(at:)`. every test runs against a real LMDB environment in a unique temp
// directory (parallel-safe).

@RAW_staticbuff(bytes:4)
@RAW_staticbuff_fixedwidthinteger_type<UInt32>(bigEndian:true)
@MDB_comparable
@frozen public struct TestKey:Sendable, Hashable, Equatable, Comparable {}

@RAW_staticbuff(bytes:8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian:true)
@MDB_comparable
@frozen public struct TestValue:Sendable, Hashable, Equatable, Comparable {}

public enum TestError:Error {
	case simulatedFailure
}

@MDB_environment(file: "test.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct TestCore:Sendable {
	public let env:Environment
	public let primary:Database.Strict<TestKey, TestValue>
	public let secondary:Database.DupSort<TestKey, TestValue>
}

// - MARK: transaction boundary methods (bodies rewritten in place by @MDB_transact)

extension TestCore {

	@MDB_transact(.readWrite)
	public func writePrimary(_ key: consuming TestKey, _ value: consuming TestValue) throws {
		try primary.setEntry(key: key, value: value, flags: [])
	}

	@MDB_transact(.readWrite)
	public func writeBoth(_ key: consuming TestKey, _ primaryValue: consuming TestValue, _ secondaryValue: consuming TestValue) throws {
		try primary.setEntry(key: key, value: primaryValue, flags: [])
		try secondary.setEntry(key: key, value: secondaryValue, flags: [])
	}

	@MDB_transact(.readWrite)
	public func writeBothThrowing(_ key: consuming TestKey, _ primaryValue: consuming TestValue, _ secondaryValue: consuming TestValue) throws {
		try primary.setEntry(key: key, value: primaryValue, flags: [])
		try secondary.setEntry(key: key, value: secondaryValue, flags: [])
		throw TestError.simulatedFailure
	}

	@MDB_transact(.readOnly)
	public func readOnlyRead(_ key: borrowing TestKey) throws -> TestValue? {
		return try? primary.loadEntry(key: key, as: TestValue.self)
	}

	@MDB_transact(.readOnly)
	public func readOnlyWriteAttempt(_ key: consuming TestKey, _ value: consuming TestValue) throws {
		try primary.setEntry(key: key, value: value, flags: [])
	}

	// explicit parent-free composition: the injected `tx` is passed to a shared helper
	@MDB_transact(.readWrite)
	public func writePrimaryViaHelper(_ key: consuming TestKey, _ value: consuming TestValue) throws {
		try storeHelper(key, value, tx: tx)
	}

	// shared helper taking an explicit transaction (unchanged API shape)
	public func storeHelper(_ key: borrowing TestKey, _ value: consuming TestValue, tx: borrowing Transaction) throws {
		try primary.setEntry(key: key, value: value, flags: [], tx: tx)
	}
}

extension TestCore {

	// child transaction boundary: parent merges on commit, aborts independently on error
	@MDB_transact(.readWriteChild)
	public func writeNested(_ key: consuming TestKey, _ value: consuming TestValue, parent: borrowing Transaction) throws {
		try primary.setEntry(key: key, value: value, flags: [])
	}

	@MDB_transact(.readWriteChild)
	public func writeNestedThrowing(_ key: consuming TestKey, _ value: consuming TestValue, parent: borrowing Transaction) throws {
		try primary.setEntry(key: key, value: value, flags: [])
		throw TestError.simulatedFailure
	}

	@MDB_transact(.readWrite)
	public func outerWrite(_ key: consuming TestKey, _ value: consuming TestValue, _ innerKey: consuming TestKey, _ innerValue: consuming TestValue) throws {
		try primary.setEntry(key: key, value: value, flags: [])
		try writeNested(innerKey, innerValue, parent: tx)
	}

	@MDB_transact(.readWrite)
	public func outerWriteChildAbort(_ key: consuming TestKey, _ value: consuming TestValue, _ innerKey: consuming TestKey, _ innerValue: consuming TestValue) throws {
		try primary.setEntry(key: key, value: value, flags: [])
		do {
			try writeNestedThrowing(innerKey, innerValue, parent: tx)
		} catch TestError.simulatedFailure {
			// child aborted; parent scope remains usable
		}
	}

	// child boundary READS its parent's uncommitted state — the defining child semantic.
	// the parent boundary below writes without committing, then asks the child for its view.
	@MDB_transact(.readWriteChild)
	public func readParentUncommitted(_ key: borrowing TestKey, parent: borrowing Transaction) throws -> TestValue? {
		return try? primary.loadEntry(key: key, as: TestValue.self)
	}

	@MDB_transact(.readWrite)
	public func childSeesParentUncommitted(_ key: borrowing TestKey, _ value: consuming TestValue) throws -> TestValue? {
		try primary.setEntry(key: key, value: value, flags: [])   // uncommitted at this point
		return try readParentUncommitted(key, parent: tx)         // the child must see it
	}

	// misuse surfaced through the macro path: a .readWriteChild boundary is handed a READ
	// boundary's transaction as `parent:`. the child's Transaction init rejects it (EINVAL).
	@MDB_transact(.readOnly)
	public func childUnderReadParentAttempt(_ key: borrowing TestKey) throws -> TestValue? {
		return try attemptChildUnderReadParent(key, parent: tx)
	}

	@MDB_transact(.readWriteChild)
	public func attemptChildUnderReadParent(_ key: borrowing TestKey, parent: borrowing Transaction) throws -> TestValue? {
		try primary.setEntry(key: key, value: TestValue(RAW_native: 1), flags: [])
		return TestValue(RAW_native: 1)
	}

	// multi-level write nesting: a child spawns its own child with ITS injected tx —
	// top -> child -> grandchild, all one atomic unit (probed; now pinned).
	@MDB_transact(.readWriteChild)
	public func writeChildThenGrandchild(_ key: consuming TestKey, _ value: consuming TestValue, _ grandKey: consuming TestKey, _ grandValue: consuming TestValue, parent: borrowing Transaction) throws {
		try primary.setEntry(key: key, value: value, flags: [])
		try writeNested(grandKey, grandValue, parent: tx)   // this child's OWN tx -> grandchild
	}

	@MDB_transact(.readWrite)
	public func outerWriteGrandchild(_ k1: consuming TestKey, _ v1: consuming TestValue, _ k2: consuming TestKey, _ v2: consuming TestValue, _ k3: consuming TestKey, _ v3: consuming TestValue) throws {
		try primary.setEntry(key: k1, value: v1, flags: [])
		try writeChildThenGrandchild(k2, v2, k3, v3, parent: tx)
	}

	@MDB_transact(.readOnly)
	public func scanAll() throws -> [(key: TestKey, value: TestValue)] {
		var result: [(key: TestKey, value: TestValue)] = []
		primary.cursor { cursor in
			for (k, v) in cursor {
				result.append((key: k, value: v))
			}
		}
		return result
	}

	@MDB_transact(.readOnly)
	public func scanCount() throws -> UInt64 {
		var result: UInt64 = 0
		primary.cursor { cursor in
			for _ in cursor {
				result += 1
			}
		}
		return result
	}
}

extension TestCore {
	// direct read path used by assertions — raw Transaction plus the unchanged tx-bearing API
	public func loadEntryDirect(_ key: borrowing TestKey, tx: borrowing Transaction) throws -> TestValue? {
		return try? primary.loadEntry(key: key, as: TestValue.self, tx: tx)
	}
}

// - MARK: harness

@Suite("MDB_transact + MDB_environment runtime (body macro architecture)")
struct MacroRuntimeTests {

	private func makeCore() throws -> TestCore {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-macro-\(UUID().uuidString)", isDirectory:true)
		try FileManager.default.createDirectory(at:dir, withIntermediateDirectories:true)
		return try TestCore.open(at: dir.path)
	}

	private func readViaRawTX(_ core: TestCore, key: TestKey) throws -> TestValue? {
		let tx = try Transaction(env:core.env, readOnly:true)
		do {
			let result = try core.loadEntryDirect(key, tx: tx)
			tx.abort()
			return result
		} catch let error {
			tx.abort()
			throw error
		}
	}

	private func readDupsViaRawTX(_ core: TestCore, key: TestKey) throws -> [TestValue] {
		let tx = try Transaction(env:core.env, readOnly:true)
		var vals:[TestValue] = []
		core.secondary.cursor(tx: tx) { cursor in
			for (_, dup) in cursor.makeDupIterator(key: key) {
				vals.append(dup)
			}
		}
		tx.abort()
		return vals
	}

	private func containsDupViaRawTX(_ core: TestCore, key: TestKey) throws -> Bool {
		let tx = try Transaction(env:core.env, readOnly:true)
		do {
			let result = try core.secondary.containsEntry(key: key, tx: tx)
			tx.abort()
			return result
		} catch let error {
			tx.abort()
			throw error
		}
	}

	@Test func environmentOpenAndSingleWriteCommits() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 7)
		let value = TestValue(RAW_native: 700)
		try core.writePrimary(key, value)
		let readBack = try readViaRawTX(core, key: key)
		#expect(readBack == value)
	}

	@Test func atomicMultiTableWrite() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 9)
		try core.writeBoth(key, TestValue(RAW_native: 100), TestValue(RAW_native: 200))
		let p = try readViaRawTX(core, key: key)
		#expect(p == TestValue(RAW_native: 100))
		let s = try readDupsViaRawTX(core, key: key)
		#expect(s == [TestValue(RAW_native: 200)])
	}

	@Test func throwingBoundaryRollsBackEverything() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 11)
		do {
			try core.writeBothThrowing(key, TestValue(RAW_native: 300), TestValue(RAW_native: 400))
			Issue.record("expected the boundary to throw")
		} catch is TestError {
			// expected
		}
		let p = try readViaRawTX(core, key: key)
		#expect(p == nil)
		let s = try containsDupViaRawTX(core, key: key)
		#expect(s == false)
	}

	@Test func childBoundaryCommitsIntoParent() throws {
		let core = try makeCore()
		let outerKey = TestKey(RAW_native: 21)
		let innerKey = TestKey(RAW_native: 22)
		try core.outerWrite(outerKey, TestValue(RAW_native: 1), innerKey, TestValue(RAW_native: 2))
		#expect(try readViaRawTX(core, key: outerKey) == TestValue(RAW_native: 1))
		#expect(try readViaRawTX(core, key: innerKey) == TestValue(RAW_native: 2))
	}

	@Test func childAbortLeavesParentUsable() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 31)
		let innerKey = TestKey(RAW_native: 32)
		try core.outerWriteChildAbort(key, TestValue(RAW_native: 99), innerKey, TestValue(RAW_native: 100))
		// parent write persists; the aborted child's write is rolled back
		#expect(try readViaRawTX(core, key: key) == TestValue(RAW_native: 99))
		#expect(try readViaRawTX(core, key: innerKey) == nil)
	}

	@Test func childSeesParentUncommittedWrites() throws {
		// the defining parent/child contract: a child transaction operates on its parent's
		// VIEW — it must observe writes the parent has made but not yet committed.
		let core = try makeCore()
		let key = TestKey(RAW_native: 71)
		let value = TestValue(RAW_native: 710)
		let seen = try core.childSeesParentUncommitted(key, value)
		#expect(seen == value, "a child boundary must see its parent's uncommitted writes")
		// and the whole unit is durable after the parent commits
		#expect(try readViaRawTX(core, key: key) == value)
	}

	@Test func writeChildUnderReadParentThrowsThroughMacro() throws {
		// the same EINVAL the raw API pins, surfaced through real boundaries: passing a
		// .readOnly boundary's injected tx as `parent:` to a .readWriteChild boundary.
		let core = try makeCore()
		do {
			_ = try core.childUnderReadParentAttempt(TestKey(RAW_native: 81))
			Issue.record("expected a .readWriteChild boundary under a .readOnly parent boundary to throw")
		} catch let error as LMDBError {
			#expect(error.returnCode == LMDBError.invalidParameter.returnCode)
		}
	}

	@Test func multiLevelWriteNestingCommitsAtomically() throws {
		// top -> child -> grandchild: each level spawns the next with its own injected tx;
		// all three writes must land together (the journal's "probed" claim, now pinned).
		let core = try makeCore()
		let (k1, k2, k3) = (TestKey(RAW_native: 91), TestKey(RAW_native: 92), TestKey(RAW_native: 93))
		try core.outerWriteGrandchild(k1, TestValue(RAW_native: 1), k2, TestValue(RAW_native: 2), k3, TestValue(RAW_native: 3))
		#expect(try readViaRawTX(core, key: k1) == TestValue(RAW_native: 1))
		#expect(try readViaRawTX(core, key: k2) == TestValue(RAW_native: 2))
		#expect(try readViaRawTX(core, key: k3) == TestValue(RAW_native: 3))
	}

	@Test func explicitTxHelperComposition() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 41)
		try core.writePrimaryViaHelper(key, TestValue(RAW_native: 222))
		#expect(try readViaRawTX(core, key: key) == TestValue(RAW_native: 222))
	}

	@Test func readOnlyBoundaryReads() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 5)
		try core.writePrimary(key, TestValue(RAW_native: 555))
		let read = try core.readOnlyRead(key)
		#expect(read == TestValue(RAW_native: 555))
	}

	@Test func writeInsideReadOnlyBoundaryThrows() throws {
		let core = try makeCore()
		do {
			try core.readOnlyWriteAttempt(TestKey(RAW_native: 2), TestValue(RAW_native: 20))
			Issue.record("expected a write inside a read-only boundary to fail")
		} catch let error as LMDBError {
			// LMDB rejects writes on a read-only transaction with EACCES
			#expect(error.returnCode == LMDBError.accessViolation.returnCode)
		}
	}

	@Test func cursorCallsAreBoundInsideBoundary() throws {
		let core = try makeCore()
		for i in 0..<10 {
			let k = TestKey(RAW_native: 1000 + UInt32(i))
			try core.writePrimary(k, TestValue(RAW_native: UInt64(i)))
		}
		let all = try core.scanAll()
		#expect(all.count == 10)
		let count = try core.scanCount()
		#expect(count == 10)
	}

	@Test func worksOnBareDispatchThread() throws {
		// no storage of any kind is used by the boundary — dispatch threads are trivially safe
		let core = try makeCore()
		let key = TestKey(RAW_native: 61)
		try DispatchQueue(label:"qlmdb-bare-thread-\(UUID().uuidString)").sync {
			try core.writePrimary(key, TestValue(RAW_native: 610))
		}
		#expect(try readViaRawTX(core, key: key) == TestValue(RAW_native: 610))
	}
}
