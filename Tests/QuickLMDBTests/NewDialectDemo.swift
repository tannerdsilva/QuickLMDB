import Testing
import Foundation
import QuickLMDB
import RAW

// - MARK: domain types (fixed-width RAW, big-endian per house convention)

/// day index (UInt32 BE). calendar keys are time-first so disk order tracks the clock.
@RAW_staticbuff(bytes: 4)
@RAW_staticbuff_fixedwidthinteger_type<UInt32>(bigEndian: true)
@MDB_comparable
@frozen public struct DayKey: Sendable, Hashable, Equatable, Comparable {}

/// an event id (UInt32 BE).
@RAW_staticbuff(bytes: 4)
@RAW_staticbuff_fixedwidthinteger_type<UInt32>(bigEndian: true)
@MDB_comparable
@frozen public struct EventID: Sendable, Hashable, Equatable, Comparable {}

/// a contact id (UInt32 BE) — the cross-app linkage.
@RAW_staticbuff(bytes: 4)
@RAW_staticbuff_fixedwidthinteger_type<UInt32>(bigEndian: true)
@MDB_comparable
@frozen public struct ContactID: Sendable, Hashable, Equatable, Comparable {}

/// epoch time in SECONDS (UInt64 BE).
@RAW_staticbuff(bytes: 8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian: true)
@MDB_comparable
@frozen public struct Timestamp: Sendable, Hashable, Equatable, Comparable {}

// the new dialect — the typed-environment architecture:
//
//   every environment is its own TYPE. @MDB_environment cores carry their
//   `Database.X` handles, and transaction boundaries live ON those types as
//   plain instance methods. NOTHING about transactions is visible: no tx
//   parameters, no `environments:` list, no entry suffixes, no `_mdb_*` —
//   just @MDB_transact(_ mode:) on the method and the typed verb family in
//   the body. calling a boundary opens + commits/aborts its own transactions;
//   composing inside a boundary is spelled `#MDB_transacted(callee(args))`.

@MDB_environment(file: "calendar.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct CalendarCore: Sendable {
	public let env: Environment
	public let events: Database.Strict<DayKey, EventID>
	public let invitees: Database.DupSort<EventID, ContactID>

	// - MARK: reads

	@MDB_transact(.readOnly)
	public func eventOn(_ day: DayKey) throws -> EventID? {
		#load(CalendarCore.self, database: \.events, key: day)
	}

	@MDB_transact(.readOnly)
	public func inviteesFor(_ event: EventID) throws -> [ContactID] {
		var result: [ContactID] = []
		#cursor(CalendarCore.self, database: \.invitees) { cursor in
			for (_, dup) in cursor.makeDupIterator(key: event) {
				result.append(dup)
			}
		}
		return result
	}

	// - MARK: writes

	@MDB_transact(.readWrite)
	public func book(_ event: EventID, on day: DayKey) throws {
		try #store(CalendarCore.self, database: \.events, key: day, value: event)
	}

	// reusable write logic composed by JOINING: each #MDB_transacted(...) call
	// runs on THIS boundary's write transaction, so the event row AND every
	// invitee row land in ONE transaction (atomic by construction)
	@MDB_transact(.readWrite)
	public func bookWithInvitees(_ event: EventID, on day: DayKey, invitees: [ContactID]) throws {
		try #store(CalendarCore.self, database: \.events, key: day, value: event)
		for invitee in invitees {
			try #MDB_transacted(addInvitee(event, invitee))
		}
	}

	@MDB_transact(.readWrite)
	public func addInvitee(_ event: EventID, _ contact: ContactID) throws {
		try #store(CalendarCore.self, database: \.invitees, key: event, value: contact)
	}

	// a joined read INSIDE this write boundary sees THIS boundary's own
	// uncommitted state (the same transaction) — atomic by construction
	@MDB_transact(.readWrite)
	public func bookAndSelfCheck(_ event: EventID, on day: DayKey) throws -> EventID? {
		try #store(CalendarCore.self, database: \.events, key: day, value: event)
		return try #MDB_transacted(eventOn(day))
	}

	// a bare call to a READ boundary inside this write boundary is a SIBLING
	// read: eventOn's own shell opens a fresh root READ, seeing only the last
	// COMMITTED state — the "validate against durable data" pattern
	@MDB_transact(.readWrite)
	public func validateThenBook(_ event: EventID, on day: DayKey) throws -> Bool {
		guard try eventOn(day) == nil else { return false }
		try #store(CalendarCore.self, database: \.events, key: day, value: event)
		return true
	}

	// - MARK: multi-environment (the other core is a TYPED parameter)

	@MDB_transact(.readWrite)
	public func scheduleAndMarkSync(_ event: EventID, on day: DayKey, contact: ContactID, at timestamp: Timestamp, contacts: ContactsCore) throws {
		try #store(CalendarCore.self, database: \.events, key: day, value: event)
		try #store(ContactsCore.self, database: \.lastSync, key: contact, value: timestamp)
	}

	@MDB_transact(.readWrite)
	public func scheduleAndMarkSyncThrowing(_ event: EventID, on day: DayKey, contact: ContactID, at timestamp: Timestamp, contacts: ContactsCore) throws {
		try #store(CalendarCore.self, database: \.events, key: day, value: event)
		try #store(ContactsCore.self, database: \.lastSync, key: contact, value: timestamp)
		throw ClubDemoError.syncFailed
	}
}

