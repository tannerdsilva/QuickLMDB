import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import QuickLMDBMacros

// expansion fixtures for @MDB_env_group — the SHARED-PHYSICAL-ENVIRONMENT layer.
// one physical LMDB file = one type. the group's stored properties are its
// member cores (nested @MDB_environment structs); the group opens the env ONCE
// and constructs every member from the same Environment value + one setup
// write-transaction. the nested @MDB_environment attribute stays in source
// (its own expansion is pinned by the runtime suite + member diagnostics below).

private let groupMacros: [String: Macro.Type] = [
	"MDB_env_group": MDB_env_group_macro.self,
]

private func assertGroupExpansion(_ source: String, expanded expected: String) {
	assertMacroExpansion(
		source,
		expandedSource: expected,
		macroSpecs: groupMacros.mapValues { MacroSpec(type: $0) },
		failureHandler: { spec in Issue.record(Comment(stringLiteral: spec.message)) }
	)
}

/// negative-path helper: thrown member-macro errors are not captured by
/// assertMacroExpansion's context — the seeded file.expand path records them.
private func assertGroupError(_ source: String, _ expectedDiags: [String]) {
	let file = Parser.parse(source: source)
	var contexts: [BasicMacroExpansionContext] = []
	_ = file.expand(macros: groupMacros, contextGenerator: { node in
		let ctx = BasicMacroExpansionContext()
		contexts.append(ctx)
		return ctx
	})
	let actual = contexts.flatMap { $0.diagnostics.map(\.message) }
	#expect(actual == expectedDiags, Comment(stringLiteral: "diagnostics mismatch: \(actual)"))
}

@Suite("MDB_env_group — the shared-physical-env layer (generated surface)")
struct MDBEnvGroupExpansionTests {

	@Test func groupGeneratesAccessorInventoryAndOpen() {
		// byte-frozen oracle (actual expansion spliced from the dump harness)
		assertGroupExpansion(
			"""
			@MDB_env_group(file: "shared.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 16)
			public struct SharedEnv {
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
			}
			""",
			expanded: """
			
			public struct SharedEnv {
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

			    /// the shared environment handle of this group's physical environment — every member core opens from the same value.
			    public var env: Environment {
			        alpha.env
			    }

			    public static let mdb_core_names: [String] = ["alpha", "beta"]

			    /// opens the physical environment once and constructs every member core from it —
			    /// all member tables are created in a single setup write-transaction.
			    /// - parameter basePath: the directory that will contain the environment file (created if
			    ///   it does not already exist).
			    /// - parameter mapHeadroom: added to the current file size when sizing the memory map.
			    @available(*, noasync)
			    public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)
			        let slash = basePath.hasSuffix("/") ? "" : "/"
			        let targetPath = basePath + slash + "shared.mdb"
			        let fileSize = QuickLMDB._MDBEnvironmentSupport.__fileSize(at: targetPath)
			        let env = try Environment(path: targetPath, flags: QuickLMDB.Environment.Flags([.noTLS]).union([.noSubDir]), mapSize: Int(fileSize + mapHeadroom), maxReaders: 16, maxDBs: 16, mode: [.ownerReadWriteExecute, .groupRead, .otherRead])
			        let setupTX = try Transaction<Write>(env: env)
			        let alphaEntries = try Database.Strict<TestKey, TestValue>(env: env, name: "alphaEntries", flags: [.create], tx: setupTX)
			        let alpha = AlphaCore(env: env, alphaEntries: alphaEntries)
			        let betaEntries = try Database.Strict<TestKey, TestValue>(env: env, name: "betaEntries", flags: [.create], tx: setupTX)
			        let beta = BetaCore(env: env, betaEntries: betaEntries)
			        try setupTX.commit()
			        return Self(alpha: alpha, beta: beta)
			    }
			}

			extension SharedEnv: MDB_environment {
			}
			"""
		)
	}

