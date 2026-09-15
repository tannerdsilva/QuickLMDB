import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
import Foundation
@testable import QuickLMDBMacros

// expansion fixtures for the WRITE-COMPOSITION LINT (the compile-time
// write-at-depth guard) that lives in the @MDB_environment MEMBER macro.
//
// the boundary body/peer roles get a lexicalContext SHELL under the real
// compiler (empty member list — verified), so classifying same-type write
// callees is impossible there; the member role is the only one that sees every
// member and body, and it emits one error per BARE/`self.` call to a same-type
// `.readWrite` boundary:
//   - from a `.readWrite` boundary → "opens a SECOND root write ... compose
//     with try #MDB_transacted(...)" (the sanctioned join),
//   - from a `.readOnly` boundary → "a read transaction cannot host a write".
// joined calls (#MDB_transacted-wrapped), sibling reads, cross-type receivers
// and plain methods are each left alone.

private let lintMacros: [String: Macro.Type] = [
	"MDB_environment": MDB_environment_macro.self,
	"MDB_transacted": MDB_transacted_macro.self,
]

/// seeded `file.expand`: `assertMacroExpansion` does NOT capture member-role
/// diagnostics, so contexts are collected and compared by message. the
/// `#MDB_transacted(...)` STANDALONE fallback also fires here (the enclosing
/// body macro does not run on the seeded path) — those
/// "must appear inside an @MDB_transact body" messages are filtered so the
/// assertion sees exactly the lint's output.
private func lintDiagnostics(_ source: String) -> [String] {
	let file = Parser.parse(source: source)
	var contexts: [BasicMacroExpansionContext] = []
	_ = file.expand(macros: lintMacros, contextGenerator: { node in
		let ctx = BasicMacroExpansionContext()
		contexts.append(ctx)
		return ctx
	})
	return contexts
		.flatMap { $0.diagnostics }
		.map { $0.message }
		.filter { !$0.contains("#MDB_transacted must appear inside an @MDB_transact body") }
}

@Suite("MDB_environment — write-composition lint (write-at-depth guard)")
struct WriteCompositionLintTests {

