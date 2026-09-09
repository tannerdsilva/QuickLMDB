import Testing
import Foundation
import QuickLMDB

// runtime safety tests for marker-gated verb lowering (Phase 4):
//   - a user-defined `setEntry(_ label: String)` method (unrelated shape) called
//     inside a boundary must run untouched — the rewriter cannot reach plain
//     calls anymore (the OLD name-list would have appended tx: and broken this)
//   - verbs and explicit-tx: method calls coexist in one boundary
//   - runtime exercises of #cursor / #clear / #delete(key:value:) on a dup-sort table
// (expansion-level coverage lives in MDB_transactExpansionTests; these run the
// generated code for real.)

@Suite("Verb marker-gating runtime safety")
struct VerbSafetyTests {

	private func makeCore() throws -> TestCore {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-verbs-\(UUID().uuidString)", isDirectory:true)
		try FileManager.default.createDirectory(at:dir, withIntermediateDirectories:true)
		return try TestCore.open(at: dir.path)
	}

	private func readViaRawTX(_ core: TestCore, key: TestKey) throws -> TestValue? {
		let tx = try Transaction(env:core.env, readOnly:true)
		let result = try? core.primary.loadEntry(key:key, as:TestValue.self, tx:tx)
		tx.abort()
		return result
	}

	@Test func userHelperNamedSetEntryRunsUntouched() throws {
		let core = try makeCore()
		let label = "hello"
		let n = try core.userHelperNamedLikeOperation(TestKey(RAW_native: 101), TestValue(RAW_native: 10101), label)
		#expect(n == label.count, "the user helper must execute its REAL body — the marker gate kept the call untouched")
		#expect(try readViaRawTX(core, key:TestKey(RAW_native: 101)) == TestValue(RAW_native: 10101), "the verb write still landed")
	}

	@Test func verbsAndExplicitTxCoexistInOneBoundary() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 102)
		try core.verbAndExplicitTxHybrid(key, TestValue(RAW_native: 10202))
		#expect(try readViaRawTX(core, key:key) == TestValue(RAW_native: 10202))
	}

	@Test func dupWorkflowVerbsDeletePairAndScan() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 103)
		let dups = [TestValue(RAW_native: 1), TestValue(RAW_native: 2), TestValue(RAW_native: 3)]

		let remaining = try core.dupWorkflow(key, dups, TestValue(RAW_native: 2))
		#expect(remaining == 2, "pair delete removed exactly one dup; two remain")

		let tx = try Transaction(env:core.env, readOnly:true)
		var seen:[TestValue] = []
		core.secondary.cursor(tx:tx) { cursor in
			for (_, dup) in cursor.makeDupIterator(key:key) {
				seen.append(dup)
			}
		}
		tx.abort()
		#expect(seen == [TestValue(RAW_native: 1), TestValue(RAW_native: 3)], "only the un-deleted pairings survive")
	}

	@Test func clearWorkflowVerbsEmptyTheTable() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 104)
		let dups = [TestValue(RAW_native: 7), TestValue(RAW_native: 8)]
		let cleared = try core.clearWorkflow(key, dups)
		#expect(cleared == true, "#contains must report false after #clear")
	}
}

// the boundary bodies, on TestCore. the regression case proves the marker gate:
// `TestCore.setEntry(_ label: String) -> Int` is a plain method the rewriter
// must NEVER touch (the old name-list would have rewritten it and broken the
// compile); it is genuinely reachable from inside a boundary body.
extension TestCore {

	/// a NON-database member named like the operation. the old name-list
	/// attribution would have appended `tx:` to calls of this and broken them;
	/// the marker gate leaves them byte-identical.
	public func setEntry(_ label: String) -> Int {
		return label.count
	}

	@MDB_transact(.readWrite)
	public func userHelperNamedLikeOperation(_ key: consuming TestKey, _ value: consuming TestValue, _ label: String) throws -> Int {
		try #store(primary, key: key, value: value)
		// a plain method call named `setEntry` — must pass through untouched
		return setEntry(label)
	}

	@MDB_transact(.readWrite)
	public func verbAndExplicitTxHybrid(_ key: consuming TestKey, _ value: consuming TestValue) throws {
		// setEntry consumes its value, so an explicit copy is taken up front and
		// carries the second write; the original goes through the verb.
		let valueCopy = value
		// verb form (auto-threaded)
		try #store(primary, key: key, value: value)
		// explicit-tx form on the same table in the same boundary — both must land
		try primary.setEntry(key: key, value: valueCopy, flags: [], tx: tx)
	}

	@MDB_transact(.readWrite)
	public func dupWorkflow(_ key: consuming TestKey, _ dups: [TestValue], _ remove: TestValue) throws -> Int {
		for dup in dups {
			try #store(secondary, key: key, value: dup)
		}
		// pair delete: exact key/value pairing removed from the dup set
		try #delete(secondary, key: key, value: remove)
		// cursor scan counts what remains
		var count = 0
		#cursor(secondary) { cursor in
			for (_, _) in cursor.makeDupIterator(key: key) {
				count += 1
			}
		}
		return count
	}

	@MDB_transact(.readWrite)
	public func clearWorkflow(_ key: consuming TestKey, _ dups: [TestValue]) throws -> Bool {
		for dup in dups {
			try #store(secondary, key: key, value: dup)
		}
		try #clear(secondary)
		return (try #contains(secondary, key: key)) == false
	}
}
