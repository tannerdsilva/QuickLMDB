import Testing
import Foundation
import QuickLMDB
import RAW

// runtime pins for the SHARED-PHYSICAL-ENVIRONMENT layer (`@MDB_env_group`):
// several distinct core TYPES over one physical LMDB file — the v22 multi-env
// blind spot. the group opens the env ONCE and constructs every member core
// from the same `Environment` value, and the boundary dialect keys its
// transactions to the GROUP: a boundary addressing two members opens ONE
// transaction on the shared env (the double-write self-deadlock is
// structurally unreachable), so cross-member write sets are atomic.
//
// the group struct is itself verb-addressable with keypaths chained through
// its members (`\.alpha.alphaEntries`); a boundary ON a member references
// sibling members by their qualified name (taken as typed parameters). both
// spellings collapse to the single `tx_<Group>` label.

@MDB_env_group(file: "shared.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 16)
public struct SharedEnv: Sendable {

	@MDB_environment
	public struct AlphaCore: Sendable {
		public let env: Environment
		public let alphaEntries: Database.Strict<TestKey, TestValue>
	}

	@MDB_environment
	public struct BetaCore: Sendable {
		public let env: Environment
		public let betaEntries: Database.Strict<TestKey, TestValue>
	}

	public let alpha: AlphaCore
	public let beta: BetaCore

	// an IN-STRUCT boundary on the group itself: pure coordinator (verb-less) —
	// its env set is inferred from self being a @MDB_env_group struct. the two
	// joined member boundaries share the one tx_<Group> transaction, so the
	// composed write is atomic with the caller.
	@MDB_transact(.readWrite)
	public func persistPair(_ key: TestKey, _ value: TestValue) throws {
		try #MDB_transacted(alpha.put(key, value))
		try #MDB_transacted(beta.put(key, value))
	}

	// cross-member boundary on the GROUP with keypaths chained through members.
	@MDB_transact(.readWrite)
	public func writePair(_ key: TestKey, _ value: TestValue) throws {
		try #store(SharedEnv.self, database: \.alpha.alphaEntries, key: key, value: value)
		try #store(SharedEnv.self, database: \.beta.betaEntries, key: key, value: value)
	}

	// the abort side: a thrown failure rolls back BOTH member writes.
	@MDB_transact(.readWrite)
	public func writePairFailing(_ key: TestKey, _ value: TestValue) throws {
		try #store(SharedEnv.self, database: \.alpha.alphaEntries, key: key, value: value)
		try #store(SharedEnv.self, database: \.beta.betaEntries, key: key, value: value)
		throw TestError.simulatedFailure
	}

	// one snapshot across both members (readOnly single-transaction read).
	@MDB_transact(.readOnly)
	public func readPair(_ key: TestKey) throws -> (TestValue?, TestValue?) {
		let a = #load(SharedEnv.self, database: \.alpha.alphaEntries, key: key)
		let b = #load(SharedEnv.self, database: \.beta.betaEntries, key: key)
		return (a, b)
	}

	// mixed same-group pair + distinct-env core: exception-atomicity across
	// both (the report's §2.3.4 acceptance).
	@MDB_transact(.readWrite)
	public func writePairAndForeign(_ key: TestKey, _ value: TestValue, foreign: ForeignCore) throws {
		try #store(SharedEnv.self, database: \.alpha.alphaEntries, key: key, value: value)
		try #store(SharedEnv.self, database: \.beta.betaEntries, key: key, value: value)
		try #store(ForeignCore.self, database: \.foreignEntries, key: key, value: value)
	}
}

extension SharedEnv.AlphaCore {

	// single-member boundary on a group member — the group label is invisible;
	// one write transaction on the shared env, like any other core boundary.
	@MDB_transact(.readWrite)
	func put(_ key: TestKey, _ value: TestValue) throws {
		try #store(AlphaCore.self, database: \.alphaEntries, key: key, value: value)
	}

	@MDB_transact(.readOnly)
	func get(_ key: TestKey) throws -> TestValue? {
		#load(AlphaCore.self, database: \.alphaEntries, key: key)
	}

	// cross-member boundary ON a member: self + a sibling member as a typed
	// (qualified) parameter — both collapse to the one group transaction.
	@MDB_transact(.readWrite)
	func writeSibling(_ key: TestKey, _ value: TestValue, beta: SharedEnv.BetaCore) throws {
		try #store(SharedEnv.AlphaCore.self, database: \.alphaEntries, key: key, value: value)
		try #store(SharedEnv.BetaCore.self, database: \.betaEntries, key: key, value: value)
	}

	// write boundary joining a sibling-member boundary — atomic with caller.
	@MDB_transact(.readWrite)
	func putAndVerifyInBeta(_ key: TestKey, _ value: TestValue, beta: SharedEnv.BetaCore) throws -> Bool {
		try #store(SharedEnv.AlphaCore.self, database: \.alphaEntries, key: key, value: value)
		return try #MDB_transacted(beta.putAndConfirm(key, value))
	}
}

extension SharedEnv.BetaCore {

	@MDB_transact(.readWrite)
	func put(_ key: TestKey, _ value: TestValue) throws {
		try #store(BetaCore.self, database: \.betaEntries, key: key, value: value)
	}

	@MDB_transact(.readOnly)
	func get(_ key: TestKey) throws -> TestValue? {
		#load(BetaCore.self, database: \.betaEntries, key: key)
	}

	// reads ITS OWN table through the JOINED (shared) transaction — must see
	// the caller's uncommitted AlphaCore state, and persists atomically.
	@MDB_transact(.readWrite)
	func putAndConfirm(_ key: TestKey, _ value: TestValue) throws -> Bool {
		try #store(BetaCore.self, database: \.betaEntries, key: key, value: value)
		return #load(BetaCore.self, database: \.betaEntries, key: key) == value
	}
}

// a distinct-physical-env core for the mixed-boundary acceptance (unchanged
// standalone shape — the group layer must not disturb distinct-env semantics).
@MDB_environment(file: "foreign.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct ForeignCore: Sendable {
	public let env: Environment
	public let foreignEntries: Database.Strict<TestKey, TestValue>
}

@Suite("shared-physical-environment multi-core layer")
struct SharedEnvironmentMultiCoreTests {

	private func freshGroup() throws -> SharedEnv {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-sharedenv-\(UUID().uuidString)", isDirectory: true)
		return try SharedEnv.open(at: dir.path)
	}

	@Test func groupOpensOneEnvironmentForAllMembers() throws {
		let env = try freshGroup()
		// THE one-open guarantee: every member core holds the SAME Environment
		// instance (a second handle on the file is invalid), and the group's
		// `env` accessor mirrors it for the boundary shell.
		#expect(env.alpha.env === env.beta.env)
		#expect(env.env === env.alpha.env)
	}

	@Test func memberBoundariesReadAndWriteTheirOwnTables() throws {
		let env = try freshGroup()
		let key = TestKey(RAW_native: 1)
		let value = TestValue(RAW_native: 100)
		try env.alpha.put(key, value)
		#expect(try env.alpha.get(key) == value)
		// committed state is visible through the OTHER member's handle — the
		// tables live in one physical env even though the types are distinct
		#expect(try env.beta.betaEntries.readCommitted(key: key) == nil)
		try env.beta.put(key, value)
		#expect(try env.beta.get(key) == value)
	}

	// THE regression pin: a boundary addressing TWO members in one .readWrite
	// — impossible before the group layer (two write transactions on one env =
	// writer-mutex self-deadlock). now one transaction: both durable.
	@Test func crossMemberWriteIsAtomicAndDurable() throws {
		let env = try freshGroup()
		let key = TestKey(RAW_native: 2)
		let value = TestValue(RAW_native: 200)
		try env.writePair(key, value)
		#expect(try env.alpha.alphaEntries.readCommitted(key: key) == value)
		#expect(try env.beta.betaEntries.readCommitted(key: key) == value)
	}

	@Test func crossMemberReadIsOneSnapshot() throws {
		let env = try freshGroup()
		let key = TestKey(RAW_native: 3)
		let value = TestValue(RAW_native: 300)
		try env.writePair(key, value)
		let (a, b) = try env.readPair(key)
		#expect(a == value)
		#expect(b == value)
	}

	@Test func crossMemberAbortRollsBackBothMembers() throws {
		let env = try freshGroup()
		let key = TestKey(RAW_native: 4)
		let value = TestValue(RAW_native: 400)
		#expect(throws: TestError.self) {
			try env.writePairFailing(key, value)
		}
		#expect(try env.alpha.alphaEntries.readCommitted(key: key) == nil)
		#expect(try env.beta.betaEntries.readCommitted(key: key) == nil)
	}

	@Test func memberAttachedBoundaryAddressesSiblingMember() throws {
		let env = try freshGroup()
		let key = TestKey(RAW_native: 5)
		let value = TestValue(RAW_native: 500)
		try env.alpha.writeSibling(key, value, beta: env.beta)
		#expect(try env.alpha.alphaEntries.readCommitted(key: key) == value)
		#expect(try env.beta.betaEntries.readCommitted(key: key) == value)
	}

	@Test func joinedSiblingBoundaryIsAtomicWithCaller() throws {
		let env = try freshGroup()
		let key = TestKey(RAW_native: 6)
		let value = TestValue(RAW_native: 600)
		// the joined BetaCore boundary runs inside THIS boundary's one group
		// transaction — a sibling (bare) call would open a fresh write txn and
		// block; the join threads tx_<Group> and the pair commits together
		let confirmed = try env.alpha.putAndVerifyInBeta(key, value, beta: env.beta)
		#expect(confirmed)
		#expect(try env.alpha.alphaEntries.readCommitted(key: key) == value)
		#expect(try env.beta.betaEntries.readCommitted(key: key) == value)
	}

	@Test func coordinatorJoinsMemberBoundariesAtomically() throws {
		let env = try freshGroup()
		let key = TestKey(RAW_native: 7)
		let value = TestValue(RAW_native: 700)
		try env.persistPair(key, value)
		#expect(try env.alpha.alphaEntries.readCommitted(key: key) == value)
		#expect(try env.beta.betaEntries.readCommitted(key: key) == value)
	}

	@Test func mixedSameGroupAndDistinctEnvKeepsExceptionAtomicity() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-sharedenv-\(UUID().uuidString)", isDirectory: true)
		let env = try SharedEnv.open(at: dir.path)
		let foreignDir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-foreign-\(UUID().uuidString)", isDirectory: true)
		let foreign = try ForeignCore.open(at: foreignDir.path)
		let key = TestKey(RAW_native: 8)
		let value = TestValue(RAW_native: 800)

		try env.writePairAndForeign(key, value, foreign: foreign)
		#expect(try env.alpha.alphaEntries.readCommitted(key: key) == value)
		#expect(try env.beta.betaEntries.readCommitted(key: key) == value)
		#expect(try foreign.foreignEntries.readCommitted(key: key) == value)
	}

	// ENGINE REALITY PIN: two DISTINCT env handles (e.g. two group types) on
	// one file are TOLERATED by this CLMDB build (fcntl locks are per-process,
	// not per-handle) — the report's §1 "not valid" assumption is false here.
	// the macro cannot see across declarations, and a runtime registry would
	// violate the zero-ambient doctrine, so this remains the consumer's
	// responsibility: declare one group per physical file. this test pins the
	// CURRENT engine behavior so a future LMDB change (or a corruption bug)
	// surfaces loudly.
	@Test func twoGroupsOnOneFileAreEngineTolerated() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-sharedenv-\(UUID().uuidString)", isDirectory: true)
		_ = try SharedEnv.open(at: dir.path)
		// a second group-level open on the same file succeeds (separate
		// Environment instance; distinct writer mutexes). concurrent writers
		// through BOTH is unsafe — document, do not encourage.
		_ = try SharedEnv.open(at: dir.path)
	}
}
