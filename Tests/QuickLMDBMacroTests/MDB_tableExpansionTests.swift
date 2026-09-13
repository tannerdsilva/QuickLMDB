import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
import Foundation
@testable import QuickLMDBMacros

// schema-layer fixtures (port phase 1): @MDB_table placement validation +
// @MDB_environment consumption (name override, extra flags, and the name /
// flags-vs-type diagnostics). derived defaults must be byte-identical to the
// pre-@MDB_table shape for bare properties.

private let schemaMacros: [String: Macro.Type] = [
	"MDB_environment": MDB_environment_macro.self,
	"MDB_table": MDB_table_macro.self,
]

// NOTE: the schema fixtures use seeded file.expand paths below rather than
// assertMacroExpansion: the table macro gates on the ENCLOSING core struct, and
// assertMacroExpansion's contexts have empty lexicalContext, which would
// spuriously fail its placement check. positives byte-compare the expansion;
// negatives collect diagnostics by message.

/// seeded contexts: a blank `BasicMacroExpansionContext` gives EMPTY
/// lexicalContext, so a peer that gates on the enclosing type (the table
/// macro's core check) is seeded by walking each node's parent chain to the
/// enclosing struct (in-process trees have parents — the span suite's
/// established pattern).
private func expandSeeded(_ source: String) -> (file: Syntax, contexts: [BasicMacroExpansionContext]) {
	let file = Parser.parse(source: source)
	var contexts: [BasicMacroExpansionContext] = []
	let expanded = file.expand(macros: schemaMacros, contextGenerator: { node in
		var enclosingStruct: StructDeclSyntax? = nil
		var current: Syntax? = node
		while let c = current {
			if let sd = c.as(StructDeclSyntax.self) {
				enclosingStruct = sd
				break
			}
			current = c.parent
		}
		let ctx = BasicMacroExpansionContext(lexicalContext: enclosingStruct.map { [Syntax($0)] } ?? [])
		contexts.append(ctx)
		return ctx
	})
	return (expanded, contexts)
}

/// seeded positive-path: byte compares the expansion (the table macro's
/// enclosing-core check sees the real struct, so no spurious placement error).
private func assertSchemaExpansion(_ source: String, expanded expected: String) {
	let (file, _) = expandSeeded(source)
	let actual = String(describing: file)
	#expect(actual == expected, Comment(stringLiteral: "schema expansion mismatch: \(actual)"))
}

/// negative-path helper: asserts the recorded diagnostics' messages.
private func assertSchemaError(_ source: String, _ expectedDiags: [String]) {
	let (_, contexts) = expandSeeded(source)
	let actual = contexts.flatMap { $0.diagnostics.map { $0.message } }
	#expect(actual == expectedDiags, Comment(stringLiteral: "diagnostics mismatch: \(actual)"))
}

@Suite("MDB_table — @MDB_environment derived + consumed expansion")
struct TableSchemaExpansionTests {

	@Test func bareTablesDeriveDefaults() {
		// byte-frozen oracle (actual expansion spliced from the dump harness)
		assertSchemaExpansion(
			"""
			@MDB_environment(file: "test.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
			struct Core {
				let env: Environment
				let events: Database.Strict<TestKey, TestValue>
				let logs: Database.DupSort<TestKey, TestValue>
			}
			""",
			expanded: """
			
			struct Core {
				let env: Environment
				let events: Database.Strict<TestKey, TestValue>
				let logs: Database.DupSort<TestKey, TestValue>
			
			    @available(*, noasync)
			
			    public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {
			
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)
			
			    let slash = basePath.hasSuffix("/") ? "" : "/"

			    let targetPath = basePath + slash + "test.mdb"
			
			    let fileSize = QuickLMDB._MDBEnvironmentSupport.__fileSize(at: targetPath)
			
			    let env = try Environment(path: targetPath, flags: QuickLMDB.Environment.Flags([.noTLS]).union([.noSubDir]), mapSize: Int(fileSize + mapHeadroom), maxReaders: 16, maxDBs: 8, mode: [.ownerReadWriteExecute, .groupRead, .otherRead])
			
			    let setupTX = try Transaction<Write>(env: env)
			
			    let events = try Database.Strict<TestKey, TestValue>(env: env, name: "events", flags: [.create], tx: setupTX)
			
			    let logs = try Database.DupSort<TestKey, TestValue>(env: env, name: "logs", flags: [.create], tx: setupTX)
			
			        try setupTX.commit()
			
			        return Self(env: env, events: events, logs: logs)
			
			    }
			}
			
			extension Core: MDB_environment {
			}
			"""
		)
	}

