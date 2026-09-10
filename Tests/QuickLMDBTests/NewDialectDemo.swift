import Testing
import Foundation
import QuickLMDB
import RAW

// - MARK: domain types (fixed-width RAW, big-endian per house convention)
// (previously defined in the legacy HybridAppDemo, removed in the phase-2 shed)

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

// the new dialect, demonstrated end to end on the real engine — a club app
// with a calendar core and a contacts core, exercising the full PROVISIONAL
// surface:
//
//   @MDB_transact(.readOnly | .readWrite, environments: <cores>)
//       attached body + peer: the method becomes a SHELL that opens tx_<E>
//       per listed environment, calls the WRAPPED SIBLING, and closes each
//       (readOnly aborts; readWrite commits on success).
//   #MDB_entry_load / #MDB_entry_store       trailing verbs, lowered inside a boundary.
//   #MDB_transacted(call)  Design-B join marker — the boundary rewrites it
//                          into the callee's wrapped sibling, threading THIS
//                          boundary's transaction (one transaction across the
//                          composed call; atomic for writes).
//
// besides the verbs, a boundary body may call the raw QuickLMDB surface with
// the injected `tx_<E>` name directly (cursors, dup iteration, zero-copy) —
// only the marker-gated verbs and joins are rewritten; everything else passes
// through byte-identical.

private enum ClubPaths {
	static let root = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-club-v2", isDirectory: true)
}

@MDB_environment(file: "calendar.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct ClubCalendarCore: Sendable {
	public let env: Environment
	public let events: Database.Strict<DayKey, EventID>
	public let invitees: Database.DupSort<EventID, ContactID>
}

@MDB_environment(file: "contacts.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct ClubContactsCore: Sendable {
	public let env: Environment
	public let lastSync: Database.Strict<ContactID, Timestamp>
}

/// the demo container: boundary methods live here, transacting over zero, one,
/// or both static cores. the cores are STATIC because the boundary's
/// `environments:` attribute arguments are evaluated at type scope — instance
/// stored properties are not in scope there.
enum ClubApp {

	// both cores must outlive any first access; the flag runs exactly once
	private static let prepared: Void = {
		try? FileManager.default.removeItem(at: ClubPaths.root)
		return ()
	}()

	static let calendar: ClubCalendarCore = {
		_ = ClubApp.prepared
		return try! ClubCalendarCore.open(at: ClubPaths.root.appendingPathComponent("calendar").path)
	}()

	static let contacts: ClubContactsCore = {
		_ = ClubApp.prepared
		return try! ClubContactsCore.open(at: ClubPaths.root.appendingPathComponent("contacts").path)
	}()

	// - MARK: reads

	// a single-env READ boundary: opens one read txn on calendar
	@MDB_transact(.readOnly, environments: calendar)
	static func eventOn(_ day: DayKey) throws -> EventID? {
		#MDB_entry_load(environment: calendar, database: calendar.events, key: day)
	}

	// multi-env READ boundary: one read txn per core, both joined behind the
	// one method
	@MDB_transact(.readOnly, environments: calendar, contacts)
	static func contactOverview(_ day: DayKey, _ contact: ContactID) throws -> (EventID?, Timestamp?) {
		let event = #MDB_entry_load(environment: calendar, database: calendar.events, key: day)
		let synced = #MDB_entry_load(environment: contacts, database: contacts.lastSync, key: contact)
		return (event, synced)
	}

	// READ composition: joined reads run on THIS boundary's transaction (the
	// single snapshot the boundary opened)
	@MDB_transact(.readOnly, environments: calendar)
	static func dayReadTwice(_ day: DayKey) throws -> (EventID?, EventID?) {
		let a = try #MDB_transacted(eventOn(day))
		let b = try #MDB_transacted(eventOn(day))
		return (a, b)
	}

	// READ with a cursor: the raw surface (with the injected tx_<E> name)
	// is available inside a boundary — only verbs and joins are rewritten
	@MDB_transact(.readOnly, environments: calendar)
	static func inviteesFor(_ event: EventID) throws -> [ContactID] {
		var result: [ContactID] = []
		if try calendar.invitees.contains(key: event, tx: tx_calendar) {
			calendar.invitees.cursor(tx: tx_calendar) { cursor in
				for (_, dup) in cursor.makeDupIterator(key: event) {
					result.append(dup)
				}
			}
		}
		return result
	}