	@Test func groupConsumesTableAttributes() {
		// byte-frozen oracle: @MDB_table name override + flags splice through
		// the group's per-member table opens, exactly like the standalone core.
		assertGroupExpansion(
			"""
			@MDB_env_group(file: "daemon.mdb", flags: [.noSubDir], maxReaders: 32, maxDBs: 32)
			public struct DaemonEnv {
			    @MDB_environment
			    public struct WireguardDatabase: Sendable {
			        public let env: Environment
			        @MDB_table(name: "client_pub", flags: [.reverseKey])
			        public let clientPub: Database.Strict<TestKey, TestValue>
			    }
			    public let wireguard: WireguardDatabase
			}
			""",
			expanded: """
			
			public struct DaemonEnv {
			    @MDB_environment
			    public struct WireguardDatabase: Sendable {
			        public let env: Environment
			        @MDB_table(name: "client_pub", flags: [.reverseKey])
			        public let clientPub: Database.Strict<TestKey, TestValue>
			    }
			    public let wireguard: WireguardDatabase

			    /// the shared environment handle of this group's physical environment — every member core opens from the same value.
			    public var env: Environment {
			        wireguard.env
			    }

			    public static let mdb_core_names: [String] = ["wireguard"]

			    /// opens the physical environment once and constructs every member core from it —
			    /// all member tables are created in a single setup write-transaction.
			    /// - parameter basePath: the directory that will contain the environment file (created if
			    ///   it does not already exist).
			    /// - parameter mapHeadroom: added to the current file size when sizing the memory map.
			    @available(*, noasync)
			    public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)
			        let slash = basePath.hasSuffix("/") ? "" : "/"
			        let targetPath = basePath + slash + "daemon.mdb"
			        let fileSize = QuickLMDB._MDBEnvironmentSupport.__fileSize(at: targetPath)
			        let env = try Environment(path: targetPath, flags: QuickLMDB.Environment.Flags([.noTLS]).union([.noSubDir]), mapSize: Int(fileSize + mapHeadroom), maxReaders: 32, maxDBs: 32, mode: [.ownerReadWriteExecute, .groupRead, .otherRead])
			        let setupTX = try Transaction<Write>(env: env)
			        let clientPub = try Database.Strict<TestKey, TestValue>(env: env, name: "client_pub", flags: QuickLMDB.MDB_db_flags([.create]).union([.reverseKey]), tx: setupTX)
			        let wireguard = WireguardDatabase(env: env, clientPub: clientPub)
			        try setupTX.commit()
			        return Self(wireguard: wireguard)
			    }
			}

			extension DaemonEnv: MDB_environment {
			}
			"""
		)
	}

	@Test func groupVersionSuffixesTheFileName() {
		// byte-frozen oracle: the version rides in the on-disk file name
		// (`<stem>-v<N>.mdb`), identical to the standalone versioned core.
		assertGroupExpansion(
			"""
			@MDB_env_group(file: "store.mdb", version: 2, flags: [.noSubDir])
			public struct StoreEnv {
			    @MDB_environment
			    public struct CoreA: Sendable {
			        public let env: Environment
			        public let a: Database.Strict<TestKey, TestValue>
			    }
			    public let coreA: CoreA
			}
			""",
			expanded: """
			
			public struct StoreEnv {
			    @MDB_environment
			    public struct CoreA: Sendable {
			        public let env: Environment
			        public let a: Database.Strict<TestKey, TestValue>
			    }
			    public let coreA: CoreA

			    /// the shared environment handle of this group's physical environment — every member core opens from the same value.
			    public var env: Environment {
			        coreA.env
			    }

			    public static let mdb_core_names: [String] = ["coreA"]

			    /// opens the physical environment once and constructs every member core from it —
			    /// all member tables are created in a single setup write-transaction.
			    /// - parameter basePath: the directory that will contain the environment file (created if
			    ///   it does not already exist).
			    /// - parameter mapHeadroom: added to the current file size when sizing the memory map.
			    @available(*, noasync)
			    public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)
			        let slash = basePath.hasSuffix("/") ? "" : "/"
			        let targetPath = basePath + slash + ("store.mdb".hasSuffix(".mdb") ? String("store.mdb".dropLast(4)) + "-v2" + ".mdb" : "store.mdb" + "-v2")
			        let fileSize = QuickLMDB._MDBEnvironmentSupport.__fileSize(at: targetPath)
			        let env = try Environment(path: targetPath, flags: QuickLMDB.Environment.Flags([.noTLS]).union([.noSubDir]), mapSize: Int(fileSize + mapHeadroom), maxReaders: 32, maxDBs: 8, mode: [.ownerReadWriteExecute, .groupRead, .otherRead])
			        let setupTX = try Transaction<Write>(env: env)
			        let a = try Database.Strict<TestKey, TestValue>(env: env, name: "a", flags: [.create], tx: setupTX)
			        let coreA = CoreA(env: env, a: a)
			        try setupTX.commit()
			        return Self(coreA: coreA)
			    }
			}

			extension StoreEnv: MDB_environment {
			}
			"""
		)
	}

	// - MARK: validation (seeded path — member-macro throws record there)

	@Test func rejectsNonStructTargets() {
		assertGroupError(
			"""
			@MDB_env_group(file: "x.mdb")
			enum NotAStruct {
			}
			""",
			["@MDB_env_group can only be applied to a struct"]
		)
	}

	@Test func requiresFileArgument() {
		assertGroupError(
			"""
			@MDB_env_group
			struct Group {
			    @MDB_environment
			    struct M: Sendable {
			        let env: Environment
			        let t: Database.Strict<TestKey, TestValue>
			    }
			    let m: M
			}
			""",
			["@MDB_env_group requires a `file:` argument naming the environment file (e.g. @MDB_env_group(file: \"daemon.mdb\"))"]
		)
	}

	@Test func requiresAtLeastOneArrangedMember() {
		assertGroupError(
			"""
			@MDB_env_group(file: "x.mdb")
			struct Group {
			    static let helper = 1
			}
			""",
			["@MDB_env_group requires at least one member core — a stored property of a nested @MDB_environment struct type, e.g. `public let daemon: DaemonDB`"]
		)
	}

