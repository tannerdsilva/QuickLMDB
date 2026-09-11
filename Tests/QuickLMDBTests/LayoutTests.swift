import Testing
import Foundation
import QuickLMDB
import RAW

// runtime pins for @MDB_layout — the environment ARRANGEMENT helper (every
// environment is its own type; boundaries live ON the core):
//   - a one-core arrangement opens + assembles a fresh instance,
//   - the core inventory,
//   - the dynamic open is exercised through the raw surface.
// per-doctrine, these drive the REAL engine on fresh temp paths.

@MDB_environment(file: "single.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct SingleCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>

	// boundaries live directly on the environment type — no container needed
	@MDB_transact(.readWrite)
	public func store(_ key: TestKey, _ value: TestValue) throws {
		try #store(SingleCore.self, database: \.primary, key: key, value: value)
	}

	@MDB_transact(.readOnly)
	public func load(_ key: TestKey) throws -> TestValue? {
		#load(SingleCore.self, database: \.primary, key: key)
	}
}

// the arrangement: multiple cores owned by one struct, one open
@MDB_layout
public struct SingleApp {
	public var single: SingleCore
}

@Suite("MDB_layout — the arrangement (one-core, dynamic open)")
struct LayoutCoreTests {

	@Test func arrangementOpensFreshInstancesAndPinsTheInventory() throws {
		#expect(SingleApp.mdb_core_names == ["single"])

		let root = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-layout-\(UUID().uuidString)", isDirectory: true)
		let app = try SingleApp.open(at: root.path)

		let key = TestKey(RAW_native: 2)
		let value = TestValue(RAW_native: 7)
		try app.single.store(key, value)
		#expect(try app.single.load(key) == value)
	}
}