	// - MARK: writes

	// a single-env WRITE boundary: one write txn, committed exactly once
	@MDB_transact(.readWrite, environments: calendar)
	static func book(_ event: EventID, on day: DayKey) throws {
		try #MDB_entry_store(environment: calendar, database: calendar.events, key: day, value: event)
	}

	// reusable write logic as its own boundary — composed by JOINING: each
	// #MDB_transacted(addInvitee(...)) runs on THIS boundary's write txn, so
	// the event row AND every invitee row land in ONE transaction (atomic by
	// construction)
	@MDB_transact(.readWrite, environments: calendar)
	static func bookWithInvitees(_ event: EventID, on day: DayKey, invitees: [ContactID]) throws {
		try #MDB_entry_store(environment: calendar, database: calendar.events, key: day, value: event)
		for invitee in invitees {
			try #MDB_transacted(addInvitee(event, invitee))
		}
	}

	@MDB_transact(.readWrite, environments: calendar)
	static func addInvitee(_ event: EventID, _ contact: ContactID) throws {
		try #MDB_entry_store(environment: calendar, database: calendar.invitees, key: event, value: contact)
	}

	// joined read INSIDE a write boundary sees THIS boundary's own uncommitted
	// state (the same transaction) — the new dialect's "child view" semantic,
	// atomic by construction
	@MDB_transact(.readWrite, environments: calendar)
	static func bookAndSelfCheck(_ event: EventID, on day: DayKey) throws -> EventID? {
		try #MDB_entry_store(environment: calendar, database: calendar.events, key: day, value: event)
		return try #MDB_transacted(eventOn(day))
	}

	// sibling read INSIDE a write boundary: a PLAIN call to eventOn opens its
	// own read transaction — the last COMMITTED state, not this boundary's
	// uncommitted write. the "validate against durable data" pattern.
	@MDB_transact(.readWrite, environments: calendar)
	static func validateThenBook(_ event: EventID, on day: DayKey) throws -> Bool {
		guard try eventOn(day) == nil else { return false }   // sibling read: committed-only
		try #MDB_entry_store(environment: calendar, database: calendar.events, key: day, value: event)
		return true
	}

	// multi-env WRITE boundary: one write txn per core, committed back to back.
	// honest ceiling: cross-environment commits are best-effort — a body throw
	// aborts BOTH (nothing lands), but a crash between the two commit calls
	// could still split the pair (cross-env atomicity is impossible)
	@MDB_transact(.readWrite, environments: calendar, contacts)
	static func scheduleAndMarkSync(_ event: EventID, on day: DayKey, contact: ContactID, at timestamp: Timestamp) throws {
		try #MDB_entry_store(environment: calendar, database: calendar.events, key: day, value: event)
		try #MDB_entry_store(environment: contacts, database: contacts.lastSync, key: contact, value: timestamp)
	}

	@MDB_transact(.readWrite, environments: calendar, contacts)
	static func scheduleAndMarkSyncThrowing(_ event: EventID, on day: DayKey, contact: ContactID, at timestamp: Timestamp) throws {
		try #MDB_entry_store(environment: calendar, database: calendar.events, key: day, value: event)
		try #MDB_entry_store(environment: contacts, database: contacts.lastSync, key: contact, value: timestamp)
		throw ClubDemoError.syncFailed
	}
}

enum ClubDemoError: Error {
	case syncFailed
}

@Suite("new dialect demo — club app (the @MDB_transact surface)")
struct NewDialectDemo {

	/// committed setup through a raw write transaction
	private func seed(_ key: DayKey, _ value: EventID) throws {
		let tx = try Transaction(env: ClubApp.calendar.env, readOnly: false)
		try ClubApp.calendar.events.setEntry(key: key, value: value, flags: [], tx: tx)
		try tx.commit()
	}

	// - MARK: reads

	@Test func readBoundaryReadsCommittedState() throws {
		let day = DayKey(RAW_native: 1)
		try seed(day, EventID(RAW_native: 100))
		#expect(try ClubApp.eventOn(day) == EventID(RAW_native: 100))
	}

	@Test func joinedReadsInOneBoundarySeeOneSnapshot() throws {
		let day = DayKey(RAW_native: 2)
		try seed(day, EventID(RAW_native: 200))
		let (a, b) = try ClubApp.dayReadTwice(day)
		#expect(a == EventID(RAW_native: 200))
		#expect(b == EventID(RAW_native: 200))
	}

