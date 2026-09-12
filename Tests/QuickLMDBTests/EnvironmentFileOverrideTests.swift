import Testing
import Foundation
import QuickLMDB
import RAW

// runtime pins for the generated open's `fileName:` override — a
// runtime-parameterized environment (one file per configured tenant or base
// symbol) opens through the same macro surface without an ambient naming
// global: the caller supplies the file name at open time and the attribute
// value stays the default.

@MDB_environment(file: "default.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct OverrideCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
}

private enum OverridePaths {
	static func freshDir(_ tag: String) -> String {
		FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-override-\(tag)-\(UUID().uuidString)", isDirectory: true).path
	}
}

@Suite("environment file-name override")
struct EnvironmentFileOverrideTests {

	@Test func defaultUsesTheAttributeName() throws {
		let dir = OverridePaths.freshDir("default")
		_ = try OverrideCore.open(at: dir)
		#expect(FileManager.default.fileExists(atPath: dir + "/default.mdb"))
	}

	@Test func overrideNamesTheEnvironmentFile() throws {
		let dir = OverridePaths.freshDir("override")
		let core = try OverrideCore.open(at: dir, fileName: "tenant-42.mdb")
		#expect(FileManager.default.fileExists(atPath: dir + "/tenant-42.mdb"))
		#expect(!FileManager.default.fileExists(atPath: dir + "/default.mdb"))

		// the named environment actually reads and writes
		let k = TestKey(RAW_native: 7)
		let v = TestValue(RAW_native: 700)
		let tx = try Transaction<Write>(env: core.env)
		try core.primary.store(key: k, value: v, tx: tx)
		try tx.commit()
		#expect(try core.primary.readCommitted(key: k) == v)
	}

	@Test func versionSuffixAppliesToTheOverriddenName() throws {
		let dir = OverridePaths.freshDir("override-version")
		_ = try VersionOneCore.open(at: dir, fileName: "custom.mdb")
		#expect(FileManager.default.fileExists(atPath: dir + "/custom-v1.mdb"))
		#expect(!FileManager.default.fileExists(atPath: dir + "/custom.mdb"))
		#expect(!FileManager.default.fileExists(atPath: dir + "/events-v1.mdb"))
	}
}