@MDB_environment(file: "contacts.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct ContactsCore: Sendable {
	public let env: Environment
	public let lastSync: Database.Strict<ContactID, Timestamp>

	@MDB_transact(.readOnly)
	public func lastSync(_ contact: ContactID) throws -> Timestamp? {
		#load(ContactsCore.self, database: \.lastSync, key: contact)
	}
}

enum ClubDemoError: Error {
	case syncFailed
}

@Suite("new dialect demo — typed environments (the effortless surface)")
struct NewDialectDemo {

	/// a fresh per-test environment; the boundary methods ARE the seeding and
	/// the verification (each opens its own transaction)
	private func freshCore() throws -> CalendarCore {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-club-\(UUID().uuidString)", isDirectory: true)
		return try CalendarCore.open(at: dir.path)
	}

	// - MARK: reads

	@Test func readBoundaryReadsCommittedState() throws {
		let calendar = try freshCore()
		let day = DayKey(RAW_native: 1)
		try calendar.book(EventID(RAW_native: 100), on: day)
		#expect(try calendar.eventOn(day) == EventID(RAW_native: 100))
	}

	// - MARK: writes

	@Test func writeBoundaryCommitsDurably() throws {
		let calendar = try freshCore()
		let day = DayKey(RAW_native: 3)
		try calendar.book(EventID(RAW_native: 300), on: day)
		#expect(try calendar.eventOn(day) == EventID(RAW_native: 300))
	}

	@Test func writeCompositionIsOneTransaction() throws {
		let calendar = try freshCore()
		let day = DayKey(RAW_native: 4)
		let event = EventID(RAW_native: 400)
		let invitees = [ContactID(RAW_native: 1), ContactID(RAW_native: 2)]
		// event + every joined invitee write land ATOMICALLY in one txn
		try calendar.bookWithInvitees(event, on: day, invitees: invitees)
		#expect(try calendar.eventOn(day) == event)
		#expect(try calendar.inviteesFor(event) == invitees)
	}

	@Test func joinedReadInsideWriteSeesUncommittedState() throws {
		let calendar = try freshCore()
		let day = DayKey(RAW_native: 5)
		let event = EventID(RAW_native: 500)
		// bookAndSelfCheck writes then reads BACK THROUGH the same transaction
		// — the uncommitted value is visible to the joined read
		let selfCheck = try calendar.bookAndSelfCheck(event, on: day)
		#expect(selfCheck == event, "the joined read must see the boundary's own uncommitted write")
	}

	@Test func siblingReadInsideWriteSeesCommittedOnly() throws {
		let calendar = try freshCore()
		let day = DayKey(RAW_native: 6)
		let event = EventID(RAW_native: 600)
		// eventOn(day) bare is a root-scoped sibling read: its own read txn
		// sees only committed data — so the validate passes, the write lands,
		// and a second attempt refuses because the GATE sees committed
		#expect(try calendar.validateThenBook(event, on: day))
		let again = try calendar.validateThenBook(EventID(RAW_native: 601), on: day)
		#expect(!again)
		#expect(try calendar.eventOn(day) == event)
	}

	// - MARK: multi-environment

	@Test func multiEnvBoundarySpansBothCores() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-club-multi-\(UUID().uuidString)", isDirectory: true)
		let calendar = try CalendarCore.open(at: root.appendingPathComponent("calendar").path)
		let contacts = try ContactsCore.open(at: root.appendingPathComponent("contacts").path)
		let day = DayKey(RAW_native: 7)
		let event = EventID(RAW_native: 700)
		let when = Timestamp(RAW_native: 7_000)

		try calendar.scheduleAndMarkSync(event, on: day, contact: ContactID(RAW_native: 10), at: when, contacts: contacts)
		#expect(try calendar.eventOn(day) == event)
		#expect(try contacts.lastSync(ContactID(RAW_native: 10)) == when)
	}

	@Test func multiEnvThrowAbortsBothCores() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-club-multi-\(UUID().uuidString)", isDirectory: true)
		let calendar = try CalendarCore.open(at: root.appendingPathComponent("calendar").path)
		let contacts = try ContactsCore.open(at: root.appendingPathComponent("contacts").path)
		let day = DayKey(RAW_native: 8)
		let event = EventID(RAW_native: 800)

		#expect(throws: ClubDemoError.self) {
			try calendar.scheduleAndMarkSyncThrowing(event, on: day, contact: ContactID(RAW_native: 11), at: Timestamp(RAW_native: 8_000), contacts: contacts)
		}
		#expect(try calendar.eventOn(day) == nil, "the calendar write must be rolled back with the failed contacts write")
		#expect(try contacts.lastSync(ContactID(RAW_native: 11)) == nil)
	}
}
