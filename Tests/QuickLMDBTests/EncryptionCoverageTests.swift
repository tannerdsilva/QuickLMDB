import Testing
import Foundation
import QuickLMDB
import RAW

// meaningful coverage beyond the four baseline encryption tests. each test here
// exercises a DISTINCT code path that the baseline doesn't touch — not
// redundant assertions:
//
//   1. encrypt-only (no `checksum:`) — the engine path where `me_sumsize == 0`
//      and the macro codegen branch that omits the checksum label.
//   2. overflow-sized values (multi-page) — the engine's overflow-page encrypt/
//      decrypt path (`numpgs > 1`), never exercised point-loads.
//   3. cursor traversal over encrypted pages — range walks hit the cursor
//      decrypt path (`mdb_rpage_decrypt`), distinct from point loads.
//   4. tamper detection — the AEAD/checksum integrity guarantee: corrupt live
//      pages on disk, reopen with the RIGHT key, and the original plaintext
//      must never be served silently.
//   5. `readCommitted` self-scoped reads over an encrypted env.
//   6. the macro transaction layer over encryption — `@MDB_transact`
//      boundaries, typed verbs, a `#MDB_transacted` join, and DupSort
//      iteration, all on an encrypted environment.

// encrypt-only scaffold (the checksum is deliberately omitted)
@MDB_environment(file: "vault.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8, encryption: QuickLMDB.ChaChaPoly.self)
public struct VaultCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
	public let blobs: Database.Strict<TestKey, [UInt8]>
}

// macro-layer scaffold: boundaries + a DupSort table over an encrypted env
@MDB_environment(file: "boundary.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8, encryption: QuickLMDB.ChaChaPoly.self, checksum: QuickLMDB.Blake2.self)
public struct EncryptedBoundaryCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
	public let dups: Database.DupSort<TestKey, TestValue>

	@MDB_transact(.readWrite)
	public func writeAndJoinDup(_ key: TestKey, _ value: TestValue, _ dup: TestValue) throws {
		try #store(EncryptedBoundaryCore.self, database: \.primary, key: key, value: value)
		try #MDB_transacted(putDup(key, dup))
	}

	@MDB_transact(.readWrite)
	public func putDup(_ key: TestKey, _ value: TestValue) throws {
		try #store(EncryptedBoundaryCore.self, database: \.dups, key: key, value: value)
	}

	@MDB_transact(.readWrite)
	public func putDups(_ key: TestKey, _ values: [TestValue]) throws {
		for v in values {
			try #store(EncryptedBoundaryCore.self, database: \.dups, key: key, value: v)
		}
	}

	@MDB_transact(.readOnly)
	public func fetch(_ key: TestKey) throws -> TestValue? {
		#load(EncryptedBoundaryCore.self, database: \.primary, key: key)
	}

	@MDB_transact(.readOnly)
	public func walkDups(_ key: TestKey) throws -> [TestValue] {
		try #cursor(EncryptedBoundaryCore.self, database: \.dups) { cursor in
			_ = try cursor.opSetKey(returning: (key: TestKey, value: TestValue).self, key: key)
			var out: [TestValue] = []
			do {
				var v = try cursor.opFirstDup(returning: TestValue.self)
				out.append(v)
				while true {
					v = try cursor.opNextDup(returning: TestValue.self)
					out.append(v)
				}
			} catch let error as LMDBError {
				if !isMDBErr(error, .notFound) { throw error }
			}
			return out
		}
	}

	@MDB_transact(.readOnly)
	public func dupCount(_ key: TestKey) throws -> Int {
		try #cursor(EncryptedBoundaryCore.self, database: \.dups) { cursor in
			_ = try cursor.opSetKey(returning: (key: TestKey, value: TestValue).self, key: key)
			return try cursor.dupCount()
		}
	}
}

@Suite("encrypted environment — meaningful coverage")
struct EncryptionCoverageTests {

	// 1. encryption without a checksum: the engine path with no per-page
	// checksums (me_sumsize == 0) and the macro's encrypt-only codegen branch
	@Test func encryptOnlyRoundTrip() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-cov-enconly-\(UUID().uuidString)", isDirectory: true)
		let key = [UInt8](repeating: 0x11, count: 32)
		let core = try VaultCore.open(at: dir.path, encryptionKey: key)
		#expect(core.env.flags.contains(.encrypt))
		#expect(core.env.flags.contains(.remapChunks))

		let write = try Transaction<Write>(env: core.env)
		try core.primary.setEntry(key: TestKey(RAW_native: 1), value: TestValue(RAW_native: 0xABCD), flags: [], tx: write)
		try write.commit()

