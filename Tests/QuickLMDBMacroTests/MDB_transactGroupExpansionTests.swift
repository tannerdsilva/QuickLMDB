import SwiftParser
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import QuickLMDBMacros

// expansion fixtures for the group-aware boundary dialect: `@MDB_transact`
// keying transactions to the ENVIRONMENT GROUP (`tx_<Group>`) so a boundary
// over several member cores of one physical env opens ONE transaction — the
// double-write self-deadlock is structurally unreachable. membership is
// positional (nested member cores), read from the type spelling alone.

private let boundaryMacros: [String: Macro.Type] = [
	"MDB_transact": MDB_transact_macro.self,
	"MDB_transacted": MDB_transacted_macro.self,
	"store": MDB_verb_error_macro.self,
	"load": MDB_verb_error_macro.self,
	"contains": MDB_verb_error_macro.self,
]

private func assertExpansion(_ source: String, expanded expected: String) {
	assertMacroExpansion(
		source,
		expandedSource: expected,
		macroSpecs: boundaryMacros.mapValues { MacroSpec(type: $0) },
		failureHandler: { spec in Issue.record(Comment(stringLiteral: spec.message)) }
	)
}

@Suite("MDB_transact — group-keyed boundaries (shared physical env)")
struct MDBTransactGroupExpansionTests {

	@Test func groupSelfBoundaryOpensOneTransaction() {
		// byte-frozen oracle: a boundary on the GROUP struct addresses member
		// tables through chained keypaths; its single label IS the group, so
		// one transaction covers every member the body touches.
		assertExpansion(
			"""
			public struct SharedEnv {
			    public struct AlphaCore {
			        public let env: Environment
			        public let alphaEntries: Database.Strict<Key, Value>
			    }
			    public let alpha: AlphaCore
			    @MDB_transact(.readWrite)
			    public func writePair(_ k: Key, _ v: Value) throws {
			        try #store(SharedEnv.self, database: \\.alpha.alphaEntries, key: k, value: v)
			    }
			}
			""",
			expanded: """

			public struct SharedEnv {
			    public struct AlphaCore {
			        public let env: Environment
			        public let alphaEntries: Database.Strict<Key, Value>
			    }
			    public let alpha: AlphaCore
			    public func writePair(_ k: Key, _ v: Value) throws {
			        let tx_SharedEnv = try Transaction<Write>(env: self.env)
			        do {
			            try self.writePair(k, v, tx_SharedEnv: tx_SharedEnv)
			        } catch let error {
			            tx_SharedEnv.abort()
			            throw error
			        }
			        try tx_SharedEnv.commit()
			    }

			    public func writePair(_ k: Key, _ v: Value, tx_SharedEnv: borrowing Transaction<Write>) throws {
			        try self[keyPath: \\.alpha.alphaEntries].store(key: k, value: v, tx: tx_SharedEnv)
			    }
			}
			"""
		)
	}

	@Test func memberSiblingBoundaryCollapsesToOneTransaction() {
		// byte-frozen oracle: the boundary touches TWO member cores (self +
		// a sibling member parameter) — the shell emits ONE `tx_SharedEnv`
		// and both verbs lower to it. this boundary was IMPOSSIBLE before the
		// group layer (two write transactions on one env = self-deadlock).
		assertExpansion(
			"""
			public struct SharedEnv {
			    public struct AlphaCore {
			        public let env: Environment
			        public let alphaEntries: Database.Strict<Key, Value>
			    }
			    public struct BetaCore {
			        public let env: Environment
			        public let betaEntries: Database.Strict<Key, Value>
			    }
			}
			extension SharedEnv.AlphaCore {
			    @MDB_transact(.readWrite)
			    public func writeSibling(_ k: Key, _ v: Value, beta: SharedEnv.BetaCore) throws {
			        try #store(SharedEnv.AlphaCore.self, database: \\.alphaEntries, key: k, value: v)
			        try #store(SharedEnv.BetaCore.self, database: \\.betaEntries, key: k, value: v)
			    }
			}
			""",
			expanded: """

			public struct SharedEnv {
			    public struct AlphaCore {
			        public let env: Environment
			        public let alphaEntries: Database.Strict<Key, Value>
			    }
			    public struct BetaCore {
			        public let env: Environment
			        public let betaEntries: Database.Strict<Key, Value>
			    }
			}
			extension SharedEnv.AlphaCore {
			    public func writeSibling(_ k: Key, _ v: Value, beta: SharedEnv.BetaCore) throws {
			        let tx_SharedEnv = try Transaction<Write>(env: self.env)
			        do {
			            try self.writeSibling(k, v, beta: beta, tx_SharedEnv: tx_SharedEnv)
			        } catch let error {
			            tx_SharedEnv.abort()
			            throw error
			        }
			        try tx_SharedEnv.commit()
			    }

			    public func writeSibling(_ k: Key, _ v: Value, beta: SharedEnv.BetaCore, tx_SharedEnv: borrowing Transaction<Write>) throws {
			        try self[keyPath: \\.alphaEntries].store(key: k, value: v, tx: tx_SharedEnv)
			        try beta[keyPath: \\.betaEntries].store(key: k, value: v, tx: tx_SharedEnv)
			    }
			}
			"""
		)
	}

