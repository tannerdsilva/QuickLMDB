import Testing
import Foundation
import QuickLMDB

// LMDB 1.0 authenticated per-page encryption + checksums, driven through the
// macro surface: an `@MDB_environment(encryption:checksum:)` environment whose
// generated `open(at:mapHeadroom:encryptionKey:)` requires a key. the real
// engine must write encrypted pages, read them back through the same key, and
// fail loudly (not silently corrupt) when the wrong key is supplied.

@MDB_environment(file: "encrypted.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8, encryption: QuickLMDB.ChaChaPoly.self, checksum: QuickLMDB.Blake2.self)
public struct EncryptedCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
	public let secondary: Database.DupSort<TestKey, TestValue>
}

// checksum-only variant: LMDB supports checksums without encryption; the
// generated open keeps the plain two-parameter signature.
@MDB_environment(file: "checksummed.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8, checksum: QuickLMDB.Blake2.self)
public struct ChecksummedCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
}

@Suite("LMDB 1.0 encryption through the macro surface")
struct EncryptionRuntimeTests {

	@Test func encryptedRoundTripThroughGeneratedOpen() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-enc-\(UUID().uuidString)", isDirectory: true)
		let key = [UInt8](repeating: 0x42, count: 32)
		let core = try EncryptedCore.open(at: dir.path, encryptionKey: key)

		// the environment is genuinely flagged encrypted (engine forces remap chunks)
		#expect(core.env.flags.contains(.encrypt))
		#expect(core.env.flags.contains(.remapChunks))

		// a write transaction lands real records through the encrypt callback
		let value = TestValue(RAW_native: 12345)
		let write = try Transaction<Write>(env: core.env)
		try core.primary.setEntry(key: TestKey(RAW_native: 7), value: value, flags: [], tx: write)
		try write.commit()

		// read back within the same process
		let read = try Transaction<Read>(env: core.env)
		let loaded = core.primary.load(key: TestKey(RAW_native: 7), tx: read)
		read.abort()
		#expect(loaded == value)
	}

	@Test func encryptedDataPersistsAndReopensWithSameKey() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-enc2-\(UUID().uuidString)", isDirectory: true)
		let key = [UInt8](repeating: 0x13, count: 32)
		do {
			let core = try EncryptedCore.open(at: dir.path, encryptionKey: key)
			let write = try Transaction<Write>(env: core.env)
			try core.primary.setEntry(key: TestKey(RAW_native: 1), value: TestValue(RAW_native: 99), flags: [], tx: write)
			try write.commit()
			// core deallocates -> environment closed when scope exits
		}
		// reopen the SAME directory with the SAME key: the on-disk pages are
		// encrypted, so this exercises decrypt-on-read of a real stored file.
		let reopened = try EncryptedCore.open(at: dir.path, encryptionKey: key)
		let read = try Transaction<Read>(env: reopened.env)
		let loaded = reopened.primary.load(key: TestKey(RAW_native: 1), tx: read)
		read.abort()
		#expect(loaded == TestValue(RAW_native: 99))
	}

	@Test func wrongKeyFailsLoudly() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-enc3-\(UUID().uuidString)", isDirectory: true)
		let goodKey = [UInt8](repeating: 0x01, count: 32)
		do {
			let core = try EncryptedCore.open(at: dir.path, encryptionKey: goodKey)
			let write = try Transaction<Write>(env: core.env)
			try core.primary.setEntry(key: TestKey(RAW_native: 2), value: TestValue(RAW_native: 5), flags: [], tx: write)
			try write.commit()
		}

		// open with a DIFFERENT key: the read path must reject, never return
		// undecrypted garbage
		let wrongKey = [UInt8](repeating: 0x99, count: 32)
		do {
			let core = try EncryptedCore.open(at: dir.path, encryptionKey: wrongKey)
			var threw = false
			do {
				let read = try Transaction<Read>(env: core.env)
				let loaded = core.primary.load(key: TestKey(RAW_native: 2), tx: read)
				read.abort()
				_ = loaded
			} catch {
				threw = true
			}
			#expect(threw, "wrong key unexpectedly read undecrypted data")
		} catch {
			// open itself detected the key mismatch — also a valid loud failure
			#expect(true)
		}
	}

	@Test func checksumOnlyEnvironmentStillOpensAndRoundTrips() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-cksum-\(UUID().uuidString)", isDirectory: true)
		let core = try ChecksummedCore.open(at: dir.path)

		let write = try Transaction<Write>(env: core.env)
		try core.primary.setEntry(key: TestKey(RAW_native: 3), value: TestValue(RAW_native: 77), flags: [], tx: write)
		try write.commit()

		let read = try Transaction<Read>(env: core.env)
		let loaded = core.primary.load(key: TestKey(RAW_native: 3), tx: read)
		read.abort()
		#expect(loaded == TestValue(RAW_native: 77))
	}
}
