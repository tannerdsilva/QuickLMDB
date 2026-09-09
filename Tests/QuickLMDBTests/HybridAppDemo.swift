import Testing
import Foundation
import QuickLMDB
import RAW

// a complete usage demo of a "calendar app" × "contact app" hybrid. every function
// lives in its own environment (CalendarCore / ContactCore), and the patterns below
// exercise the FULL matrix of transactional boundary relationships — single-env
// boundaries in each app, and a "spanning" operation that reads/writes BOTH
// environments behind one effortless-looking app method (two real transactions,
// one per environment, under the hood).
//
// the boundary relationship matrix demonstrated here (each = a real test):
//
//   single-env, CalendarCore / ContactCore:
//     readWrite top-level                  bookEvent, markSync
//     readOnly top-level                   eventOn, lastSyncFor, inviteesFor
//     readWriteChild(parent:)              addInvitee (merges into parent on commit)
//     readOnly inside readWrite            sibling read: bookIfSlotFree,
//     (sees last COMMITTED state)              bookAndSelfCheck
//     readWrite inside readOnly            sibling write: snapshotAndBump
//     (commits independently)
//     readOnly inside readOnly             sibling reads: daySnapshotTwice
//     (.noTLS makes this legal)
//     child abort leaves parent usable     bookWithAvailableInvitees
//     injected-tx helper composition       bookViaHelper
//
//   cross-env, HybridApp (the spanning layer):
//     spanning WRITE = one calendar txn   scheduleMeeting:
//       + one contacts txn,                one app method, two real transactions.
//       no transaction plumbing visible
//     spanning READ = sibling reads        dayOverview
//       across both environments
//     spanning is BEST-EFFORT, never       scheduleMeetingBestEffort: the calendar
//       atomic (two commit points —        write survives a contacts failure.
//       no cross-env commit exists)
//     manual raw two-txn contrast          scheduleMeetingManual — the ceremony the
//       (what the boundary layer saves)    boundary layer removes
//
// deliberately NOT demonstrated here (pinned elsewhere or impossible to test):
//   multi-level nesting top→child→grandchild            -> MacroRuntimeTests
//   write child under read parent (EINVAL)              -> MacroRuntimeTests + raw pins
//   nested .readWrite without parent: deadlocks on the  -> documented forbidden
//       writer mutex WITHIN one env. cross-env nested   pattern (would hang CI)
//       .readWrite is the sibling relationship above

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

/// a contact id (UInt32 BE) — the cross-app linkage: invitees on the calendar
/// reference contact ids owned by the contacts app.
@RAW_staticbuff(bytes: 4)
@RAW_staticbuff_fixedwidthinteger_type<UInt32>(bigEndian: true)
@MDB_comparable
@frozen public struct ContactID: Sendable, Hashable, Equatable, Comparable {}

/// epoch time in SECONDS (UInt64 BE).
@RAW_staticbuff(bytes: 8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian: true)
@MDB_comparable
@frozen public struct Timestamp: Sendable, Hashable, Equatable, Comparable {}

/// domain errors for the two apps.
public enum CalendarError: Error {
	case blockedContact
}

public enum ContactError: Error {
	case syncFailed
}

// - MARK: calendar app (its own environment)

@MDB_environment(file: "calendar.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct CalendarCore: Sendable {
	public let env: Environment
	public let events: Database.Strict<DayKey, EventID>
	public let invitees: Database.DupSort<EventID, ContactID>
}

extension CalendarCore {

	// 1. readWrite top-level: one atomic write. commits once on success, aborts once on throw.
	@MDB_transact(.readWrite)
	public func bookEvent(_ event: consuming EventID, on day: consuming DayKey) throws {
		try #store(events, key: day, value: event)
	}

	// 2. readOnly top-level: never commits.
	@MDB_transact(.readOnly)
	public func eventOn(_ day: borrowing DayKey) throws -> EventID? {
		return #load(events, key: day)
	}