	@Test func tableAttributesOverrideNameAndUnionFlags() {
		// byte-frozen oracle (actual expansion spliced from the dump harness)
		assertSchemaExpansion(
			"""
			@MDB_environment(file: "test.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
			struct Core {
				let env: Environment
				@MDB_table(name: "event_log", flags: [.reverseKey])
				let events: Database.Strict<TestKey, TestValue>
				@MDB_table(flags: [.dupSort, .dupFixed])
				let blobs: Database
			}
			""",
			expanded: """
			
			struct Core {
				let env: Environment
				let events: Database.Strict<TestKey, TestValue>
				let blobs: Database
			
			    @available(*, noasync)
			
			    public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {
			
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)
			
			    let slash = basePath.hasSuffix("/") ? "" : "/"

			    let targetPath = basePath + slash + "test.mdb"
			
			    let fileSize = QuickLMDB._MDBEnvironmentSupport.__fileSize(at: targetPath)
			
			    let env = try Environment(path: targetPath, flags: QuickLMDB.Environment.Flags([.noTLS]).union([.noSubDir]), mapSize: Int(fileSize + mapHeadroom), maxReaders: 16, maxDBs: 8, mode: [.ownerReadWriteExecute, .groupRead, .otherRead])
			
			    let setupTX = try Transaction<Write>(env: env)
			
			    let events = try Database.Strict<TestKey, TestValue>(env: env, name: "event_log", flags: QuickLMDB.MDB_db_flags([.create]).union([.reverseKey]), tx: setupTX)
			
			    let blobs = try Database(env: env, name: "blobs", flags: QuickLMDB.MDB_db_flags([.create]).union([.dupSort, .dupFixed]), tx: setupTX)
			
			        try setupTX.commit()
			
			        return Self(env: env, events: events, blobs: blobs)
			
			    }
			}
			
			extension Core: MDB_environment {
			}
			"""
		)
	}

}

@Suite("MDB_table — placement validation")
struct TablePlacementTests {

	@Test func rejectsNonPropertyTargets() {
		assertSchemaError(
			"""
			struct Core {
				@MDB_table
				static func f() {}
			}
			""",
			["@MDB_table must be attached to a stored table property (a `Database` or `Database.X<...>` stored property) — it configures a table's declaration"]
		)
	}

	@Test func rejectsNonTablePropertyTargets() {
		assertSchemaError(
			"""
			struct Core {
				@MDB_table
				let name: String = ""
			}
			""",
			["@MDB_table target has type 'String', which is not a table — expected `Database` or `Database.X<...>`"]
		)
	}

	@Test func rejectsTableOutsideAnEnvironmentCore() {
		assertSchemaError(
			"""
			struct Plain {
				@MDB_table
				let events: Database.Strict<TestKey, TestValue> = Database.Strict()
			}
			""",
			["@MDB_table can only be used inside an @MDB_environment core — tables belong to a core's schema"]
		)
	}
}

@Suite("MDB_table — @MDB_environment consumption")
struct TableConsumptionTests {

	@Test func rejectsEmptyTableName() {
		assertSchemaError(
			"""
			@MDB_environment(file: "test.mdb")
			struct Core {
				let env: Environment
				@MDB_table(name: "")
				let events: Database.Strict<TestKey, TestValue>
			}
			""",
			["@MDB_table(name: \"\") is not a valid LMDB table name — the name must be a non-empty string without NUL characters"]
		)
	}

	@Test func rejectsDuplicateResolvedNames() {
		assertSchemaError(
			"""
			@MDB_environment(file: "test.mdb")
			struct Core {
				let env: Environment
				@MDB_table(name: "shared")
				let events: Database.Strict<TestKey, TestValue>
				let shared: Database.Strict<TestKey, TestValue>
			}
			""",
			["two tables resolve to the same LMDB table name \"shared\" — table names must be unique within an environment"]
		)
	}

	@Test func rejectsDupFlagsOnStrictHandle() {
		assertSchemaError(
			"""
			@MDB_environment(file: "test.mdb")
			struct Core {
				let env: Environment
				@MDB_table(flags: [.dupSort])
				let events: Database.Strict<TestKey, TestValue>
			}
			""",
			["@MDB_table(flags: [.dupSort]) on 'events' contradicts its declared type — the dup-sort flags are expressed by the typed subtype (Strict/DupSort/DupFixed), not by this attribute"]
		)
	}

	@Test func versionedEnvironmentDerivesTheFileSuffix() {
		// writing `version:` derives the on-disk name `<stem>-v<N>.mdb`;
		// a bare core keeps its exact file name (pinned by the bare fixture
		// above). byte-frozen oracle (actual expansion spliced from the dump).
		assertSchemaExpansion(
			"""
			@MDB_environment(file: "test.mdb", version: 2, flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
			struct Core {
				let env: Environment
				let events: Database.Strict<TestKey, TestValue>
			}
			""",
			expanded: """
			
			struct Core {
				let env: Environment
				let events: Database.Strict<TestKey, TestValue>
			
			    @available(*, noasync)
			
			    public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {
			
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)
			
			    let slash = basePath.hasSuffix("/") ? "" : "/"

			    let targetPath = basePath + slash + ("test.mdb".hasSuffix(".mdb") ? String("test.mdb".dropLast(4)) + "-v2" + ".mdb" : "test.mdb" + "-v2")
			
			    let fileSize = QuickLMDB._MDBEnvironmentSupport.__fileSize(at: targetPath)
			
			    let env = try Environment(path: targetPath, flags: QuickLMDB.Environment.Flags([.noTLS]).union([.noSubDir]), mapSize: Int(fileSize + mapHeadroom), maxReaders: 16, maxDBs: 8, mode: [.ownerReadWriteExecute, .groupRead, .otherRead])
			
			    let setupTX = try Transaction<Write>(env: env)
			
			    let events = try Database.Strict<TestKey, TestValue>(env: env, name: "events", flags: [.create], tx: setupTX)
			
			        try setupTX.commit()
			
			        return Self(env: env, events: events)
			
			    }
			}
			
			extension Core: MDB_environment {
			}
			"""
		)
	}
}