		let read = try Transaction<Read>(env: core.env)
		let loaded = core.primary.load(key: TestKey(RAW_native: 1), tx: read)
		read.abort()
		#expect(loaded == TestValue(RAW_native: 0xABCD))
	}

	// 2. a value spanning many pages round-trips through the encrypt callback
	@Test func overflowValueOverEncryption() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-cov-overflow-\(UUID().uuidString)", isDirectory: true)
		let key = [UInt8](repeating: 0x22, count: 32)
		let core = try VaultCore.open(at: dir.path, encryptionKey: key)
		let big = [UInt8](repeating: 0xAB, count: 256 * 1024)   // spans dozens of pages
		let write = try Transaction<Write>(env: core.env)
		try core.blobs.setEntry(key: TestKey(RAW_native: 2), value: big, flags: [], tx: write)
		try write.commit()

		let read = try Transaction<Read>(env: core.env)
		let loaded = core.blobs.load(key: TestKey(RAW_native: 2), tx: read)
		read.abort()
		#expect(loaded == big)
	}

	// 3. a cursor range walk decrypts every page it traverses
	@Test func cursorWalkOverEncryptedPages() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-cov-cursor-\(UUID().uuidString)", isDirectory: true)
		let key = [UInt8](repeating: 0x33, count: 32)
		let core = try VaultCore.open(at: dir.path, encryptionKey: key)
		let write = try Transaction<Write>(env: core.env)
		for i in 0..<100 {
			try core.primary.setEntry(key: TestKey(RAW_native: UInt32(i)), value: TestValue(RAW_native: UInt64(i * 3)), flags: [], tx: write)
		}
		try write.commit()

		let read = try Transaction<Read>(env: core.env)
		var count = 0
		var bad = 0
		try core.primary.cursor(tx: read) { cursor in
			do {
				var entry = try cursor.opFirst(returning: (key: TestKey, value: TestValue).self)
				while true {
					if entry.value.RAW_native() != UInt64(count * 3) { bad += 1 }
					count += 1
					entry = try cursor.opNext(returning: (key: TestKey, value: TestValue).self)
				}
			} catch let error as LMDBError {
				if !isMDBErr(error, .notFound) { throw error }
			}
		}
		read.abort()
		#expect(count == 100)
		#expect(bad == 0)
	}

	// 4. the point of the AEAD + checksums: tampering live pages is DETECTED.
	// corrupt a full page inside the value's storage, reopen with the RIGHT
	// key, and the original value must never be served back silently.
	@Test func tamperedLivePagesNeverServeOriginal() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-cov-tamper-\(UUID().uuidString)", isDirectory: true)
		let key = [UInt8](repeating: 0x44, count: 32)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		let fileURL = dir.appendingPathComponent("vault.mdb")
		let value = [UInt8](repeating: 0x5A, count: 512 * 1024)
		do {
			let core = try VaultCore.open(at: dir.path, encryptionKey: key)
			let write = try Transaction<Write>(env: core.env)
			try core.blobs.setEntry(key: TestKey(RAW_native: 3), value: value, flags: [], tx: write)
			try write.commit()
		}

		let pristine = try Data(contentsOf: fileURL)
		let pageSize = 4096
		// sweep full-page flips across the file's page range, skipping the head
		// (meta + tree) and the tail (sparse padding). every flip here lands in
		// a page the value read MUST traverse.
		var silentRenders: [Int] = []
		var detected = 0
		for page in stride(from: 40, to: (pristine.count / pageSize) - 8, by: 16) {
			let base = page * pageSize
			var flipped = pristine
			for i in 0..<pageSize { flipped[base + i] ^= 0xFF }
			try flipped.write(to: fileURL)

			do {
				let core = try VaultCore.open(at: dir.path, encryptionKey: key)
				let read = try Transaction<Read>(env: core.env)
				let loaded = core.blobs.load(key: TestKey(RAW_native: 3), tx: read)
				read.abort()
				if loaded == value {
					silentRenders.append(page)
				} else {
					detected += 1   // nil, wrong bytes, or a thrown error — all loud
				}
			} catch {
				detected += 1       // cryptoFail / badChecksum — loud by definition
			}
		}
		try pristine.write(to: fileURL)
		#expect(detected > 0, "tamper sweep should detect corruption somewhere")
		#expect(silentRenders.isEmpty, "tampered pages silently served the original value at pages \(silentRenders)")
	}

	// 5. self-scoped committed reads over an encrypted env
	@Test func readCommittedOverEncryptedEnv() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-cov-committed-\(UUID().uuidString)", isDirectory: true)
		let key = [UInt8](repeating: 0x55, count: 32)
		let core = try VaultCore.open(at: dir.path, encryptionKey: key)
		let write = try Transaction<Write>(env: core.env)
		try core.primary.setEntry(key: TestKey(RAW_native: 9), value: TestValue(RAW_native: 40), flags: [], tx: write)
		try write.commit()

		let loaded = try core.primary.readCommitted(key: TestKey(RAW_native: 9))
		#expect(loaded == TestValue(RAW_native: 40))
	}

	// 6. the macro transaction layer over an encrypted env: boundaries, typed
	// verbs, a joined child write, and DupSort iteration
	@Test func macroLayerOverEncryptedEnv() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-cov-macro-\(UUID().uuidString)", isDirectory: true)
		let key = [UInt8](repeating: 0x77, count: 32)
		let core = try EncryptedBoundaryCore.open(at: dir.path, encryptionKey: key)

		// boundary write + joined child write (folded on commit)
		try core.writeAndJoinDup(TestKey(RAW_native: 5), TestValue(RAW_native: 50), TestValue(RAW_native: 51))
		let fetched = try core.fetch(TestKey(RAW_native: 5))
		#expect(fetched == TestValue(RAW_native: 50))

		// DupSort iteration over encrypted pages
		try core.putDups(TestKey(RAW_native: 6), [TestValue(RAW_native: 1), TestValue(RAW_native: 2), TestValue(RAW_native: 3)])
		let walked = try core.walkDups(TestKey(RAW_native: 6))
		#expect(walked == [TestValue(RAW_native: 1), TestValue(RAW_native: 2), TestValue(RAW_native: 3)])

		// the joined dup folded durably
		let dups = try core.dupCount(TestKey(RAW_native: 5))
		#expect(dups == 1)
	}
}