	// 3. child boundary: merges into the calling boundary's write on commit.
	@MDB_transact(.readWriteChild)
	public func addInvitee(_ event: borrowing EventID, _ contact: consuming ContactID, parent: borrowing Transaction) throws {
		try #store(invitees, key: event, value: contact)
	}

	// 4. one boundary = one atomic unit across BOTH tables, via sequential children.
	//    the parent write + each child merge all land (or none do). this is the
	//    "multi-table atomic write" idiom inside a single environment. event is
	//    consumed into the parent write; an explicit copy carries the borrows into
	//    the child loop (setEntry's value is consuming on every call).
	@MDB_transact(.readWrite)
	public func bookWithInvitees(_ event: consuming EventID, on day: consuming DayKey, invitees: [ContactID]) throws {
		let eventCopy = event
		try #store(events, key: day, value: eventCopy)
		for invitee in invitees {
			try addInvitee(event, invitee, parent: tx)
		}
	}

	// 5. sibling READ inside a WRITE: the inner read is an independent top-level read
	//    transaction on the SAME environment, seeing the last COMMITTED state — not
	//    this boundary's uncommitted write. the idiom: "validate against durable
	//    data before committing".
	@MDB_transact(.readOnly)
	public func committedEvent(on day: DayKey) throws -> EventID? {
		return #load(events, key: day)
	}

	@MDB_transact(.readWrite)
	public func bookIfSlotFree(_ event: consuming EventID, on day: borrowing DayKey) throws -> Bool {
		guard try committedEvent(on: day) == nil else { return false }
		try #store(events, key: day, value: event)
		return true
	}

	// 6. the reverse visibility check: a sibling read AFTER this boundary's own write
	//    must STILL see the committed (pre-write) state — the write is invisible to
	//    siblings until the boundary commits.
	@MDB_transact(.readWrite)
	public func bookAndSelfCheck(_ event: consuming EventID, on day: borrowing DayKey) throws -> EventID? {
		try #store(events, key: day, value: event)
		return try committedEvent(on: day)
	}

	// 7. sibling READ inside a READ: two top-level reads on one thread are legal
	//    because @MDB_environment forces .noTLS (each transaction owns its reader slot).
	@MDB_transact(.readOnly)
	public func daySnapshotTwice(_ day: DayKey) throws -> (EventID?, EventID?) {
		let a = try eventOn(day)
		let b = try eventOn(day)
		return (a, b)
	}

	// 8. child ABORT leaves the parent usable: a child that throws rolls back only
	//    its own writes; the parent catches, continues, and commits its own.
	@MDB_transact(.readWriteChild)
	public func addInviteeGuarded(_ event: borrowing EventID, _ contact: consuming ContactID, parent: borrowing Transaction) throws {
		guard contact != ContactID(RAW_native: 0) else { throw CalendarError.blockedContact }
		try #store(invitees, key: event, value: contact)
	}

	@MDB_transact(.readWrite)
	public func bookWithAvailableInvitees(_ event: consuming EventID, on day: consuming DayKey, invitees: [ContactID]) throws -> [ContactID] {
		let eventCopy = event
		try #store(events, key: day, value: eventCopy)
		var accepted: [ContactID] = []
		for invitee in invitees {
			do {
				try addInviteeGuarded(event, invitee, parent: tx)
				accepted.append(invitee)
			} catch CalendarError.blockedContact {
				// child aborted independently; this boundary's write continues
			}
		}
		return accepted
	}

	// 9. injected-tx helper composition: the boundary's `tx` handed to a plain helper
	//    whose operation call carries `tx:` explicitly. the helper's value param must
	//    be `consuming` because setEntry consumes its value.
	@MDB_transact(.readWrite)
	public func bookViaHelper(_ event: consuming EventID, on day: borrowing DayKey) throws {
		try writeEventHelper(event, day, tx: tx)
	}