	@Test func coordinatorInGroupStructIsInferredFromSelf() {
		// byte-frozen oracle: a VERB-LESS boundary on the group struct — its
		// env set is inferred from self being a @MDB_env_group (the attribute
		// sits on the seeded enclosing struct). the pure-`#MDB_transacted`
		// body threads the one group transaction into the joined member
		// boundary; no artificial `#stats` anchor.
		assertExpansion(
			"""
			@MDB_env_group(file: "shared.mdb")
			public struct SharedEnv {
			    public struct AlphaCore {
			        public let env: Environment
			        public let alphaEntries: Database.Strict<Key, Value>
			    }
			    public let alpha: AlphaCore
			    @MDB_transact(.readWrite)
			    public func persist(_ k: Key, _ v: Value) throws {
			        try #MDB_transacted(alpha.put(k, v))
			    }
			}
			""",
			expanded: """

			@MDB_env_group(file: "shared.mdb")
			public struct SharedEnv {
			    public struct AlphaCore {
			        public let env: Environment
			        public let alphaEntries: Database.Strict<Key, Value>
			    }
			    public let alpha: AlphaCore
			    public func persist(_ k: Key, _ v: Value) throws {
			        let tx_SharedEnv = try Transaction<Write>(env: self.env)
			        do {
			            try self.persist(k, v, tx_SharedEnv: tx_SharedEnv)
			        } catch let error {
			            tx_SharedEnv.abort()
			            throw error
			        }
			        try tx_SharedEnv.commit()
			    }

			    public func persist(_ k: Key, _ v: Value, tx_SharedEnv: borrowing Transaction<Write>) throws {
			        try alpha.put(k, v, tx_SharedEnv: tx_SharedEnv)
			    }
			}
			"""
		)
	}

	@Test func mixedGroupAndForeignKeepsTwoLabelsWithGuard() {
		// byte-frozen oracle: a same-group pair AND a distinct-env core keeps
		// two labels (tx_SharedEnv, tx_ForeignCore) — exception-atomic across
		// both — with the runtime double-open guard emitted for >1 label.
		assertExpansion(
			"""
			public struct SharedEnv {
			    public let alpha: AlphaCore
			    @MDB_transact(.readWrite)
			    public func mixed(_ k: Key, _ v: Value, foreign: ForeignCore) throws {
			        try #store(SharedEnv.self, database: \\.alpha.alphaEntries, key: k, value: v)
			        try #store(ForeignCore.self, database: \\.foreignEntries, key: k, value: v)
			    }
			}
			""",
			expanded: """

			public struct SharedEnv {
			    public let alpha: AlphaCore
			    public func mixed(_ k: Key, _ v: Value, foreign: ForeignCore) throws {
			        // one transaction per resolved environment — two labels resolving to the same
			            // Environment INSTANCE would be a double-open (LMDB writer-mutex self-deadlock)
			            let __mdb_envs: [Environment] = [foreign.env, self.env]
			            for __mdb_i in 0..<__mdb_envs.count {
			                for __mdb_j in (__mdb_i + 1)..<__mdb_envs.count {
			                    if __mdb_envs[__mdb_i] === __mdb_envs[__mdb_j] { throw LMDBError.duplicateEnvironment }
			                }
			            }
			        let tx_ForeignCore = try Transaction<Write>(env: foreign.env)
			        let tx_SharedEnv = try Transaction<Write>(env: self.env)
			        do {
			            try self.mixed(k, v, foreign: foreign, tx_ForeignCore: tx_ForeignCore, tx_SharedEnv: tx_SharedEnv)
			        } catch let error {
			            tx_ForeignCore.abort()
			            tx_SharedEnv.abort()
			            throw error
			        }
			        try tx_ForeignCore.commit()
			        try tx_SharedEnv.commit()
			    }

			    public func mixed(_ k: Key, _ v: Value, foreign: ForeignCore, tx_ForeignCore: borrowing Transaction<Write>, tx_SharedEnv: borrowing Transaction<Write>) throws {
			        try self[keyPath: \\.alpha.alphaEntries].store(key: k, value: v, tx: tx_SharedEnv)
			        try foreign[keyPath: \\.foreignEntries].store(key: k, value: v, tx: tx_ForeignCore)
			    }
			}
			"""
		)
	}
}
