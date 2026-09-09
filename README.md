# QuickLMDB

QuickLMDB is designed to be a easy, efficient, and uncompromising integration of the LMDB library. QuickLMDB does not hide access to the underlying LMDB core, allowing you to directly utilize the core LMDB API at any time. Likewise, QuickLMDB makes it very easy to write high-level code that is simultaneously memory-safe and high-performance. 

- QuickLMDB is the only known Swift library to allow full transactional control over an Environment. This is crucial to achieving high performance.

- QuickLMDB allows direct access to the LMDB memorymap without overhead or copies. This is also a unique feature for Swift-based LMDB wrappers.

## Transaction boundaries with macros

QuickLMDB ships two macros that organize the transaction layer into method boundaries, with no ambient state of any kind (no task-local, no thread-local, no registry):

- `@MDB_transact(.readWrite | .readOnly | .readWriteChild)` — an attached **body macro**. It rewrites the annotated method's body in place: the method itself owns its transaction scope. Inside the body, **freestanding verb macros** — `#store`, `#load`, `#delete`, `#contains`, `#cursor`, `#clear` — are lowered to the same tx-bearing calls, threading the boundary transaction automatically. the scope commits exactly once on success / aborts exactly once on error.

```swift
@MDB_environment(file: "booking.mdb", flags: [.noSubDir], maxReaders: 32, maxDBs: 8)
public struct BookingCore: Sendable {
    public let env: Environment
    public let sheets: Database.Strict<SlotKey, SlotRecord>
}

extension BookingCore {
    @MDB_transact(.readWrite)
    public func addBooking(_ key: SlotKey, _ record: SlotRecord) throws {
        try #store(sheets, key: key, value: record)
    }

    @MDB_transact(.readOnly)
    public func nearestSlot(to date: SlotKey) throws -> SlotRecord? {
        var found: SlotRecord? = nil
        #cursor(sheets) { cursor in
            if let first = try? cursor.opSetRange(key: date).value {
                found = first
            }
        }
        return found
    }
}
```

  - **Marker gating (the rawdog principle):** no line is rewritten unless it is a freestanding verb macro in the closed set — `#store`, `#load`, `#delete`, `#contains`, `#cursor`, `#clear`, `#stats`, `#drop`. every other line is emitted byte-identical — a user function named `setEntry` can never be reached by the rewriter. consequence: a plain operation call inside a boundary must carry `tx:` explicitly (verb-free code either uses `tx: tx` or fails to compile).
  - Using a verb **outside** a boundary is a compile-time diagnostic (`must only appear inside an @MDB_transact body`) — the standalone verb expansion is a hard error by construction.
  - `#stats(db)` reads `dbStatistics(tx:)` (metadata); `#drop(db)` runs `deleteDatabase(tx:)` — destructive and handle-consuming, so its receiver must be a locally-owned raw `Database`, never a stored `self.X` table.
  - Composition of reusable logic is BOUNDARIES, not tx-taking helpers: the injected `tx` exists for exactly one purpose — passing as `parent:` to a `.readWriteChild` boundary (write reuse, merges into the caller's view) or `.readOnly` sibling (read reuse). a helper that does DB work declares its mode in its own boundary attribute; there is no plain-helper-with-`tx:` pattern for it to leak mode through.

- `@MDB_environment(file:flags:maxReaders:maxDBs:mode:)` — schema assembly: generates `static func open(at:mapHeadroom:)` which sizes the memory map, opens the environment, and opens every `Database.X` table in one setup write-transaction.

## Cross-environment boundaries (spans)

For apps that own MORE than one environment, `@MDB_app` + `@MDB_transact_span` coordinate all of them behind one method — one top-level transaction per core, all opened up front, ALL aborted on any body throw, and the write members committed back-to-back in first-touch order (read members simply close):

```swift
@MDB_app
public struct HybridApp {
    public var calendar: CalendarCore
    public var contacts: ContactCore

    @MDB_transact_span
    public func scheduleMeeting(_ event: EventID, on day: DayKey,
                                invitees: [ContactID], at timestamp: Timestamp) throws {
        try #store(calendar.events, key: day, value: event)
        for invitee in invitees {
            try #store(calendar.invitees, key: event, value: invitee)
            try #store(contacts.lastSync, key: invitee, value: timestamp)
        }
    }
}
```

- `@MDB_app` marks the struct as an environment **container** (its stored `@MDB_environment` cores become the environment inventory) and is required on the span's containing type.
- The **bare form infers everything from the verbs**: environments = the receiver base names, modes = any write verb (`#store`/`#delete`/`#clear`) marks a core read-write (read-only access alone marks it read-only), commit order = first-touch order.
- The **override form** forces modes/order explicitly: `@MDB_transact_span([.readWrite("calendar"), .readOnly("contacts")])` — cores named by stored property as strings (a naked `.readWrite(calendar)` can't type-check: attribute arguments are evaluated on the type level).
- Injected names are `tx_<core>` (e.g. `tx_calendar`): hand one to a `.readWriteChild(parent:)` boundary to merge into a member transaction with the span.
- **Honest ceiling:** cross-environment commits are best-effort — the span aborts ALL members on a body throw (nothing lands), but a crash between the two adjacent commit calls can still split the pair. cross-env atomicity is impossible.

All four macros expand to plain calls through the existing public API (`Environment`, `Transaction`, `Database.*`, `load(key:tx:)`, `store(key:value:flags:tx:)`, `cursor(tx:_:)`). The raw bridge that backs these calls lives in the standalone `QuickLMDBFunctionalInterop` product, along with `LMDBError`: its public api surface is a layer of functions that take `consuming MDB_val` arguments over raw handles (`MDB_dbi`, pointer handles) — the handle-level `MDB_*_static` implementations are module-internal. The C wrapper layer itself (CLMDB) is untouched.

## Transaction relationships

Boundaries open top-level transactions of their requested mode; relationships are the engine's own defaults, pinned by tests: a `readOnly` boundary inside a `readWrite` boundary is a **sibling read** (sees the last committed state), inside another `readOnly` boundary it is a sibling read when the environment uses `.noTLS` (`badReaderSlot` otherwise), and a `readWrite` boundary inside a `readOnly` boundary is a **sibling write** (commits independently). Write composition inside a write boundary is explicit via `.readWriteChild(parent:)` — nesting a plain `.readWrite` without `parent:` deadlocks on LMDB's writer mutex and is forbidden.

`@MDB_environment` forces `.noTLS` on every environment it opens: reader slots bind to the transaction object rather than the thread, which makes Swift's task-based concurrency safe and enables the sibling-read relationships above.

## Versioning

This library uses SemVer 2.0 for version tags.

## Compatibility

QuickLMDB is fully supported(*) on all platforms capable of running Swift, including:

- Linux

- MacOS (* Non-Sandboxed Only)

- iOS

## License

QuickLMDB is available with an MIT license.

LMDB is included with QuickLMDB with an OpenLDAP license.