	public func writeEventHelper(_ event: consuming EventID, _ day: borrowing DayKey, tx: borrowing Transaction) throws {
		try events.setEntry(key: day, value: event, flags: [], tx: tx)
	}

	// 10. dup-sort read: all invitees of an event, in a readOnly boundary.
	@MDB_transact(.readOnly)
	public func inviteesFor(_ event: EventID) throws -> [ContactID] {
		guard try #contains(invitees, key: event) else { return [] }
		var result: [ContactID] = []
		#cursor(invitees) { cursor in
			for (_, dup) in cursor.makeDupIterator(key: event) {
				result.append(dup)
			}
		}
		return result
	}
}

// - MARK: contact app (its own environment)

@MDB_environment(file: "contacts.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct ContactCore: Sendable {
	public let env: Environment
	public let lastSync: Database.Strict<ContactID, Timestamp>
}

extension ContactCore {

	// 11. readWrite top-level.
	@MDB_transact(.readWrite)
	public func markSync(_ ids: [ContactID], at timestamp: Timestamp) throws {
		for id in ids {
			try #store(lastSync, key: id, value: timestamp)
		}
	}

	// 12. readOnly top-level.
	@MDB_transact(.readOnly)
	public func lastSyncFor(_ id: ContactID) throws -> Timestamp? {
		return #load(lastSync, key: id)
	}

	// 13. sibling WRITE inside a READ: the inner write commits independently and the
	//     outer read's snapshot is unaffected (it keeps seeing the pre-write state).
	@MDB_transact(.readOnly)
	public func snapshotAndBump(_ id: ContactID, at timestamp: Timestamp) throws -> Timestamp? {
		let before = try lastSyncFor(id)
		try markSync([id], at: timestamp)
		return before
	}

	// 14. a write that fails AFTER writing: its transaction aborts, so nothing lands.
	//     used to demonstrate that a spanning operation is best-effort (see below).
	@MDB_transact(.readWrite)
	public func markSyncThrowing(_ ids: [ContactID], at timestamp: Timestamp) throws {
		for id in ids {
			try #store(lastSync, key: id, value: timestamp)
		}
		throw ContactError.syncFailed
	}
}

// - MARK: hybrid app — the spanning layer

/// owns both apps; the spanning methods below read/write BOTH environments behind
/// a single app-level call. no transaction plumbing appears in their signatures.
/// `@MDB_app` marks this struct as an environment container (its stored cores are
/// the routing inventory), and `@MDB_transact_span` boundaries coordinate a
/// calendar transaction and a contacts transaction behind one app method.
@MDB_app
public struct HybridApp {
	public let calendar: CalendarCore
	public let contacts: ContactCore

	public static func open(calendarAt: String, contactsAt: String) throws -> HybridApp {
		return HybridApp(calendar: try CalendarCore.open(at: calendarAt), contacts: try ContactCore.open(at: contactsAt))
	}

	// 15. spanning WRITE: one app method, two real transactions behind the seams —
	//     a calendar write and a contacts write, opened up front and committed
	//     back-to-back. the syntax looks exactly like any other operation; the two
	//     boundaries are the implementation.
	@MDB_transact_span
	public func scheduleMeeting(_ event: EventID, on day: DayKey, invitees: [ContactID], at timestamp: Timestamp) throws {
		try #store(calendar.events, key: day, value: event)
		for invitee in invitees {
			try #store(calendar.invitees, key: event, value: invitee)
			try #store(contacts.lastSync, key: invitee, value: timestamp)
		}
	}

	// 16. spanning READ: an all-read span — two read members, no commits. the sync
	//     timestamp of a contact plus a calendar lookup in one app call.
	@MDB_transact_span
	public func dayOverview(on day: DayKey, contact: ContactID) throws -> (event: EventID?, lastSync: Timestamp?) {
		let event = #load(calendar.events, key: day)
		let synced = #load(contacts.lastSync, key: contact)
		return (event, synced)
	}

