# QuickLMDB

QuickLMDB is designed to be a easy, efficient, and uncompromising integration of the LMDB library. QuickLMDB does not hide access to the underlying LMDB core, allowing you to directly utilize the core LMDB API at any time. Likewise, QuickLMDB makes it very easy to write high-level code that is simultaneously memory-safe and high-performance.

- QuickLMDB is the only known Swift library to allow full transactional control over an Environment. This is crucial to achieving high performance.

- QuickLMDB allows direct access to the LMDB memorymap without overhead or copies. This is also a unique feature for Swift-based LMDB wrappers.

## Transaction boundaries with macros

QuickLMDB organizes the transaction layer into **method boundaries** with no ambient state of any kind (no task-local, no thread-local, no registry). Every environment is its own `@MDB_environment` **type**, and a boundary is an INSTANCE method on that type: `@MDB_transact(_ mode:)` turns the method into a transactional unit whose transactions are opened, committed, and aborted for it. The authored surface carries NO transaction vocabulary — no `tx:` parameters, no environment lists, no entry suffixes.

Inside a boundary body you write the **typed verb family** — the exact database operations (`#store`/`#load`/`#delete`/`#contains`/`#cursor`/`#clear`/`#stats`/`#drop`), where the first argument is the environment TYPE and `database:` is a `KeyPath` to a `Database.X` handle, so the key/value types are compiler-checked against the table itself. The boundary lowers each verb to the tx-bearing operation.

```swift
@MDB_environment(file: "booking.mdb", flags: [.noSubDir], maxReaders: 32, maxDBs: 8)
public struct BookingCore: Sendable {
    public let env: Environment
    public let sheets: Database.Strict<SlotKey, SlotRecord>

    @MDB_transact(.readWrite)
    public func addBooking(_ key: SlotKey, _ record: SlotRecord) throws {
        try #store(BookingCore.self, database: \.sheets, key: key, value: record)
    }

    @MDB_transact(.readOnly)
    public func slotOn(_ day: SlotKey) throws -> SlotRecord? {
        #load(BookingCore.self, database: \.sheets, key: day)
    }
}

let booking = try BookingCore.open(at: "<data-path>")
try booking.addBooking(key, record)
let record = try booking.slotOn(day)
```

- **`@MDB_transact(_ mode: MDB_transact_mode)`** — the boundary, on an instance method of an `@MDB_environment` type. `.readOnly` opens read transactions that never commit (a read leaf); `.readWrite` commits each on success. The environment set is **inferred from the verbs** — every environment type a verb references must be `self` or a typed parameter of the method. A multi-environment boundary just takes the other cores as typed parameters.
- **The typed verbs** (`#store(E.self, database: \.table, key:…, value:…)`) — compiler-typed end to end: `E` names the environment, the `KeyPath` names the table on that type, and key/value/return types flow from the table's own generics. A call inside a boundary is lowered to `instance[keyPath: \.table].<op>(…, tx:)`; used outside a boundary it is a compile-time diagnostic.
- **Composition is JOINING, not nesting.** `#MDB_transacted(callee(args))` is rewritten into the callee's sibling with `tx_<E>` threading — the callee runs on *this* boundary's transaction. joined reads see this boundary's own uncommitted state; joined writes land in ONE transaction, **atomic by construction** (a thrown joined write rolls back the whole boundary). a *sibling* read — the last committed state, independent of this boundary — is a plain call `eventOn(day)`.
- **THE JOIN / SIBLING RULE (deadlock warning):** a bare call to a `.readWrite` boundary inside a live boundary opens a SECOND write transaction, which BLOCKS on LMDB's writer mutex until the outer commits — and the outer can't commit while it blocks: a **DEADLOCK**. composition inside a boundary is spelled with `#MDB_transacted(...)`, always. a bare call to a `.readOnly` boundary inside a boundary is a safe *sibling read* (its own fresh read transaction, committed state only).

## Self-scoped committed reads

For verification reads (tests, health checks) that just want "what is the last committed state", the typed handles carry self-scoped read members — each opens its own read-only transaction, performs the read, and closes it internally:

```swift
let v = try core.primary.readCommitted(key: key)          // -> Value? (nil when absent)
let present = try core.primary.containsCommitted(key: key) // -> Bool
let dups = try core.secondary.readCommittedDups(key: key)  // -> [Value] (dupsort)
```

these are NOT boundary verbs: a verb's contract is boundary participation, the opposite of a self-scoped verification read. they are protocol-extension members of `MDB_db`, so every handle — `Database`, `Database.Strict`, `Database.DupSort`, `Database.DupFixed` — inherits them with no manual `Transaction` ceremony.

## Multi-environment boundaries

The same boundary coordinates MORE than one environment — the other cores flow in as **typed parameters**:

```swift
public struct ClubCalendarCore: Sendable { … }   // @MDB_environment: events, invitees
public struct ClubContactsCore: Sendable { … }    // @MDB_environment: lastSync

extension ClubCalendarCore {
    @MDB_transact(.readWrite)
    public func scheduleAndMarkSync(_ event: EventID, on day: DayKey,
                                    contact: ContactID, at timestamp: Timestamp,
                                    contacts: ClubContactsCore) throws {
        try #store(ClubCalendarCore.self, database: \.events, key: day, value: event)
        try #store(ClubContactsCore.self, database: \.lastSync, key: contact, value: timestamp)
    }
}
```

one transaction per referenced environment, all aborted on any body throw (nothing lands), write members committed back-to-back. **honest ceiling:** cross-environment commits are best-effort — a crash between the adjacent commit calls can still split the pair. cross-env atomicity is impossible. (within ONE environment, joined writes are fully atomic — the single transaction.)

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
