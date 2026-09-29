import Testing
import Foundation
import QuickLMDB
import RAW

// REGRESSION SUITE: the raw `tx_<E>` transaction surface inside JOINED
// children. before the child-twin rename (the caller's tx arrives as
// `parent_tx_<E>`; the child local holds the canonical `tx_<E>`), a joined
// child's raw references bound to the CALLER's transaction — whose flags
// carry MDB_TXN_HAS_CHILD while the child lives — so every raw
// get/put/delete/cursor op failed with LMDBError.badTransaction ("Transaction
// must abort, has a child, or is invalid"). these pins hold that surface
// correct in the child twin. the MANUAL-* cases are controls: a hand-built
// child transaction running the same calls directly proves the engine and the
// C shim are innocent.

@MDB_environment(file: "cursor-child.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct RawTxChildCore: Sendable {
	public let env: Environment
	public let dup: Database.DupSort<TestKey, TestValue>
	public let strict: Database.Strict<TestKey, TestValue>

	@MDB_transact(.readWrite)
	public func seed(_ key: TestKey, _ values: [TestValue]) throws {
		for value in values {
			try #store(RawTxChildCore.self, database: \.dup, key: key, value: value)
		}
	}

	@MDB_transact(.readWrite)
	public func seedStrict(_ key: TestKey, _ value: TestValue) throws {
		try #store(RawTxChildCore.self, database: \.strict, key: key, value: value)
	}

	// - MARK: candidate callee bodies (each joined below)

	@MDB_transact(.readWrite)
	public func cursorIterate(_ key: TestKey) throws -> Int {
		var count = 0
		try #cursor(RawTxChildCore.self, database: \.dup) { cursor in
			for (_, _) in cursor.makeDupIterator(key: key) { count += 1 }
		}
		return count
	}

	@MDB_transact(.readWrite)
	public func cursorIterateThenStore(_ key: TestKey) throws {
		var count = 0
		try #cursor(RawTxChildCore.self, database: \.dup) { cursor in
			for (_, _) in cursor.makeDupIterator(key: key) { count += 1 }
		}
		try #store(RawTxChildCore.self, database: \.dup, key: TestKey(RAW_native: UInt32(count) + 900), value: TestValue(RAW_native: UInt64(count)))
	}

	@MDB_transact(.readWrite)
	public func storeThenCursorIterate(_ key: TestKey) throws {
		try #store(RawTxChildCore.self, database: \.dup, key: TestKey(RAW_native: 901), value: TestValue(RAW_native: 1))
		try #cursor(RawTxChildCore.self, database: \.dup) { cursor in
			for (_, _) in cursor.makeDupIterator(key: key) { _ = 0 }
		}
	}

	@MDB_transact(.readWrite)
	public func cursorPosAndDeleteCurrent(_ key: TestKey) throws {
		try #cursor(RawTxChildCore.self, database: \.dup) { cursor in
			_ = try cursor.opSet(key: key)
			try cursor.deleteCurrentEntry(flags: [], tx: tx_RawTxChildCore)
		}
	}

	@MDB_transact(.readWrite)
	public func cursorIterateThenDeleteCurrent(_ key: TestKey) throws {
		try #cursor(RawTxChildCore.self, database: \.dup) { cursor in
			_ = try cursor.opSet(key: key)
			for (_, _) in cursor.makeDupIterator(key: key) { _ = 0 }
			try cursor.deleteCurrentEntry(flags: [], tx: tx_RawTxChildCore)
		}
	}

	// - MARK: wiremand-shaped variants (multi-table, pair deletes)

	// mirrors IPDatabase's original uninstallPending: cursor on one table,
	// plain delete on ANOTHER (strict) table, deleteCurrentEntry, all in the child
	@MDB_transact(.readWrite)
	public func cursorCrossTableDelete(_ key: TestKey) throws {
		try #cursor(RawTxChildCore.self, database: \.dup) { cursor in
			let found = try cursor.opSet(key: key)
			try #delete(RawTxChildCore.self, database: \.strict, key: key)
			try cursor.deleteCurrentEntry(flags: [], tx: tx_RawTxChildCore)
			_ = found
		}
	}

	// mirrors _clientRemove's dereference: raw pair-delete on a strict table
	// while a cursor on the dup table is open (one strict entry per key — a
	// non-dupsort pair-delete is a key delete, so delete exactly once)
	@MDB_transact(.readWrite)
	public func cursorThenRawPairDelete(_ key: TestKey) throws {
		try #cursor(RawTxChildCore.self, database: \.dup) { cursor in
			for (_, value) in cursor.makeDupIterator(key: key) {
				try self.strict.deleteEntry(key: key, value: value, tx: tx_RawTxChildCore)
				return
			}
		}
	}

	// dup-sort pair-delete through the typed verb, inside the child
	@MDB_transact(.readWrite)
	public func dupPairDeleteVerb(_ key: TestKey, _ value: TestValue) throws {
		try #delete(RawTxChildCore.self, database: \.dup, key: key, value: value)
	}

	// iterate dups, store a new dup, then pair-delete one — the _clientRemove brew
	@MDB_transact(.readWrite)
	public func iterateStorePairDelete(_ key: TestKey) throws {
		var seen = [TestValue]()
		try #cursor(RawTxChildCore.self, database: \.dup) { cursor in
			for (_, value) in cursor.makeDupIterator(key: key) { seen.append(value) }
		}
		try #store(RawTxChildCore.self, database: \.dup, key: key, value: TestValue(RAW_native: 555))
		if let first = seen.first {
			try #delete(RawTxChildCore.self, database: \.dup, key: key, value: first)
		}
	}

	// - MARK: surgical bisect variants

	// raw pair-delete (not the typed verb) on the DUP table, same cursor shape as JOIN-7
	@MDB_transact(.readWrite)
	public func cursorThenRawPairDeleteDup(_ key: TestKey) throws {
		try #cursor(RawTxChildCore.self, database: \.dup) { cursor in
			for (_, value) in cursor.makeDupIterator(key: key) {
				try self.dup.deleteEntry(key: key, value: value, tx: tx_RawTxChildCore)
			}
		}
	}

	// pair-delete on the STRICT table, but AFTER the cursor closure has closed
	@MDB_transact(.readWrite)
	public func pairDeleteAfterCursorClosed(_ key: TestKey) throws {
		var seen = [TestValue]()
		try #cursor(RawTxChildCore.self, database: \.dup) { cursor in
			for (_, value) in cursor.makeDupIterator(key: key) { seen.append(value) }
		}
		if let first = seen.first {
			try self.strict.deleteEntry(key: key, value: first, tx: tx_RawTxChildCore)
		}
	}

	// pair-delete on the STRICT table in the child with NO cursor anywhere
	@MDB_transact(.readWrite)
	public func pairDeleteNoCursor(_ key: TestKey, _ value: TestValue) throws {
		_ = try #contains(RawTxChildCore.self, database: \.strict, key: key)   // anchors the env set
		try self.strict.deleteEntry(key: key, value: value, tx: tx_RawTxChildCore)
	}

	// the exact historical uninstallPending shape: cursor opSet + cross-table
	// plain delete + deleteCurrentEntry
	@MDB_transact(.readWrite)
	public func cursorOpSetCrossDeleteDeleteCurrent(_ key: TestKey) throws {
		try #cursor(RawTxChildCore.self, database: \.dup) { cursor in
			_ = try cursor.opSet(key: key)
			try #delete(RawTxChildCore.self, database: \.strict, key: key)
			try cursor.deleteCurrentEntry(flags: [], tx: tx_RawTxChildCore)
		}
	}

	// the _clientRemove shape: a raw read as the FIRST operation in the child
	@MDB_transact(.readWrite)
	public func rawReadFirstStatement(_ key: TestKey) throws {
		_ = try self.strict.loadEntry(key: key, tx: tx_RawTxChildCore)
		try #store(RawTxChildCore.self, database: \.dup, key: TestKey(RAW_native: 902), value: TestValue(RAW_native: 1))
	}

	// - MARK: joined parents (#stats anchors the env set)

	@MDB_transact(.readWrite)
	public func joinCursorIterate(_ key: TestKey) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		_ = try #MDB_transacted(cursorIterate(key))
	}

	@MDB_transact(.readWrite)
	public func joinCursorIterateThenStore(_ key: TestKey) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(cursorIterateThenStore(key))
	}

	@MDB_transact(.readWrite)
	public func joinStoreThenCursorIterate(_ key: TestKey) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(storeThenCursorIterate(key))
	}

	@MDB_transact(.readWrite)
	public func joinCursorPosAndDeleteCurrent(_ key: TestKey) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(cursorPosAndDeleteCurrent(key))
	}

	@MDB_transact(.readWrite)
	public func joinCursorIterateThenDeleteCurrent(_ key: TestKey) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(cursorIterateThenDeleteCurrent(key))
	}

	@MDB_transact(.readWrite)
	public func joinCursorCrossTableDelete(_ key: TestKey) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(cursorCrossTableDelete(key))
	}

	@MDB_transact(.readWrite)
	public func joinCursorThenRawPairDelete(_ key: TestKey) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(cursorThenRawPairDelete(key))
	}

	@MDB_transact(.readWrite)
	public func joinDupPairDeleteVerb(_ key: TestKey, _ value: TestValue) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(dupPairDeleteVerb(key, value))
	}

	@MDB_transact(.readWrite)
	public func joinIterateStorePairDelete(_ key: TestKey) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(iterateStorePairDelete(key))
	}

	@MDB_transact(.readWrite)
	public func joinCursorThenRawPairDeleteDup(_ key: TestKey) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(cursorThenRawPairDeleteDup(key))
	}

	@MDB_transact(.readWrite)
	public func joinPairDeleteAfterCursorClosed(_ key: TestKey) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(pairDeleteAfterCursorClosed(key))
	}

	@MDB_transact(.readWrite)
	public func joinPairDeleteNoCursor(_ key: TestKey, _ value: TestValue) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(pairDeleteNoCursor(key, value))
	}

	@MDB_transact(.readWrite)
	public func joinCursorOpSetCrossDeleteDeleteCurrent(_ key: TestKey) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(cursorOpSetCrossDeleteDeleteCurrent(key))
	}

	@MDB_transact(.readWrite)
	public func joinRawReadFirstStatement(_ key: TestKey) throws {
		_ = try #stats(RawTxChildCore.self, database: \.dup)
		try #MDB_transacted(rawReadFirstStatement(key))
	}
}

