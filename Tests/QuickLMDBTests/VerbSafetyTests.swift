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
		// the @MDB_environment-generated open(at:) creates the directory as needed
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-verbs-\(UUID().uuidString)", isDirectory:true)
		return try TestCore.open(at: dir.path)
	}

	@Test func userHelperNamedSetEntryRunsUntouched() throws {
		let core = try makeCore()
		let label = "hello"
		let n = try core.userHelperNamedLikeOperation(TestKey(RAW_native: 101), TestValue(RAW_native: 10101), label)
		#expect(n == label.count, "the user helper must execute its REAL body — the marker gate kept the call untouched")
		#expect(try core.primary.readCommitted(key:TestKey(RAW_native: 101)) == TestValue(RAW_native: 10101), "the verb write still landed")
	}

	@Test func verbsAndExplicitTxCoexistInOneBoundary() throws {
		let core = try makeCore()
		let key = TestKey(RAW_native: 102)
		try core.verbAndExplicitTxHybrid(key, TestValue(RAW_native: 10202))
		#expect(try core.primary.readCommitted(key:key) == TestValue(RAW_native: 10202))
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

	@Test func statsVerbReportsEntryCount() throws {
		// #stats lowers to dbStatistics(tx:) and reports the live entry count
		let core = try makeCore()
		let entries = (1...5).map { TestKey(RAW_native: UInt32($0 + 200)) }
		let count = try core.statsWorkflow(entries)
		#expect(count == 5, "dbStatistics.ms_entries must report all five stored entries")
	}

	@Test func dropVerbRemovesTheDatabase() throws {
		// #drop consumes a locally-owned raw handle; after commit the named table
		// must be gone from the environment (reopening without .create fails)
		let core = try makeCore()
		let name = "dropme-\(UUID().uuidString)"
		try core.dropWorkflow(name)

		let tx = try Transaction(env: core.env, readOnly: true)
		do {
			_ = try Database(env: core.env, name: name, flags: [], tx: tx)
			Issue.record("expected the dropped database to be gone from the environment")
		} catch let error {
			// Database(env:flags:tx:) throws LMDBError (typed throws)
			#expect(error.returnCode == LMDBError.notFound.returnCode, "the drop must remove the named dbi (open without .create → notFound)")
		}
		tx.abort()
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

	// #stats lowers to dbStatistics(tx:) — a metadata READ through the boundary.
	@MDB_transact(.readWrite)
	public func statsWorkflow(_ entries: [TestKey]) throws -> Int {
		for entry in entries {
			try #store(primary, key: entry, value: TestValue(RAW_native: 1))
		}
		return Int(try #stats(primary).ms_entries)
	}

	// #drop lowers to deleteDatabase(tx:) — the receiver must be a handle the body
	// owns (deleteDatabase CONSUMES it), so a local raw Database opened inside the
	// boundary is dropped; a stored `self.X` table would not compile.
	@MDB_transact(.readWrite)
	public func dropWorkflow(_ name: String) throws {
		let db = try Database(env: env, name: name, flags: [.create], tx: tx)
		try #drop(db)
	}
}
