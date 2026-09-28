import Testing
import Foundation
import QuickLMDB
import RAW

// runtime pins for `@MDB_state` — configuration state an environment core owns.
// each marked property becomes a REQUIRED `open` parameter (declaration order) and
// rides into the instance; state is per-instance, never persisted, and never
// touches the transaction layer.

@MDB_environment(file: "state.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct StateCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
	@MDB_state public let tag: String
	@MDB_state public let limit: Int
}

@MDB_environment(flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct TenantStateCore: Sendable {
	public let env: Environment
	@MDB_state public let tag: String
	public let primary: Database.Strict<TestKey, TestValue>
}

private enum StatePaths {
	static func freshDir(_ tag: String) -> String {
		FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-state-\(tag)-\(UUID().uuidString)", isDirectory: true).path
	}
}

@Suite("environment configuration state")
struct StateRuntimeTests {

	@Test func stateRidesIntoTheInstance() throws {
		let dir = StatePaths.freshDir("carry")
		let core = try StateCore.open(at: dir, tag: "alpha", limit: 7)
		#expect(core.tag == "alpha")
		#expect(core.limit == 7)
	}

	@Test func stateIsPerInstanceAndNotPersisted() throws {
		let dir = StatePaths.freshDir("per-instance")
		let key = TestKey(RAW_native: 5)
		let value = TestValue(RAW_native: 500)
		do {
			let first = try StateCore.open(at: dir, tag: "first", limit: 1)
			let tx = try Transaction<Write>(env: first.env)
			try first.primary.store(key: key, value: value, tx: tx)
			try tx.commit()
		}
		let secondRead: TestValue?
		do {
			let second = try StateCore.open(at: dir, tag: "second", limit: 2)
			#expect(second.tag == "second", "state is supplied per open — never remembered from the file")
			#expect(second.limit == 2)
			secondRead = try second.primary.readCommitted(key: key)
		}
		#expect(secondRead == value, "state does not disturb the stored data")
	}

	@Test func stateComposesWithRuntimeFileNames() throws {
		let dir = StatePaths.freshDir("tenant-state")
		let key = TestKey(RAW_native: 9)
		let value = TestValue(RAW_native: 900)
		let read: TestValue?
		do {
			let core = try TenantStateCore.open(at: dir, fileName: "tenant-a.mdb", tag: "tenant-a")
			#expect(core.tag == "tenant-a")
			let tx = try Transaction<Write>(env: core.env)
			try core.primary.store(key: key, value: value, tx: tx)
			try tx.commit()
			read = try core.primary.readCommitted(key: key)
		}
		#expect(read == value)
		#expect(FileManager.default.fileExists(atPath: dir + "/tenant-a.mdb"))
	}
}