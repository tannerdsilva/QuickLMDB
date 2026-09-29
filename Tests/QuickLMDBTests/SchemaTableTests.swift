import Testing
import Foundation
import QuickLMDB

// schema layer — port phase 1, real engine: `@MDB_table` name override and
// extra flags must produce actually-openable tables with the resolved names
// and the type-strict comparators intact.

@MDB_environment(file: "schema_table.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct TableLabCore: Sendable {
	public let env: Environment
	@MDB_table(name: "event_log", flags: [.reverseKey])
	public let events: Database.Strict<TestKey, TestValue>
	@MDB_table(flags: [.dupSort, .dupFixed])
	public let blobs: Database
}

@Suite("schema layer — @MDB_table on the real engine")
struct SchemaTableTests {

	@Test func tableAttributesOpenTheRealTables() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-schema-\(UUID().uuidString)", isDirectory: true)
		let core = try TableLabCore.open(at: dir.path)

		// the resolved names are the real on-disk names
		#expect(core.events.dbName() == "event_log")
		#expect(core.blobs.dbName() == "blobs")

		// the renamed/flagged table is fully functional (raw tx round-trip)
		let key = TestKey(RAW_native: 1)
		let value = TestValue(RAW_native: 10)
		let write = try Transaction<Write>(env: core.env)
		try core.events.setEntry(key: key, value: value, flags: [], tx: write)
		try write.commit()

		let read = try Transaction<Read>(env: core.env)
		let loaded = core.events.load(key: key, tx: read)
		read.abort()
		#expect(loaded == value)
	}
}


// single-sourced names: `@MDB_table(name:)` may reference a same-core member
// (e.g. the `Databases` enum) instead of duplicating the on-disk name as a
// literal — this was the peer-macro circular reference, fixed by giving the
// @MDB_table peer a FIXED name set.
@MDB_environment(file: "schema_single_source.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct SingleSourceCore: Sendable {
	private enum Tables: String {
		case hostEvents = "host_events"
		case blobStore = "blob_store"
	}
	public let env: Environment
	@MDB_table(name: Tables.hostEvents.rawValue)
	public let events: Database.Strict<TestKey, TestValue>
	@MDB_table(name: Tables.blobStore.rawValue)
	public let blobs: Database
}

@Suite("schema layer — single-sourced table names (same-core member references)")
struct SingleSourceTableTests {

	@Test func memberReferencedNamesResolveToTheEnumValues() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-single-source-\(UUID().uuidString)", isDirectory: true)
		let core = try SingleSourceCore.open(at: dir.path)

		#expect(core.events.dbName() == "host_events")
		#expect(core.blobs.dbName() == "blob_store")

		let key = TestKey(RAW_native: 3)
		let value = TestValue(RAW_native: 30)
		let write = try Transaction<Write>(env: core.env)
		try core.events.setEntry(key: key, value: value, flags: [], tx: write)
		try write.commit()

		let read = try Transaction<Read>(env: core.env)
		let loaded = core.events.load(key: key, tx: read)
		read.abort()
		#expect(loaded == value)
	}
}
