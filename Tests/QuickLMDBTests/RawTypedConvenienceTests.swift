import Testing
import Foundation
import QuickLMDB
import RAW

// type-safe operations for the RAW (heterogeneous) `Database` surface: the
// typed `setEntry(key:value:flags:tx:)` / `loadEntry(key:as:tx:)` conveniences
// must round-trip typed values WITHOUT ever exposing an `MDB_val` view to the
// caller — and must store the actual value bytes (the fixed regression for the
// scoped-temporary corruption where writes persisted dangling pointer memory).

@MDB_environment(file: "rawmeta.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct RawMetaCore: Sendable {
	public let env: Environment
	public let metadata: Database
}

@Suite("raw Database — typed conveniences (safe heterogeneous surface)")
struct RawTypedConvenienceTests {

	private func freshCore() throws -> RawMetaCore {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-rawmeta-\(UUID().uuidString)", isDirectory: true)
		return try RawMetaCore.open(at: dir.path)
	}

	@Test func typedRoundTripStoresAndDecodes() throws {
		let core = try freshCore()
		let key = TestKey(RAW_native: 7)
		let value = TestValue(RAW_native: 99)

		let write = try Transaction<Write>(env: core.env)
		try core.metadata.setEntry(key: key, value: value, flags: [], tx: write)
		try write.commit()

		let read = try Transaction<Read>(env: core.env)
		let loaded = try core.metadata.loadEntry(key: key, as: TestValue.self, tx: read)
		read.abort()
		#expect(loaded == value)
	}

	@Test func storedBytesAreTheTrueValueBytes() throws {
		let core = try freshCore()
		let key = TestKey(RAW_native: 11)
		let value = TestValue(RAW_native: 0x0102030405060708)

		let write = try Transaction<Write>(env: core.env)
		try core.metadata.setEntry(key: key, value: value, flags: [], tx: write)
		try write.commit()

		// independent oracle: the fixed-width BE encoding of the value, NOT a
		// re-encode through the library (that would mask byte corruption)
		let oracle: [UInt8] = withUnsafeBytes(of: value.RAW_native().bigEndian) { Array($0) }

		let read = try Transaction<Read>(env: core.env)
		let keyBytes = key.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self, { Array($0) })
		let stored: [UInt8] = try keyBytes.withUnsafeBytes { keyBuf in
			let keyVal = MDB_val(mv_size: keyBuf.count, mv_data: UnsafeMutableRawPointer(mutating: keyBuf.baseAddress!))
			let raw = try core.metadata.loadEntry(key: keyVal, as: MDB_val.self, tx: read)
			return [UInt8](raw)
		}
		read.abort()
		#expect(stored == oracle)
	}

	@Test func missingKeyThrowsNotFound() throws {
		let core = try freshCore()
		let read = try Transaction<Read>(env: core.env)
		#expect(throws: LMDBError.self) {
			_ = try core.metadata.loadEntry(key: TestKey(RAW_native: 404), as: TestValue.self, tx: read)
		}
		read.abort()
	}
}