	// 17b. explicit-override span: same logical op, but the member list is forced —
	//      calendar pinned readWrite, contacts pinned readWrite (override form).
	//      reaches identical durable state to the bare-inferred version (15).
	@MDB_transact_span([.readWrite("calendar"), .readWrite("contacts")])
	public func scheduleMeetingPinned(_ event: EventID, on day: DayKey, invitees: [ContactID], at timestamp: Timestamp) throws {
		try #store(calendar.events, key: day, value: event)
		for invitee in invitees {
			try #store(calendar.invitees, key: event, value: invitee)
			try #store(contacts.lastSync, key: invitee, value: timestamp)
		}
	}

	// 17. spanning failure is BEST-EFFORT but all-abort: the span opens BOTH member
	//     transactions up front, so a throw in the contacts write aborts BOTH — the
	//     calendar write is rolled back with it. the residual, unavoidable window is
	//     only the two adjacent commit calls at the very end (crash between them can
	//     still split the pair — cross-environment atomicity is impossible).
	@MDB_transact_span
	public func scheduleMeetingAllOrNothing(_ event: EventID, on day: DayKey, invitees: [ContactID], at timestamp: Timestamp) throws {
		try #store(calendar.events, key: day, value: event)
		for invitee in invitees {
			try #store(calendar.invitees, key: event, value: invitee)
			try #store(contacts.lastSync, key: invitee, value: timestamp)
		}
		throw ContactError.syncFailed
	}

	// 18. manual, non-span variants used as the OLD two-step contrast: the two
	//     boundaries are isolated, so a contacts failure leaves the calendar write
	//     durable (the pre-span behavior the span removes). kept to prove the
	//     upgrade and to assert the manual raw ceremony reaches the same state.
	public func scheduleMeetingBestEffort(_ event: EventID, on day: DayKey, invitees: [ContactID], at timestamp: Timestamp) throws {
		try calendar.bookWithInvitees(event, on: day, invitees: invitees)
		try contacts.markSyncThrowing(invitees, at: timestamp)
	}

	// the manual raw version of scheduleMeeting — the ceremony the boundary layer
	// removes: two explicit transactions, N explicit children, three commits,
	// two abort paths, and a mid-loop nested do/catch for every child. the
	// commit-after-catch shape is identical to what the body macro expands.
	public func scheduleMeetingManual(_ event: EventID, on day: DayKey, invitees: [ContactID], at timestamp: Timestamp) throws {
		let calTX = try Transaction(env: calendar.env, readOnly: false)
		do {
			try calendar.events.setEntry(key: day, value: event, flags: [], tx: calTX)
			for invitee in invitees {
				// explicit child, committed into calTX like the `.readWriteChild` expansion
				let child = try Transaction(env: calendar.env, readOnly: false, parent: calTX)
				do {
					try calendar.invitees.setEntry(key: event, value: invitee, flags: [], tx: child)
				} catch let error {
					child.abort()
					throw error
				}
				try child.commit()
			}
		} catch let error {
			calTX.abort()
			throw error
		}
		try calTX.commit()

		let conTX = try Transaction(env: contacts.env, readOnly: false)
		do {
			for invitee in invitees {
				try contacts.lastSync.setEntry(key: invitee, value: timestamp, flags: [], tx: conTX)
			}
		} catch let error {
			conTX.abort()
			throw error
		}
		try conTX.commit()
	}
}

// - MARK: harness — every boundary cell from the matrix above is asserted here

@Suite("Hybrid calendar × contacts app (cross-environment boundaries)")
struct HybridAppDemo {

