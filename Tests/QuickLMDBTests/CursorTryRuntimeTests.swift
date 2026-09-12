import Testing
import Foundation
import QuickLMDB
import RAW

// runtime compile pins for the cursor-try resolution (DEBT item 4). the
// closures below are NON-throwing (or `#if`-gated), so every `try #cursor`
// site here warned with "no calls to throwing functions occur within 'try'
// expression" before the fix; the emitted explicitly-`throws` closure makes
// `try` unconditionally correct. the no-`try` spelling on a pure closure
// (the wiremand/pricedb shape) must keep compiling.

@MDB_environment(file: "cursortry.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct CursorTryCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
}

extension CursorTryCore {

	// non-throwing closure under `try` — the pricedb warning shape
	@MDB_transact(.readOnly)
	func collectKeys() throws -> [TestKey] {
		var keys: [TestKey] = []
		try #cursor(CursorTryCore.self, database: \.primary) { c in
			for (k, _) in c.makeIterator() {
				keys.append(k)
			}
		}
		return keys
	}

	// `#if`-gated throwing set under `try` — must compile in BOTH
	// configurations, warning-free
	@MDB_transact(.readOnly)
	func collectKeysIfGated() throws -> [TestKey] {
		var keys: [TestKey] = []
		try #cursor(CursorTryCore.self, database: \.primary) { c in
			#if CURSOR_TRY_TRACE
			_ = try c.opSet(key: TestKey(RAW_native: 0))
			#endif
			for (k, _) in c.makeIterator() {
				keys.append(k)
			}
		}
		return keys
	}

	// no-`try` spelling on a pure closure stays legal (the `Never` path)
	@MDB_transact(.readOnly)
	func countEntriesNoTry() throws -> Int {
		var count = 0
		#cursor(CursorTryCore.self, database: \.primary) { c in
			for (_, _) in c.makeIterator() {
				count += 1
			}
		}
		return count
	}
}

@Suite("cursor closure try — runtime compile pins")
struct CursorTryRuntimeTests {
	private func freshCore() throws -> CursorTryCore {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-cursortry-\(UUID().uuidString)", isDirectory: true)
		let core = try CursorTryCore.open(at: dir.path)
		let tx = try Transaction<Write>(env: core.env)
		try core.primary.store(key: TestKey(RAW_native: 1), value: TestValue(RAW_native: 10), tx: tx)
		try core.primary.store(key: TestKey(RAW_native: 2), value: TestValue(RAW_native: 20), tx: tx)
		try tx.commit()
		return core
	}

	@Test func nonThrowingCursorClosuresRoundTrip() throws {
		let core = try freshCore()
		#expect(try core.collectKeys() == [TestKey(RAW_native: 1), TestKey(RAW_native: 2)])
		#expect(try core.collectKeysIfGated() == [TestKey(RAW_native: 1), TestKey(RAW_native: 2)])
		#expect(try core.countEntriesNoTry() == 2)
	}
}
