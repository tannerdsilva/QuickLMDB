import SwiftParser
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import QuickLMDBMacros

// expansion fixtures for @MDB_layout — the ENVIRONMENT ARRANGEMENT helper
// (no per-core factories, no statics, no baked path): inventory + open.

private let layoutMacros: [String: Macro.Type] = [
	"MDB_layout": MDB_layout_macro.self,
]

private func assertLayoutExpansion(_ source: String, expanded expected: String) {
	assertMacroExpansion(
		source,
		expandedSource: expected,
		macroSpecs: layoutMacros.mapValues { MacroSpec(type: $0) },
		failureHandler: { spec in Issue.record(Comment(stringLiteral: spec.message)) }
	)
}

/// negative-path helper: thrown member-macro errors are not captured by
/// assertMacroExpansion's context — the seeded file.expand path records them.
private func assertLayoutError(_ source: String, _ expectedDiags: [String]) {
	let file = Parser.parse(source: source)
	var contexts: [BasicMacroExpansionContext] = []
	_ = file.expand(macros: layoutMacros, contextGenerator: { node in
		let ctx = BasicMacroExpansionContext()
		contexts.append(ctx)
		return ctx
	})
	let actual = contexts.flatMap { $0.diagnostics.map(\.message) }
	#expect(actual == expectedDiags, Comment(stringLiteral: "diagnostics mismatch: \(actual)"))
}

@Suite("MDB_layout — the arrangement (generated surface)")
struct MDBlayoutExpansionTests {

	@Test func arrangementGeneratesInventoryAndOpen() {
		assertLayoutExpansion(
			"""
			@MDB_layout
			public struct App {
			    public var calendar: CalendarCore
			    public var contacts: ContactsCore
			}
			""",
			expanded: """
			
			public struct App {
			    public var calendar: CalendarCore
			    public var contacts: ContactsCore
			
			    public static let mdb_core_names: [String] = ["calendar", "contacts"]
			
			    @available(*, noasync)
			    public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {
			        let calendar = try CalendarCore.open(at: basePath + "/" + "calendar")
			        let contacts = try ContactsCore.open(at: basePath + "/" + "contacts")
			        return Self(calendar: calendar, contacts: contacts)
			    }
			}
			"""
		)
	}

	// - MARK: validation (seeded path — member-macro throws record there)

	@Test func rejectsNonStructTargets() {
		assertLayoutError(
			"""
			@MDB_layout
			enum NotAStruct {
			}
			""",
			["@MDB_layout can only be applied to a struct"]
		)
	}

	@Test func rejectsEmptyCoreSets() {
		assertLayoutError(
			"""
			@MDB_layout
			struct App {
			    static let helper = 1
			}
			""",
			["@MDB_layout requires at least one stored property — the environment cores the arrangement owns"]
		)
	}
}