	private func makeApp() throws -> HybridApp {
		let base = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-hybrid-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		let cal = base.appendingPathComponent("cal", isDirectory: true)
		let con = base.appendingPathComponent("con", isDirectory: true)
		try FileManager.default.createDirectory(at: cal, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: con, withIntermediateDirectories: true)
		return try HybridApp.open(calendarAt: cal.path, contactsAt: con.path)
	}

	// raw read helpers — an explicit transaction plus the tx-bearing read API, used to
	// verify what actually became durable after a boundary (or spanning call).
	private func readEventViaRaw(_ app: HybridApp, day: DayKey) throws -> EventID? {
		let tx = try Transaction(env: app.calendar.env, readOnly: true)
		let result = try? app.calendar.events.loadEntry(key: day, as: EventID.self, tx: tx)
		tx.abort()
		return result
	}

	private func readInviteesViaRaw(_ app: HybridApp, event: EventID) throws -> [ContactID] {
		let tx = try Transaction(env: app.calendar.env, readOnly: true)
		var result: [ContactID] = []
		if (try? app.calendar.invitees.containsEntry(key: event, tx: tx)) == true {
			app.calendar.invitees.cursor(tx: tx) { cursor in
				for (_, dup) in cursor.makeDupIterator(key: event) {
					result.append(dup)
				}
			}
		}
		tx.abort()
		return result
	}

	private func readLastSyncViaRaw(_ app: HybridApp, contact: ContactID) throws -> Timestamp? {
		let tx = try Transaction(env: app.contacts.env, readOnly: true)
		let result = try? app.contacts.lastSync.loadEntry(key: contact, as: Timestamp.self, tx: tx)
		tx.abort()
		return result
	}

	// - MARK: single-environment cells

	@Test func calendarReadWriteCommitsDurably() throws {
		let app = try makeApp()
		let day = DayKey(RAW_native: 1)
		let event = EventID(RAW_native: 100)
		try app.calendar.bookEvent(event, on: day)
		#expect(try readEventViaRaw(app, day: day) == event)
		#expect(try app.calendar.eventOn(day) == event)
	}

	@Test func calendarChildBoundaryComposesAtomicallyAcrossTables() throws {
		let app = try makeApp()
		let day = DayKey(RAW_native: 2)
		let event = EventID(RAW_native: 200)
		let invitees = [ContactID(RAW_native: 1), ContactID(RAW_native: 2), ContactID(RAW_native: 3)]
		// one boundary, parent write + three child merges — all land together
		try app.calendar.bookWithInvitees(event, on: day, invitees: invitees)
		#expect(try readEventViaRaw(app, day: day) == event)
		#expect(try readInviteesViaRaw(app, event: event) == invitees)
	}

	@Test func siblingReadInsideWriteValidatesCommittedState() throws {
		let app = try makeApp()
		let day = DayKey(RAW_native: 3)
		let existing = EventID(RAW_native: 300)
		try app.calendar.bookEvent(existing, on: day)

		// slot taken: the sibling read sees the COMMITTED event and refuses the booking
		let rejected = EventID(RAW_native: 301)
		let booked = try app.calendar.bookIfSlotFree(rejected, on: day)
		#expect(booked == false)
		#expect(try readEventViaRaw(app, day: day) == existing, "the rejected booking must not have written")

		// free slot: books and commits
		let freeDay = DayKey(RAW_native: 4)
		let accepted = EventID(RAW_native: 302)
		#expect(try app.calendar.bookIfSlotFree(accepted, on: freeDay) == true)
		#expect(try readEventViaRaw(app, day: freeDay) == accepted)
	}

	@Test func siblingReadInsideWriteCannotSeeOwnUncommittedWrite() throws {
		let app = try makeApp()
		let day = DayKey(RAW_native: 5)
		let event = EventID(RAW_native: 500)
		// the sibling read runs AFTER this boundary's own write but must still return
		// the committed state (nil) — the write is invisible until the boundary commits.
		let selfCheck = try app.calendar.bookAndSelfCheck(event, on: day)
		#expect(selfCheck == nil, "a sibling read must not see this boundary's uncommitted write")
		#expect(try readEventViaRaw(app, day: day) == event, "the write itself must land on commit")
	}

