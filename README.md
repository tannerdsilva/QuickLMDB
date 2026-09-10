# QuickLMDB

QuickLMDB is designed to be a easy, efficient, and uncompromising integration of the LMDB library. QuickLMDB does not hide access to the underlying LMDB core, allowing you to directly utilize the core LMDB API at any time. Likewise, QuickLMDB makes it very easy to write high-level code that is simultaneously memory-safe and high-performance.

- QuickLMDB is the only known Swift library to allow full transactional control over an Environment. This is crucial to achieving high performance.

- QuickLMDB allows direct access to the LMDB memorymap without overhead or copies. This is also a unique feature for Swift-based LMDB wrappers.

## Transaction boundaries with macros

QuickLMDB organizes the transaction layer into **method boundaries** with no ambient state of any kind (no task-local, no thread-local, no registry). A boundary is an attached **body + peer** macro: the body scrapes the method and replaces it with a shell that opens one transaction per listed environment and closes each (abort on throw; abort for `.readOnly`, commit for `.readWrite` on success); the peer emits a wrapped sibling that carries the real body. Inside the body, **trailing verb macros** are lowered to their tx-bearing calls and the `#MDB_transacted` marker joins another boundary's call onto *this* boundary's transaction.

```swift
@MDB_environment(file: "booking.mdb", flags: [.noSubDir], maxReaders: 32, maxDBs: 8)
public struct BookingCore: Sendable {
    public let env: Environment
    public let sheets: Database.Strict<SlotKey, SlotRecord>
}

enum BookingApp {
    // attribute arguments are evaluated at type scope: the cores must be
    // attribute-reachable, so they are static stored properties opened through
    // the non-throwing lazy factory (an unopenable path crashes on first use).
    static let booking: BookingCore = { try! BookingCore.open(at: "<data-path>") }()

    @MDB_transact(.readWrite, environments: booking)
    static func addBooking(_ key: SlotKey, _ record: SlotRecord) throws {
        try #MDB_entry_store(environment: booking, database: booking.sheets, key: key, value: record)
    }

    @MDB_transact(.readOnly, environments: booking)
    static func slotOn(_ day: SlotKey) throws -> SlotRecord? {
        #MDB_entry_load(environment: booking, database: booking.sheets, key: day)
    }
}
```

- **`@MDB_transact(_ mode: MDB_transact_mode, environments: ...)`** — the boundary. `.readOnly` opens read transactions that never commit (a read leaf); `.readWrite` commits each on success. the `environments:` variadic lists the `@MDB_environment` cores that transact within the method — one `tx_<E>` per core, derived from its name (attribute arguments are evaluated at type scope, so the cores must be attribute-reachable, e.g. static stored properties).
- **Marker gating (the rawdog principle):** only the freestanding verbs (`#MDB_entry_load`, `#MDB_entry_store`) and the `#MDB_transacted(...)` join marker are rewritten; every other line is emitted byte-identical. a plain operation call inside a boundary is untouched — the raw surface (cursors, zero-copy reads, dup iteration) works directly with the injected `tx_<E>` name.
- Using a verb or the marker **outside** a boundary is a compile-time diagnostic.
- **Composition is JOINING, not nesting.** `#MDB_transacted(callee(args))` is rewritten into `callee(args, tx_<E>: tx_<E>, …)` — the callee runs on *this* boundary's transaction. joined reads see this boundary's own uncommitted state; joined writes land in ONE transaction, **atomic by construction** (a thrown joined write rolls back the whole boundary). a *sibling* read — the last committed state, independent of this boundary — is a plain call `eventOn(day)`.

## Self-scoped committed reads

For verification reads (tests, health checks) that just want "what is the last committed state", the typed handles carry self-scoped read members — each opens its own read-only transaction, performs the read, and closes it internally:

```swift
let v = try core.primary.readCommitted(key: key)          // -> Value? (nil when absent)
let present = try core.primary.containsCommitted(key: key) // -> Bool
let dups = try core.secondary.readCommittedDups(key: key)  // -> [Value] (dupsort)
```

these are NOT boundary verbs: a verb's contract is boundary participation, the opposite of a self-scoped verification read. they are protocol-extension members of `MDB_db`, so every handle — `Database`, `Database.Strict`, `Database.DupSort`, `Database.DupFixed` — inherits them with no manual `Transaction` ceremony.

## Multi-environment boundaries

The same boundary coordinates MORE than one environment — list every core that needs to transact:

```swift
enum ClubApp {
    static let calendar: ClubCalendarCore = ...
    static let contacts: ClubContactsCore = ...

    @MDB_transact(.readWrite, environments: calendar, contacts)
    static func scheduleAndMarkSync(_ event: EventID, on day: DayKey,
                                    contact: ContactID, at timestamp: Timestamp) throws {
        try #MDB_entry_store(environment: calendar, database: calendar.events, key: day, value: event)
        try #MDB_entry_store(environment: contacts, database: contacts.lastSync, key: contact, value: timestamp)
    }
}
```

one transaction per listed core, all aborted on any body throw (nothing lands), write members committed back-to-back. **honest ceiling:** cross-environment commits are best-effort — a crash between the adjacent commit calls can still split the pair. cross-env atomicity is impossible. (within ONE environment, joined writes are fully atomic — the single transaction.)

## Transaction relationships

- **joined** (via `#MDB_transacted`) — the callee runs on the caller's transaction: reads see the boundary's own uncommitted state; writes are atomic with the boundary.
- **sibling** (a plain call) — the callee opens its own transaction: reads see the last committed state; sibling writes commit independently.
- a `.readWrite` boundary's write composition is by joining, never by nesting a second write boundary call without a join — LMDB's writer mutex deadlocks on a second top-level write on one thread, and joining avoids it entirely.

`@MDB_environment` forces `.noTLS` on every environment it opens: reader slots bind to the transaction object rather than the thread, which makes Swift's task-based concurrency safe and enables sibling reads.

All macros expand to plain calls through the existing public API (`Environment`, `Transaction`, `Database.*`, `load(key:tx:)`, `store(key:value:tx:)`, `cursor(tx:_:)`). The raw bridge that backs these calls lives in the standalone `QuickLMDBFunctionalInterop` product, along with `LMDBError`: its public api surface is a layer of functions that take `consuming MDB_val` arguments over raw handles (`MDB_dbi`, pointer handles) — the handle-level `MDB_*_static` implementations are module-internal. The C wrapper layer itself (CLMDB) is untouched.

The raw `Transaction` surface stays public for code that deliberately manages its own transactions.

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