	// - MARK: writes

	@Test func writeBoundaryCommitsDurably() throws {
		let day = DayKey(RAW_native: 3)
		try ClubApp.book(EventID(RAW_native: 300), on: day)
		#expect(try ClubApp.calendar.events.readCommitted(key: day) == EventID(RAW_native: 300))
	}

	@Test func writeCompositionIsOneTransaction() throws {
		let day = DayKey(RAW_native: 4)
		let event = EventID(RAW_native: 400)
		let invitees = [ContactID(RAW_native: 1), ContactID(RAW_native: 2)]
		// event + every joined invitee write land ATOMICALLY in one txn
		try ClubApp.bookWithInvitees(event, on: day, invitees: invitees)
		#expect(try ClubApp.calendar.events.readCommitted(key: day) == event)
		#expect(try ClubApp.inviteesFor(event) == invitees)
	}

	@Test func joinedReadInsideWriteSeesUncommittedState() throws {
		let day = DayKey(RAW_native: 5)
		let event = EventID(RAW_native: 500)
		// bookAndSelfCheck writes then reads BACK THROUGH the same transaction
		// — the uncommitted value is visible to the joined read
		let selfCheck = try ClubApp.bookAndSelfCheck(event, on: day)
		#expect(selfCheck == event, "the joined read must see the boundary's own uncommitted write")
	}

	@Test func siblingReadInsideWriteSeesCommittedOnly() throws {
		let day = DayKey(RAW_native: 6)
		let event = EventID(RAW_native: 600)
		// eventOn(day) as a PLAIN call is a sibling read: it opens its own read
		// txn and sees only committed data — so the validate passes, the write
		// lands, and a second attempt refuses because the GATE sees committed
		let ok = try ClubApp.validateThenBook(event, on: day)
		#expect(ok)
		let again = try ClubApp.validateThenBook(EventID(RAW_native: 601), on: day)
		#expect(again == false, "the sibling read must see the durably booked day")
		#expect(try ClubApp.calendar.events.readCommitted(key: day) == event)
	}

	// - MARK: multi-environment

	@Test func multiEnvReadJoinsBothCores() throws {
		let day = DayKey(RAW_native: 7)
		let contact = ContactID(RAW_native: 10)
		let event = EventID(RAW_native: 700)
		let when = Timestamp(RAW_native: 7_000)
		try ClubApp.book(event, on: day)
		try ClubApp.scheduleAndMarkSync(event, on: day, contact: contact, at: when)

		let overview = try ClubApp.contactOverview(day, contact)
		#expect(overview.0 == event)
		#expect(overview.1 == when)
	}

	@Test func multiEnvWriteBothLandButThrowAbortsBoth() throws {
		let day = DayKey(RAW_native: 8)
		let contact = ContactID(RAW_native: 11)
		let event = EventID(RAW_native: 800)
		let when = Timestamp(RAW_native: 8_000)

		// both envs land on success
		try ClubApp.scheduleAndMarkSync(event, on: day, contact: contact, at: when)
		#expect(try ClubApp.calendar.events.readCommitted(key: day) == event)
		#expect(try ClubApp.contacts.lastSync.readCommitted(key: contact) == when)

		// a throwing multi-env write aborts BOTH member transactions — nothing
		// lands in either env
		let day2 = DayKey(RAW_native: 9)
		let event2 = EventID(RAW_native: 900)
		#expect(throws: ClubDemoError.self) {
			try ClubApp.scheduleAndMarkSyncThrowing(event2, on: day2, contact: contact, at: when)
		}
		#expect(try ClubApp.calendar.events.readCommitted(key: day2) == nil, "calendar write must be rolled back with the failed contacts write")
		#expect(try ClubApp.contacts.lastSync.readCommitted(key: ContactID(RAW_native: 12)) == nil)
	}

	// - MARK: raw surface inside a boundary

	@Test func cursorInsideBoundaryUsesTheInjectedTransaction() throws {
		let event = EventID(RAW_native: 900)
		let invitees = [ContactID(RAW_native: 21), ContactID(RAW_native: 22), ContactID(RAW_native: 23)]
		try ClubApp.bookWithInvitees(event, on: DayKey(RAW_native: 10), invitees: invitees)
		#expect(try ClubApp.inviteesFor(event) == invitees)
	}
}