	@Test func siblingWriteInsideReadCommitsIndependently() throws {
		let app = try makeApp()
		let contact = ContactID(RAW_native: 10)
		let early = Timestamp(RAW_native: 1_000)
		let later = Timestamp(RAW_native: 2_000)
		try app.contacts.markSync([contact], at: early)

		// snapshot sees the committed value; the sibling write commits on its own
		let before = try app.contacts.snapshotAndBump(contact, at: later)
		#expect(before == early, "the read boundary's snapshot predates the sibling write")
		#expect(try readLastSyncViaRaw(app, contact: contact) == later, "the sibling write committed independently")
	}

	@Test func siblingReadInsideReadIsLegal() throws {
		let app = try makeApp()
		let day = DayKey(RAW_native: 6)
		let event = EventID(RAW_native: 600)
		try app.calendar.bookEvent(event, on: day)
		let (a, b) = try app.calendar.daySnapshotTwice(day)
		#expect(a == event && b == event)
	}

	@Test func childAbortLeavesParentUsable() throws {
		let app = try makeApp()
		let day = DayKey(RAW_native: 7)
		let event = EventID(RAW_native: 700)
		let blocked = ContactID(RAW_native: 0)   // the guarded child rejects this one
		let good1 = ContactID(RAW_native: 1)
		let good2 = ContactID(RAW_native: 2)
		let accepted = try app.calendar.bookWithAvailableInvitees(event, on: day, invitees: [good1, blocked, good2])
		#expect(accepted == [good1, good2], "the blocked child aborted independently; the others merged")
		#expect(try readEventViaRaw(app, day: day) == event, "the parent boundary's write survived the child abort")
		#expect(try readInviteesViaRaw(app, event: event) == [good1, good2], "only the surviving children's writes landed")
	}

	@Test func injectedTxHelperComposition() throws {
		let app = try makeApp()
		let day = DayKey(RAW_native: 8)
		let event = EventID(RAW_native: 800)
		try app.calendar.bookViaHelper(event, on: day)
		#expect(try readEventViaRaw(app, day: day) == event)
	}

	// - MARK: spanning (cross-environment) cells

	@Test func spanningWriteIsOneEffortlessCallWithTwoTransactions() throws {
		let app = try makeApp()
		let day = DayKey(RAW_native: 10)
		let event = EventID(RAW_native: 1000)
		let invitees = [ContactID(RAW_native: 1), ContactID(RAW_native: 2)]
		let when = Timestamp(RAW_native: 5_000)

		// one app-level method; behind the seams: a calendar write txn (+ children)
		// and a contacts write txn, both committed.
		try app.scheduleMeeting(event, on: day, invitees: invitees, at: when)

		#expect(try readEventViaRaw(app, day: day) == event)
		#expect(try readInviteesViaRaw(app, event: event) == invitees)
		#expect(try readLastSyncViaRaw(app, contact: ContactID(RAW_native: 1)) == when)
		#expect(try readLastSyncViaRaw(app, contact: ContactID(RAW_native: 2)) == when)
	}

	@Test func spanningReadReadsBothEnvironments() throws {
		let app = try makeApp()
		let day = DayKey(RAW_native: 11)
		let event = EventID(RAW_native: 1100)
		let invitees = [ContactID(RAW_native: 7)]
		let when = Timestamp(RAW_native: 6_000)
		try app.scheduleMeeting(event, on: day, invitees: invitees, at: when)

		let overview = try app.dayOverview(on: day, contact: ContactID(RAW_native: 7))
		#expect(overview.event == event)
		#expect(overview.lastSync == when)
		#expect(try readInviteesViaRaw(app, event: event) == invitees)
	}