	@Test func rejectsNonMemberProperties() {
		assertGroupError(
			"""
			@MDB_env_group(file: "x.mdb")
			struct Group {
			    public let x: Int
			}
			""",
			["@MDB_env_group: stored property 'x' has type 'Int' which is not a nested @MDB_environment member core — a group's stored instance properties must be exactly its member cores"]
		)
	}

	@Test func rejectsUnownedMemberCores() {
		assertGroupError(
			"""
			@MDB_env_group(file: "x.mdb")
			struct Group {
			    @MDB_environment
			    struct A: Sendable {
			        let env: Environment
			        let a: Database.Strict<TestKey, TestValue>
			    }
			    @MDB_environment
			    struct B: Sendable {
			        let env: Environment
			        let b: Database.Strict<TestKey, TestValue>
			    }
			    let a: A
			}
			""",
			["@MDB_env_group: member core 'B' is declared but not arranged as a stored property — add one property of its type and remove any field you delegate outside the group"]
		)
	}

	@Test func rejectsDoubleArrangement() {
		assertGroupError(
			"""
			@MDB_env_group(file: "x.mdb")
			struct Group {
			    @MDB_environment
			    struct A: Sendable {
			        let env: Environment
			        let a: Database.Strict<TestKey, TestValue>
			    }
			    let first: A
			    let second: A
			}
			""",
			["@MDB_env_group: member core 'A' is arranged by more than one stored property — each member core is arranged exactly once"]
		)
	}

	@Test func rejectsAPropertyNamedEnv() {
		assertGroupError(
			"""
			@MDB_env_group(file: "x.mdb")
			struct Group {
			    public let env: Int
			}
			""",
			["@MDB_env_group: no stored property may be named `env` — the group owns that name for its shared-environment accessor"]
		)
	}

	@Test func rejectsCrossMemberTableNameCollisions() {
		assertGroupError(
			"""
			@MDB_env_group(file: "x.mdb")
			struct Group {
			    @MDB_environment
			    struct A: Sendable {
			        let env: Environment
			        let entries: Database.Strict<TestKey, TestValue>
			    }
			    @MDB_environment
			    struct B: Sendable {
			        let env: Environment
			        let entries: Database.Strict<TestKey, TestValue>
			    }
			    let a: A
			    let b: B
			}
			""",
			["@MDB_env_group: table \"entries\" on member 'b' collides with a table already claimed by another member — member cores share one physical environment, so table names must be unique across the group"]
		)
	}

	// - MARK: the member-core variant (nested @MDB_environment inside a group)

	// the seeded contexts here walk parents so the nested member macro sees the
	// enclosing @MDB_env_group struct, exactly as the real compiler's
	// lexicalContext does — that is what makes a nested core schema-only.
	private static let memberMacros: [String: Macro.Type] = [
		"MDB_env_group": MDB_env_group_macro.self,
		"MDB_environment": MDB_environment_macro.self,
	]

	private func assertMemberError(_ source: String, _ expectedDiags: [String]) {
		let file = Parser.parse(source: source)
		var contexts: [BasicMacroExpansionContext] = []
		_ = file.expand(macros: Self.memberMacros, contextGenerator: { node in
			// seed the lexical context with the enclosing group struct chain so
			// the member macro's nesting detection fires (parent-walk)
			var ancestors: [Syntax] = []
			var current = node.parent
			while let c = current {
				if c.is(StructDeclSyntax.self) { ancestors.append(Syntax(c)) }
				current = c.parent
			}
			let ctx = BasicMacroExpansionContext(lexicalContext: ancestors)
			contexts.append(ctx)
			return ctx
		})
		let actual = contexts.flatMap { $0.diagnostics.map(\.message) }
		#expect(actual == expectedDiags, Comment(stringLiteral: "diagnostics mismatch: \(actual)"))
	}

	@Test func memberCoreCarriesNoFileOrEnvTuning() {
		assertMemberError(
			"""
			@MDB_env_group(file: "x.mdb")
			struct Group {
			    @MDB_environment(file: "member.mdb")
			    struct A: Sendable {
			        let env: Environment
			        let a: Database.Strict<TestKey, TestValue>
			    }
			    let a: A
			}
			""",
			["@MDB_environment inside a @MDB_env_group is a MEMBER CORE: it cannot carry a `file:`/`version:`/`flags:`/`maxReaders:`/`maxDBs:`/`mode:` — the group owns the physical environment and its tuning"]
		)
	}

	@Test func standaloneCoreStillRequiresFile() {
		assertMemberError(
			"""
			struct Holder {
			    @MDB_environment
			    struct A: Sendable {
			        let env: Environment
			        let a: Database.Strict<TestKey, TestValue>
			    }
			}
			""",
			["@MDB_environment requires a `file:` argument naming the environment file (e.g. @MDB_environment(file: \"store.mdb\"))"]
		)
	}
}
