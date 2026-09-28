import Testing
import Foundation
import QuickLMDB
import RAW

// runtime pins for RUNTIME environment file names — omitting `file:` makes the
// generated factory take a REQUIRED `fileName:` parameter, so ONE type can own
// per-tenant files (`fiat-<base>.mdb`). the supplied name resolves against the
// base path at open time; `version:` derives its suffix from the SUPPLIED name,
// and `encryption:` composes (both parameters required, `fileName:` first).

@MDB_environment(flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct TenantCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
}

@MDB_environment(version: 1, flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct TenantVersionedCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
}

private enum TenantPaths {
	static func freshDir(_ tag: String) -> String {
		FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-tenant-\(tag)-\(UUID().uuidString)", isDirectory: true).path
	}
}

@Suite("runtime environment file names")
struct RuntimeFileNameTests {

	@Test func oneTypeOwnsPerTenantFiles() throws {
		let dir = TenantPaths.freshDir("per-tenant")
		let keyA = TestKey(RAW_native: 11)
		let keyB = TestKey(RAW_native: 22)
		let valueA = TestValue(RAW_native: 111)
		let valueB = TestValue(RAW_native: 222)

		// each phase is SCOPED: reopening the same .mdb while an earlier handle is
		// still live is undefined LMDB behavior.
		let readA: TestValue?
		let absentA: TestValue?
		do {
			let a = try TenantCore.open(at: dir, fileName: "fiat-usd.mdb")
			let txA = try Transaction<Write>(env: a.env)
			try a.primary.store(key: keyA, value: valueA, tx: txA)
			try txA.commit()
			readA = try a.primary.readCommitted(key: keyA)
			absentA = try a.primary.readCommitted(key: keyB)
		}
		let readB: TestValue?
		let absentB: TestValue?
		do {
			let b = try TenantCore.open(at: dir, fileName: "fiat-eur.mdb")
			let txB = try Transaction<Write>(env: b.env)
			try b.primary.store(key: keyB, value: valueB, tx: txB)
			try txB.commit()
			readB = try b.primary.readCommitted(key: keyB)
			absentB = try b.primary.readCommitted(key: keyA)
		}

		#expect(readA == valueA)
		#expect(readB == valueB)
		#expect(absentA == nil, "tenant files are isolated by name — usd must not see eur's key")
		#expect(absentB == nil, "tenant files are isolated by name — eur must not see usd's key")
		#expect(FileManager.default.fileExists(atPath: dir + "/fiat-usd.mdb"))
		#expect(FileManager.default.fileExists(atPath: dir + "/fiat-eur.mdb"))
	}

	@Test func reopeningTheSameNameSeesItsOwnData() throws {
		let dir = TenantPaths.freshDir("reopen")
		let key = TestKey(RAW_native: 7)
		let value = TestValue(RAW_native: 700)
		do {
			let first = try TenantCore.open(at: dir, fileName: "fiat-gbp.mdb")
			let tx = try Transaction<Write>(env: first.env)
			try first.primary.store(key: key, value: value, tx: tx)
			try tx.commit()
		}
		let reopened: TestValue?
		do {
			let second = try TenantCore.open(at: dir, fileName: "fiat-gbp.mdb")
			reopened = try second.primary.readCommitted(key: key)
		}
		#expect(reopened == value, "a runtime name persists across opens like a fixed one")
	}

	@Test func versionAppliesToTheSuppliedName() throws {
		let dir = TenantPaths.freshDir("tenant-version")
		_ = try TenantVersionedCore.open(at: dir, fileName: "events.mdb")
		#expect(FileManager.default.fileExists(atPath: dir + "/events-v1.mdb"))
		#expect(!FileManager.default.fileExists(atPath: dir + "/events.mdb"))
	}
}