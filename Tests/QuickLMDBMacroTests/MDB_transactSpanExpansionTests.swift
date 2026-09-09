import Testing
import Foundation
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
@testable import QuickLMDBMacros

// strict expansion fixtures for @MDB_transact_span (attached body macro) and the
// @MDB_app container (inventory + generated open(at:) factory). the span gates on the
// @MDB_app attribute of the ENCLOSING type; assertMacroExpansion never populates
// lexicalContext for body macros, so this harness seeds the context per expansion
// node by walking the node's parent chain to the enclosing struct (in-process tree
// walks work). mismatches record a Swift Testing Issue.

private func assertSpanExpansion(_ source: String, expected expanded: String, diagnostics expectedDiags: [String]? = nil) {
	var contexts: [BasicMacroExpansionContext] = []
	let file = Parser.parse(source: source)
	// the contextGenerator form returns plain Syntax (never fails)
	let expandedFile = file.expand(macros: [
		"MDB_app": MDB_app_macro.self,
		"MDB_transact_span": MDB_transact_span_macro.self
	], contextGenerator: { node in
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
	#expect(String(describing: expandedFile) == expanded, Comment(stringLiteral: "span expansion mismatch: \(String(describing: expandedFile))"))
	guard let expectedDiags else { return }
	var actualDiags: [String] = []
	for context in contexts {
		for diagnostic in context.diagnostics {
			actualDiags.append(diagnostic.message)
		}
	}
	#expect(actualDiags == expectedDiags, Comment(stringLiteral: "span diagnostics mismatch: \(actualDiags)"))
}

@Suite("MDB_transact_span body macro expansion")
struct MDB_transactSpanExpansionTests {

	@Test func bareTwoReadWriteMembersCommitInOrder() {
		// bare span: two readWrite members inferred from #store receivers, first-touch order
		assertSpanExpansion(
			"""
			@MDB_app
			struct HybridApp {
			    var calendar: CalendarCore
			    var contacts: ContactCore
			    @MDB_transact_span
			    func scheduleMeeting(_ event: EventID, on day: DayKey, invitees: [ContactID], at timestamp: Timestamp) throws {
			        try #store(calendar.events, key: day, value: event)
			        try #store(calendar.invitees, key: event, value: invitees[0])
			        try #store(contacts.lastSync, key: invitees[0], value: timestamp)
			    }
			}
			""",
			expected: """

			struct HybridApp {
			    var calendar: CalendarCore
			    var contacts: ContactCore
			    func scheduleMeeting(_ event: EventID, on day: DayKey, invitees: [ContactID], at timestamp: Timestamp) throws {
			        let tx_calendar = try Transaction(env: self.calendar.env, readOnly: false)
			        let tx_contacts = try Transaction(env: self.contacts.env, readOnly: false)
			        func __mdb_body(_ event: EventID, on day: DayKey, invitees: [ContactID], at timestamp: Timestamp, _ tx_calendar: borrowing Transaction, _ tx_contacts: borrowing Transaction) throws {
			            try calendar.events.store(key: day, value: event, tx: tx_calendar)
			            try calendar.invitees.store(key: event, value: invitees[0], tx: tx_calendar)
			            try contacts.lastSync.store(key: invitees[0], value: timestamp, tx: tx_contacts)
			        }
			        do {
			            try __mdb_body(event, on: day, invitees: invitees, at: timestamp, tx_calendar, tx_contacts)
			        } catch let error {
			            tx_calendar.abort()
			            tx_contacts.abort()
			            throw error
			        }
			        try tx_calendar.commit()
			        try tx_contacts.commit()
			    }

			    public static let mdb_environment_property_names: [String] = ["calendar", "contacts"]

			    /// opens every environment core in its own subdirectory (named after the
			    /// stored property) beneath `basePath`, creating directories as needed, and
			    /// assembles the container. maps are sized as current file + `mapHeadroom`.
			    @available(*, noasync)
			    public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)
			        let calendarDir = QuickLMDB._MDBEnvironmentSupport.__joinPath(basePath, "calendar")
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: calendarDir)
			        let calendar = try CalendarCore.open(at: calendarDir, mapHeadroom: mapHeadroom)
			        let contactsDir = QuickLMDB._MDBEnvironmentSupport.__joinPath(basePath, "contacts")
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: contactsDir)
			        let contacts = try ContactCore.open(at: contactsDir, mapHeadroom: mapHeadroom)
			        return Self(calendar: calendar, contacts: contacts)
			    }
			}

			extension HybridApp: MDB_environment_container {
			}
			"""
		)
	}

	@Test func allReadMembersCloseWithoutCommit() {
		// all-read span: both members open readOnly and close without commit
		assertSpanExpansion(
			"""
			@MDB_app
			struct HybridApp {
			    var calendar: CalendarCore
			    var contacts: ContactCore
			    @MDB_transact_span
			    func overview(_ day: DayKey, _ contact: ContactID) throws -> (EventID?, Timestamp?) {
			        let event = #load(calendar.events, key: day)
			        let synced = #load(contacts.lastSync, key: contact)
			        return (event, synced)
			    }
			}
			""",
			expected: """

			struct HybridApp {
			    var calendar: CalendarCore
			    var contacts: ContactCore
			    func overview(_ day: DayKey, _ contact: ContactID) throws -> (EventID?, Timestamp?) {
			        let tx_calendar = try Transaction(env: self.calendar.env, readOnly: true)
			        let tx_contacts = try Transaction(env: self.contacts.env, readOnly: true)
			        func __mdb_body(_ day: DayKey, _ contact: ContactID, _ tx_calendar: borrowing Transaction, _ tx_contacts: borrowing Transaction) throws -> (EventID?, Timestamp?) {
			            let event = calendar.events.load(key: day, tx: tx_calendar)
			            let synced = contacts.lastSync.load(key: contact, tx: tx_contacts)
			            return (event, synced)
			        }
			        let __mdb_output: (EventID?, Timestamp?)
			        do {
			            __mdb_output = try __mdb_body(day, contact, tx_calendar, tx_contacts)
			        } catch let error {
			            tx_calendar.abort()
			            tx_contacts.abort()
			            throw error
			        }
			        tx_calendar.abort()
			        tx_contacts.abort()
			        return __mdb_output
			    }

			    public static let mdb_environment_property_names: [String] = ["calendar", "contacts"]

			    /// opens every environment core in its own subdirectory (named after the
			    /// stored property) beneath `basePath`, creating directories as needed, and
			    /// assembles the container. maps are sized as current file + `mapHeadroom`.
			    @available(*, noasync)
			    public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)
			        let calendarDir = QuickLMDB._MDBEnvironmentSupport.__joinPath(basePath, "calendar")
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: calendarDir)
			        let calendar = try CalendarCore.open(at: calendarDir, mapHeadroom: mapHeadroom)
			        let contactsDir = QuickLMDB._MDBEnvironmentSupport.__joinPath(basePath, "contacts")
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: contactsDir)
			        let contacts = try ContactCore.open(at: contactsDir, mapHeadroom: mapHeadroom)
			        return Self(calendar: calendar, contacts: contacts)
			    }
			}

			extension HybridApp: MDB_environment_container {
			}
			"""
		)
	}

	@Test func overrideForcesModesAndOrder() {
		// explicit override forces modes and order
		assertSpanExpansion(
			"""
			@MDB_app
			struct HybridApp {
			    var calendar: CalendarCore
			    var contacts: ContactCore
			    @MDB_transact_span([.readOnly("calendar"), .readWrite("contacts")])
			    func pinned(_ day: DayKey) throws {
			        _ = #load(calendar.events, key: day)
			        try #store(contacts.lastSync, key: ContactID(), value: Timestamp())
			    }
			}
			""",
			expected: """

			struct HybridApp {
			    var calendar: CalendarCore
			    var contacts: ContactCore
			    func pinned(_ day: DayKey) throws {
			        let tx_calendar = try Transaction(env: self.calendar.env, readOnly: true)
			        let tx_contacts = try Transaction(env: self.contacts.env, readOnly: false)
			        func __mdb_body(_ day: DayKey, _ tx_calendar: borrowing Transaction, _ tx_contacts: borrowing Transaction) throws {
			            _ = calendar.events.load(key: day, tx: tx_calendar)
			            try contacts.lastSync.store(key: ContactID(), value: Timestamp(), tx: tx_contacts)
			        }
			        do {
			            try __mdb_body(day, tx_calendar, tx_contacts)
			        } catch let error {
			            tx_calendar.abort()
			            tx_contacts.abort()
			            throw error
			        }
			        tx_calendar.abort()
			        try tx_contacts.commit()
			    }

			    public static let mdb_environment_property_names: [String] = ["calendar", "contacts"]

			    /// opens every environment core in its own subdirectory (named after the
			    /// stored property) beneath `basePath`, creating directories as needed, and
			    /// assembles the container. maps are sized as current file + `mapHeadroom`.
			    @available(*, noasync)
			    public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)
			        let calendarDir = QuickLMDB._MDBEnvironmentSupport.__joinPath(basePath, "calendar")
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: calendarDir)
			        let calendar = try CalendarCore.open(at: calendarDir, mapHeadroom: mapHeadroom)
			        let contactsDir = QuickLMDB._MDBEnvironmentSupport.__joinPath(basePath, "contacts")
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: contactsDir)
			        let contacts = try ContactCore.open(at: contactsDir, mapHeadroom: mapHeadroom)
			        return Self(calendar: calendar, contacts: contacts)
			    }
			}

			extension HybridApp: MDB_environment_container {
			}
			"""
		)
	}

	@Test func childBoundaryCallAndNonVerbCallsPassThrough() {
		// a .readWriteChild boundary call (routed parent) and a non-verb helper call pass through byte-identical
		assertSpanExpansion(
			"""
			@MDB_app
			struct HybridApp {
			    var calendar: CalendarCore
			    @MDB_transact_span
			    func withChild(_ event: EventID, on day: DayKey) throws {
			        try #store(calendar.events, key: day, value: event)
			        try addInvitee(event, ContactID(), parent: tx_calendar)
			        let n = unmanagedHelper()
			        _ = n
			    }
			}
			""",
			expected: """

			struct HybridApp {
			    var calendar: CalendarCore
			    func withChild(_ event: EventID, on day: DayKey) throws {
			        let tx_calendar = try Transaction(env: self.calendar.env, readOnly: false)
			        func __mdb_body(_ event: EventID, on day: DayKey, _ tx_calendar: borrowing Transaction) throws {
			            try calendar.events.store(key: day, value: event, tx: tx_calendar)
			            try addInvitee(event, ContactID(), parent: tx_calendar)
			            let n = unmanagedHelper()
			            _ = n
			        }
			        do {
			            try __mdb_body(event, on: day, tx_calendar)
			        } catch let error {
			            tx_calendar.abort()
			            throw error
			        }
			        try tx_calendar.commit()
			    }

			    public static let mdb_environment_property_names: [String] = ["calendar"]

			    /// opens every environment core in its own subdirectory (named after the
			    /// stored property) beneath `basePath`, creating directories as needed, and
			    /// assembles the container. maps are sized as current file + `mapHeadroom`.
			    @available(*, noasync)
			    public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)
			        let calendarDir = QuickLMDB._MDBEnvironmentSupport.__joinPath(basePath, "calendar")
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: calendarDir)
			        let calendar = try CalendarCore.open(at: calendarDir, mapHeadroom: mapHeadroom)
			        return Self(calendar: calendar)
			    }
			}

			extension HybridApp: MDB_environment_container {
			}
			"""
		)
	}

	@Test func statsDoesNotForceWriteModeOnFetchOnlyCore() {
		// #stats is a metadata READ: a core touched only by #stats + #load stays readOnly
		assertSpanExpansion(
			"""
			@MDB_app
			struct HybridApp {
			    var calendar: CalendarCore
			    var contacts: ContactCore
			    @MDB_transact_span
			    func report(_ day: DayKey) throws -> Int {
			        _ = #load(calendar.events, key: day)
			        _ = #stats(calendar.events)
			        try #store(contacts.lastSync, key: ContactID(), value: Timestamp())
			        return 0
			    }
			}
			""",
			expected: """

			struct HybridApp {
			    var calendar: CalendarCore
			    var contacts: ContactCore
			    func report(_ day: DayKey) throws -> Int {
			        let tx_calendar = try Transaction(env: self.calendar.env, readOnly: true)
			        let tx_contacts = try Transaction(env: self.contacts.env, readOnly: false)
			        func __mdb_body(_ day: DayKey, _ tx_calendar: borrowing Transaction, _ tx_contacts: borrowing Transaction) throws -> Int {
			            _ = calendar.events.load(key: day, tx: tx_calendar)
			            _ = calendar.events.dbStatistics(tx: tx_calendar)
			            try contacts.lastSync.store(key: ContactID(), value: Timestamp(), tx: tx_contacts)
			            return 0
			        }
			        let __mdb_output: Int
			        do {
			            __mdb_output = try __mdb_body(day, tx_calendar, tx_contacts)
			        } catch let error {
			            tx_calendar.abort()
			            tx_contacts.abort()
			            throw error
			        }
			        tx_calendar.abort()
			        try tx_contacts.commit()
			        return __mdb_output
			    }

			    public static let mdb_environment_property_names: [String] = ["calendar", "contacts"]

			    /// opens every environment core in its own subdirectory (named after the
			    /// stored property) beneath `basePath`, creating directories as needed, and
			    /// assembles the container. maps are sized as current file + `mapHeadroom`.
			    @available(*, noasync)
			    public static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)
			        let calendarDir = QuickLMDB._MDBEnvironmentSupport.__joinPath(basePath, "calendar")
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: calendarDir)
			        let calendar = try CalendarCore.open(at: calendarDir, mapHeadroom: mapHeadroom)
			        let contactsDir = QuickLMDB._MDBEnvironmentSupport.__joinPath(basePath, "contacts")
			        _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: contactsDir)
			        let contacts = try ContactCore.open(at: contactsDir, mapHeadroom: mapHeadroom)
			        return Self(calendar: calendar, contacts: contacts)
			    }
			}

			extension HybridApp: MDB_environment_container {
			}
			"""
		)
	}

	@Test func missingMDBAppIsDiagnosed() {
		// the same body WITHOUT @MDB_app on the container — the span gate fires and the
		// body is left untouched (verb calls stay unlowered)
		assertSpanExpansion(
			"""
			struct NotAContainer {
			    var calendar: CalendarCore
			    @MDB_transact_span
			    func f() throws {
			        try #store(calendar.events, key: 1, value: 2)
			    }
			}
			""",
			expected: """
			struct NotAContainer {
			    var calendar: CalendarCore
			    func f() throws {
			        try #store(calendar.events, key: 1, value: 2)
			    }
			}
			""",
			diagnostics: ["@MDB_transact_span requires the containing type to be annotated @MDB_app (the container's stored properties are the environment inventory)"]
		)
	}
}