	@Test func bareWriteCallInsideWriteBoundaryDiagnosesExactlyOnce() {
		let diags = lintDiagnostics("""
			@MDB_environment(file: "db.mdb")
			struct Ledger {
			    let env: Environment
			    let entries: Database.Strict<Key, Value>
			    @MDB_transact(.readWrite)
			    func commit(_ key: Key) throws {
			        try post(key)
			    }
			    @MDB_transact(.readWrite)
			    func post(_ key: Key) throws {
			    }
			}
			""")
		#expect(diags == [
			"calling write boundary 'post' from inside a write boundary opens a SECOND root write on this environment and deadlocks LMDB's writer mutex — compose with try #MDB_transacted(post(...)) so the callee runs as a child transaction of this boundary"
		])
	}

	@Test func selfQualifiedWriteCallAlsoDiagnoses() {
		let diags = lintDiagnostics("""
			@MDB_environment(file: "db.mdb")
			struct Ledger {
			    let env: Environment
			    let entries: Database.Strict<Key, Value>
			    @MDB_transact(.readWrite)
			    func commit(_ key: Key) throws {
			        try self.post(key)
			    }
			    @MDB_transact(.readWrite)
			    func post(_ key: Key) throws {
			    }
			}
			""")
		#expect(diags.count == 1)
		#expect(diags[0].contains("deadlocks LMDB's writer mutex"))
	}

	@Test func joinedWriteCallIsSilent() {
		let diags = lintDiagnostics("""
			@MDB_environment(file: "db.mdb")
			struct Ledger {
			    let env: Environment
			    let entries: Database.Strict<Key, Value>
			    @MDB_transact(.readWrite)
			    func commit(_ key: Key) throws {
			        try #MDB_transacted(post(key))
			    }
			    @MDB_transact(.readWrite)
			    func post(_ key: Key) throws {
			    }
			}
			""")
		#expect(diags == [])
	}

	@Test func mixedJoinAndBareCallDiagnosesOnlyTheBareOne() {
		let diags = lintDiagnostics("""
			@MDB_environment(file: "db.mdb")
			struct Ledger {
			    let env: Environment
			    let entries: Database.Strict<Key, Value>
			    @MDB_transact(.readWrite)
			    func commit(_ key: Key) throws {
			        try #MDB_transacted(post(key))
			        try post(key)
			    }
			    @MDB_transact(.readWrite)
			    func post(_ key: Key) throws {
			    }
			}
			""")
		#expect(diags.count == 1)
		#expect(diags[0].contains("try #MDB_transacted(post(...))"))
	}

	@Test func bareWriteCallInsideReadOnlyBoundaryDiagnoses() {
		let diags = lintDiagnostics("""
			@MDB_environment(file: "db.mdb")
			struct Ledger {
			    let env: Environment
			    let entries: Database.Strict<Key, Value>
			    @MDB_transact(.readOnly)
			    func inspect(_ key: Key) throws {
			        try post(key)
			    }
			    @MDB_transact(.readWrite)
			    func post(_ key: Key) throws {
			    }
			}
			""")
		#expect(diags == [
			"calling write boundary 'post' from a read-only boundary cannot compose — a read transaction cannot host a write. make this boundary read-write, or call 'post' outside the boundary"
		])
	}

	@Test func siblingReadCallStaysSilent() {
		let diags = lintDiagnostics("""
			@MDB_environment(file: "db.mdb")
			struct Ledger {
			    let env: Environment
			    let entries: Database.Strict<Key, Value>
			    @MDB_transact(.readWrite)
			    func commit(_ key: Key) throws -> Value? {
			        try read(key)
			    }
			    @MDB_transact(.readOnly)
			    func read(_ key: Key) throws -> Value? {
			        return nil
			    }
			}
			""")
		#expect(diags == [])
	}

	@Test func crossTypeWriteCalleeIsExempt() {
		let diags = lintDiagnostics("""
			@MDB_environment(file: "a.mdb")
			struct A {
			    let env: Environment
			    let table: Database.Strict<Key, Value>
			    @MDB_transact(.readWrite)
			    func outer(_ key: Key, other: B) throws {
			        try other.post(key)
			    }
			}
			""")
		#expect(diags == [])
	}

	@Test func plainMethodCallStaysSilent() {
		let diags = lintDiagnostics("""
			@MDB_environment(file: "db.mdb")
			struct Ledger {
			    let env: Environment
			    let entries: Database.Strict<Key, Value>
			    @MDB_transact(.readWrite)
			    func commit(_ key: Key) throws {
			        helper(key)
			    }
			    func helper(_ key: Key) {
			    }
			}
			""")
		#expect(diags == [])
	}

	@Test func nonBoundaryCallerIsNotLinted() {
		let diags = lintDiagnostics("""
			@MDB_environment(file: "db.mdb")
			struct Ledger {
			    let env: Environment
			    let entries: Database.Strict<Key, Value>
			    @MDB_transact(.readWrite)
			    func post(_ key: Key) throws {
			    }
			    func plain(_ key: Key) throws {
			        try post(key)
			    }
			}
			""")
		#expect(diags == [])
	}

	@Test func nestedWriteCallsDiagnoseInClosuresToo() {
		let diags = lintDiagnostics("""
			@MDB_environment(file: "db.mdb")
			struct Ledger {
			    let env: Environment
			    let entries: Database.Strict<Key, Value>
			    @MDB_transact(.readWrite)
			    func commit(_ keys: [Key]) throws {
			        for key in keys {
			            try post(key)
			        }
			    }
			    @MDB_transact(.readWrite)
			    func post(_ key: Key) throws {
			    }
			}
			""")
		#expect(diags.count == 1)
		#expect(diags[0].contains("compose with try #MDB_transacted(post(...))"))
	}
}