	@Test func bodyThrowAbortsAllSpanMembers() throws {
		// THE headline guarantee: a throw anywhere in the span body aborts ALL
		// member transactions — the calendar write is rolled back with the failed
		// contacts write. impossible with two isolated boundaries (the old
		// scheduleMeetingBestEffort, asserted in the next test, leaves the
		// calendar side durable).
		let app = try makeApp()
		let day = DayKey(RAW_native: 12)
		let event = EventID(RAW_native: 1200)
		let invitees = [ContactID(RAW_native: 1)]
		let when = Timestamp(RAW_native: 7_000)

		do {
			try app.scheduleMeetingAllOrNothing(event, on: day, invitees: invitees, at: when)
			Issue.record("expected the span body's throw to propagate")
		} catch is ContactError {
			// expected
		}
		#expect(try readEventViaRaw(app, day: day) == nil, "the calendar member aborted — no partial logical op survived")
		#expect(try readInviteesViaRaw(app, event: event) == [], "the calendar invitees member aborted")
		#expect(try readLastSyncViaRaw(app, contact: ContactID(RAW_native: 1)) == nil, "the contacts member aborted")
	}

	@Test func isolatedTwoStepContrastLeavesFirstStepDurable() throws {
		// the pre-span contrast: two isolated boundaries. a contacts failure leaves
		// the already-committed calendar write durable — exactly what the span's
		// all-abort removes. pinned so the upgrade is meaningful.
		let app = try makeApp()
		let day = DayKey(RAW_native: 13)
		let event = EventID(RAW_native: 1300)
		let invitees = [ContactID(RAW_native: 1)]
		let when = Timestamp(RAW_native: 7_000)

		do {
			try app.scheduleMeetingBestEffort(event, on: day, invitees: invitees, at: when)
			Issue.record("expected the contacts failure to propagate")
		} catch is ContactError {
			// expected
		}
		#expect(try readEventViaRaw(app, day: day) == event, "the isolated calendar boundary already committed and survives")
		#expect(try readInviteesViaRaw(app, event: event) == invitees)
		#expect(try readLastSyncViaRaw(app, contact: ContactID(RAW_native: 1)) == nil, "the isolated contacts boundary aborted — nothing landed")
	}

	@Test func explicitOverrideReachesSameState() throws {
		// the forced-member-list span must leave identical durable state to the
		// bare-inferred span (both are calendar+contacts readWrite, same order).
		let app = try makeApp()
		let day = DayKey(RAW_native: 15)
		let event = EventID(RAW_native: 1500)
		let invitees = [ContactID(RAW_native: 5), ContactID(RAW_native: 6)]
		let when = Timestamp(RAW_native: 9_000)

		try app.scheduleMeetingPinned(event, on: day, invitees: invitees, at: when)
		#expect(try readEventViaRaw(app, day: day) == event)
		#expect(try readInviteesViaRaw(app, event: event) == invitees)
		#expect(try readLastSyncViaRaw(app, contact: ContactID(RAW_native: 5)) == when)
		#expect(try readLastSyncViaRaw(app, contact: ContactID(RAW_native: 6)) == when)
	}

	@Test func manualTwoTransactionContrastReachesSameState() throws {
		let app = try makeApp()
		let day = DayKey(RAW_native: 14)
		let event = EventID(RAW_native: 1400)
		let invitees = [ContactID(RAW_native: 3), ContactID(RAW_native: 4)]
		let when = Timestamp(RAW_native: 8_000)

		// the boundary version (scheduleMeeting) and the manual raw version
		// (scheduleMeetingManual) must leave identical durable state.
		try app.scheduleMeetingManual(event, on: day, invitees: invitees, at: when)
		#expect(try readEventViaRaw(app, day: day) == event)
		#expect(try readInviteesViaRaw(app, event: event) == invitees)
		#expect(try readLastSyncViaRaw(app, contact: ContactID(RAW_native: 3)) == when)
	}
}