@Suite("child raw-tx surface")
struct ChildRawTxSurfaceTests {

	private func seededCore(_ values: [TestValue] = [TestValue(RAW_native: 1), TestValue(RAW_native: 2)]) throws -> (RawTxChildCore, TestKey) {
		let core = try RawTxChildCore.open(at: TestHelpers.tempDirPath())
		let key = TestKey(RAW_native: 7)
		try core.seed(key, values)
		for value in values {
			try core.seedStrict(key, value)
		}
		return (core, key)
	}

	@Test("JOIN-1: cursor iterate inside a joined child")
	func joinCursorIterate() throws {
		let (core, key) = try seededCore()
		try core.joinCursorIterate(key)
		print("JOIN-1-OK")
	}

	@Test("JOIN-2: cursor iterate then store inside a joined child")
	func joinCursorIterateThenStore() throws {
		let (core, key) = try seededCore()
		try core.joinCursorIterateThenStore(key)
		print("JOIN-2-OK")
	}

	@Test("JOIN-3: store then cursor iterate inside a joined child")
	func joinStoreThenCursorIterate() throws {
		let (core, key) = try seededCore()
		try core.joinStoreThenCursorIterate(key)
		print("JOIN-3-OK")
	}

	@Test("JOIN-4: cursor position + deleteCurrentEntry inside a joined child")
	func joinCursorPosAndDeleteCurrent() throws {
		let (core, key) = try seededCore()
		try core.joinCursorPosAndDeleteCurrent(key)
		print("JOIN-4-OK")
	}

