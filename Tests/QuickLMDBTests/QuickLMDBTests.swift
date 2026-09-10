import Testing
import Foundation
import QuickLMDB

// engine smoke suite — the simplest possible real-engine verification, kept as
// the orientation suite for the test target. everything here drives a fresh
// real LMDB environment through the public engine surface (no macros).

@Suite("engine smoke")
struct EngineSmokeTests {

	@Test func transactionRoundTripAcrossEnvReopen() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-smoke-\(UUID().uuidString)", isDirectory: true)
		let core = try TestCore.open(at: dir.path)
		let key = TestKey(RAW_native: 1)
		let value = TestValue(RAW_native: 42)

		let write = try Transaction(env: core.env, readOnly: false)
		try core.primary.setEntry(key: key, value: value, flags: [], tx: write)
		try write.commit()

		// survives an environment reopen
		let reopened = try TestCore.open(at: dir.path)
		#expect(try reopened.primary.readCommitted(key: key) == value)
	}

	@Test func transactionDeinitAbortsAnUnclosedWrite() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-smoke-\(UUID().uuidString)", isDirectory: true)
		let core = try TestCore.open(at: dir.path)
		let key = TestKey(RAW_native: 2)

		do {
			let unclosed = try Transaction(env: core.env, readOnly: false)
			try core.primary.setEntry(key: key, value: TestValue(RAW_native: 7), flags: [], tx: unclosed)
			// no commit/abort: the deinit safety net aborts it
		}
		#expect(try core.primary.readCommitted(key: key) == nil)
	}
}
