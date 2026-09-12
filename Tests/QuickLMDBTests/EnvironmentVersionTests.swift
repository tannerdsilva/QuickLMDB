import Testing
import Foundation
import QuickLMDB
import RAW

// runtime pins for versioned environment files — the schema version rides in
// the FILE NAME (`<stem>-v<N>.mdb`), engaged by WRITING the `version:`
// attribute; a bare core keeps its exact name. the migration convention is new
// file + stream: bumping the version ships a FRESH file, so the new version
// never sees the old version's data, and the old file stays readable.

@MDB_environment(file: "plain.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct PlainCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
}

@MDB_environment(file: "events.mdb", version: 0, flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct VersionZeroCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
}

@MDB_environment(file: "events.mdb", version: 1, flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct VersionOneCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
}

@MDB_environment(file: "events.mdb", version: 2, flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct VersionTwoCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
}

private enum VersionPaths {
	static func freshDir(_ tag: String) -> String {
		FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-version-\(tag)-\(UUID().uuidString)", isDirectory: true).path
	}
}

@Suite("versioned environment filenames")
struct EnvironmentVersionTests {

	@Test func bareCoreKeepsItsExactFileName() throws {
		let dir = VersionPaths.freshDir("bare")
		_ = try PlainCore.open(at: dir)
		#expect(FileManager.default.fileExists(atPath: dir + "/plain.mdb"))
		#expect(!FileManager.default.fileExists(atPath: dir + "/plain-v0.mdb"))
	}

	@Test func versionZeroDerivesTheV0Suffix() throws {
		let dir = VersionPaths.freshDir("v0")
		_ = try VersionZeroCore.open(at: dir)
		#expect(FileManager.default.fileExists(atPath: dir + "/events-v0.mdb"))
		#expect(!FileManager.default.fileExists(atPath: dir + "/events.mdb"))
	}

	@Test func versionTwoDerivesTheV2Suffix() throws {
		let dir = VersionPaths.freshDir("v2")
		_ = try VersionTwoCore.open(at: dir)
		#expect(FileManager.default.fileExists(atPath: dir + "/events-v2.mdb"))
		#expect(!FileManager.default.fileExists(atPath: dir + "/events.mdb"))
	}

	@Test func bumpingTheVersionShipsAFreshFile() throws {
		// the fresh-file semantic that makes the convention trustable: v2 NEVER
		// sees v1's data (different file by construction), and v1 stays readable
		// after v2 starts writing. each phase is SCOPED so the environment
		// handle is released before the next open — reopening the same .mdb
		// while the old handle is still live is undefined LMDB behavior
		// (passes on macOS by platform accident, fails with EINVAL on Linux).
		let dir = VersionPaths.freshDir("fresh")

		// v1: write then read back
		let k1 = TestKey(RAW_native: 1)
		let v1 = TestValue(RAW_native: 100)
		let firstRead: TestValue?
		do {
			let c1 = try VersionOneCore.open(at: dir)
			let tx = try Transaction<Write>(env: c1.env)
			try c1.primary.store(key: k1, value: v1, tx: tx)
			try tx.commit()
			firstRead = try c1.primary.readCommitted(key: k1)
		}
		#expect(firstRead == v1)

		// v2 (fresh file): the old key is ABSENT, and the new version can write
		let k2 = TestKey(RAW_native: 2)
		let v2 = TestValue(RAW_native: 200)
		let freshRead: TestValue?
		let absentOld: TestValue?
		do {
			let c2 = try VersionTwoCore.open(at: dir)
			let tx = try Transaction<Write>(env: c2.env)
			try c2.primary.store(key: k2, value: v2, tx: tx)
			try tx.commit()
			absentOld = try c2.primary.readCommitted(key: k1)
			freshRead = try c2.primary.readCommitted(key: k2)
		}
		#expect(absentOld == nil, "the new version must open a FRESH file — old data is absent by construction")
		#expect(freshRead == v2)

		// v1 remains untouched after v2 wrote to ITS file — REOPENED cleanly
		// now that the first v1 handle is out of scope
		let backV1: TestValue?
		let backV1B: TestValue?
		do {
			let c1 = try VersionOneCore.open(at: dir)
			backV1 = try c1.primary.readCommitted(key: k1)
			backV1B = try c1.primary.readCommitted(key: k2)
		}
		#expect(backV1 == v1, "v1's file must stay readable and untouched after v2 wrote")
		#expect(backV1B == nil)
	}
}