	@Test("JOIN-5: cursor iterate + deleteCurrentEntry inside a joined child")
	func joinCursorIterateThenDeleteCurrent() throws {
		let (core, key) = try seededCore()
		try core.joinCursorIterateThenDeleteCurrent(key)
		print("JOIN-5-OK")
	}

	@Test("JOIN-6: cursor + cross-table delete inside a joined child")
	func joinCursorCrossTableDelete() throws {
		let (core, key) = try seededCore()
		try core.joinCursorCrossTableDelete(key)
		print("JOIN-6-OK")
	}

	@Test("JOIN-7: cursor + raw pair-delete inside a joined child")
	func joinCursorThenRawPairDelete() throws {
		let (core, key) = try seededCore()
		try core.joinCursorThenRawPairDelete(key)
		print("JOIN-7-OK")
	}

	@Test("JOIN-8: dup-sort pair-delete verb inside a joined child")
	func joinDupPairDeleteVerb() throws {
		let (core, key) = try seededCore()
		try core.joinDupPairDeleteVerb(key, TestValue(RAW_native: 1))
		print("JOIN-8-OK")
	}

	@Test("JOIN-9: iterate + store + pair-delete inside a joined child")
	func joinIterateStorePairDelete() throws {
		let (core, key) = try seededCore()
		try core.joinIterateStorePairDelete(key)
		print("JOIN-9-OK")
	}

	@Test("JOIN-10: cursor + raw pair-delete on the DUP table inside a joined child")
	func joinCursorThenRawPairDeleteDup() throws {
		let (core, key) = try seededCore()
		try core.joinCursorThenRawPairDeleteDup(key)
		print("JOIN-10-OK")
	}

	@Test("JOIN-11: pair-delete after the cursor closed, inside a joined child")
	func joinPairDeleteAfterCursorClosed() throws {
		let (core, key) = try seededCore()
		try core.joinPairDeleteAfterCursorClosed(key)
		print("JOIN-11-OK")
	}

	@Test("JOIN-12: pair-delete with no cursor inside a joined child")
	func joinPairDeleteNoCursor() throws {
		let (core, key) = try seededCore()
		try core.joinPairDeleteNoCursor(key, TestValue(RAW_native: 1))
		print("JOIN-12-OK")
	}

	@Test("JOIN-13: opSet + cross-table delete + deleteCurrentEntry (historical shape)")
	func joinCursorOpSetCrossDeleteDeleteCurrent() throws {
		let (core, key) = try seededCore()
		try core.joinCursorOpSetCrossDeleteDeleteCurrent(key)
		print("JOIN-13-OK")
	}

	@Test("JOIN-14: raw read as the first statement inside a joined child")
	func joinRawReadFirstStatement() throws {
		let (core, key) = try seededCore()
		try core.joinRawReadFirstStatement(key)
		print("JOIN-14-OK")
	}

	@Test("MANUAL-1: pair-delete on a strict table in a HAND-BUILT child transaction")
	func manualChildPairDelete() throws {
		let core = try RawTxChildCore.open(at: TestHelpers.tempDirPath())
		let key = TestKey(RAW_native: 7)
		try core.seedStrict(key, TestValue(RAW_native: 9))

		let root = try Transaction<Write>(env: core.env)
		let child = try Transaction<Write>(env: core.env, parent: root)
		try core.strict.deleteEntry(key: key, value: TestValue(RAW_native: 9), tx: child)
		try child.commit()
		try root.commit()
		print("MANUAL-1-OK")
	}

	@Test("MANUAL-2: pair-delete on the DUP table in a HAND-BUILT child transaction")
	func manualChildPairDeleteDup() throws {
		let core = try RawTxChildCore.open(at: TestHelpers.tempDirPath())
		let key = TestKey(RAW_native: 7)
		try core.seed(key, [TestValue(RAW_native: 9)])

		let root = try Transaction<Write>(env: core.env)
		let child = try Transaction<Write>(env: core.env, parent: root)
		try core.dup.deleteEntry(key: key, value: TestValue(RAW_native: 9), tx: child)
		try child.commit()
		try root.commit()
		print("MANUAL-2-OK")
	}

	@Test("MANUAL-3: key-only delete on a strict table in a HAND-BUILT child transaction")
	func manualChildKeyDelete() throws {
		let core = try RawTxChildCore.open(at: TestHelpers.tempDirPath())
		let key = TestKey(RAW_native: 7)
		try core.seedStrict(key, TestValue(RAW_native: 9))

		let root = try Transaction<Write>(env: core.env)
		let child = try Transaction<Write>(env: core.env, parent: root)
		try core.strict.deleteEntry(key: key, tx: child)
		try child.commit()
		try root.commit()
		print("MANUAL-3-OK")
	}

	@Test("MANUAL-4: pair-delete on a strict table in a ROOT transaction")
	func manualRootPairDelete() throws {
		let core = try RawTxChildCore.open(at: TestHelpers.tempDirPath())
		let key = TestKey(RAW_native: 7)
		try core.seedStrict(key, TestValue(RAW_native: 9))

		let root = try Transaction<Write>(env: core.env)
		try core.strict.deleteEntry(key: key, value: TestValue(RAW_native: 9), tx: root)
		try root.commit()
		print("MANUAL-4-OK")
	}
}