# ``QuickLMDB``

QuickLMDB is designed to be a easy, efficient, and uncompromising integration of the LMDB library. QuickLMDB does not hide access to the underlying LMDB core, allowing you to directly utilize the core LMDB API at any time. Likewise, QuickLMDB makes it very easy to write high-level code that is simultaneously memory-safe and high-performance.

### Why QuickLMDB?

- QuickLMDB is the only known Swift library to allow full transactional control over an Environment. This is crucial to achieving high performance.

- QuickLMDB allows direct access to the LMDB memorymap without overhead or copies. This is also a unique feature for Swift-based LMDB wrappers.

## LMDB basics

The basic object relationship for QuickLMDB is as follows:

- ``QuickLMDB/Environment`` is the foundation of QuickLMDB, as it is in the LMDB core. Environments are created with a system path.

	- ``QuickLMDB/Environment``s create ``QuickLMDB/Transaction``s

	- ``QuickLMDB/Environment`` can open ``QuickLMDB/Database``s under the existence of a ``QuickLMDB/Transaction``

		- ``QuickLMDB/Database`` can store and retreive key/value pairs

	- A ``QuickLMDB/Transaction`` may open child transactions, in certain contexts

	- ``QuickLMDB/Database`` can open ``QuickLMDB/Cursor`` under the existence of a ``QuickLMDB/Transaction``

## Notes on API

Here are a few notes about the QuickLMDB API design. Keeping these notes in mind will help you use the API as efficiently as possible.

### MDB_convertible protocol

This is the native serialization and deserialization protocol for QuickLMDB.

- Required when using ``QuickLMDB/Database`` (for convenience).

- Optional when using ``QuickLMDB/Cursor`` (allowing for zero-copy access to your data).

- Custom objects (classes and structs) can conform to this protocol with minimal code.

	- Objects that conform to `LosslessStringConvertible` can conform to ``QuickLMDB/MDB_convertible`` with ZERO additional lines of code.

### Database struct

In the spirit of the core LMDB API, QuickLMDB's ``QuickLMDB/Database`` struct is designed to be approachable and convenient.

- Handles serialization on your behalf with ``QuickLMDB/MDB_convertible`` protocol. Standardized serialization eliminates the need for redundant code, and as a result, reduces the risk of bugs.

- Returns a specified ``QuickLMDB/MDB_convertible`` Type directly from database, rather than expecting you to deserialize data entries on your own.

### Cursor class

QuickLMDB's ``QuickLMDB/Cursor`` class also follows the spirit of the underlying LMDB API, by offering advanced access to a given database.

- No built in serialization or data copies.

- Returns the explicit `MDB_val` structs that the LMDB core is utilizing under the hood.

	- When reading entries, this allows the developer to chose when to deserialize a given data entry.

	- Serialization and deserialization of returned `MDB_val` can occur with a single line of code.

- Conforms to Swift's `Sequence` protocol, allowing a cursor to be used in a loop with a single line of code.

### Lifecycle management

QuickLMDB has reasonable default behavior when managing the lifecycle of ``QuickLMDB/Transaction``s and ``QuickLMDB/Cursor``s.

- A transaction created directly (``QuickLMDB/Transaction/init(env:)``, mode in the type: `Transaction<Read>(env:)` / `Transaction<Write>(env:)`) is closed explicitly by calling ``QuickLMDB/Transaction/commit()`` (write transactions only) or ``QuickLMDB/Transaction/abort()``. as a safety net, the deinit of a transaction that was never closed aborts it.

- An ``QuickLMDB/MDB_transact(_:)`` boundary closes its transactions exactly once: on success a `.readOnly` boundary aborts every one (a read leaf never commits) and a `.readWrite` boundary commits every one; on a thrown body it aborts every one.

- The transaction's mode lives in its type (`Read` / `Write`): writing on a read transaction is a type-checker error (`commit()` does not exist on `Transaction<Read>`), and reads are available on either.

- At any time, a developer may call ``QuickLMDB/Transaction/commit()``, ``QuickLMDB/Transaction/abort()``, ``QuickLMDB/Transaction/reset()``, or ``QuickLMDB/Transaction/renew()`` to force their own behavior on a transaction.

## Transaction boundaries with macros

QuickLMDB organizes the transaction layer into **method boundaries** with no ambient state of any kind (no task-local, no thread-local, no registry). every environment is its own ``QuickLMDB/MDB_environment`` TYPE, and a boundary is an INSTANCE method on that type. the authored surface carries no transaction vocabulary:

- ``QuickLMDB/MDB_transact(_:)`` — attached body + peer. the environment set is INFERRED from the typed verb calls in the body; the method becomes a SHELL (opens/closes its own transactions) and the peer emits an INVISIBLE sibling carrying the tx parameters.
- the **typed verb family** — ``QuickLMDB/store(_:database:key:value:flags:)``, ``QuickLMDB/load(_:database:key:)``, ``QuickLMDB/delete(_:database:key:)``, ``QuickLMDB/contains(_:database:key:)``, ``QuickLMDB/cursor(_:database:_:)``, plus ``QuickLMDB/clear(_:database:)``, ``QuickLMDB/stats(_:database:)``, ``QuickLMDB/drop(_:database:)`` — the exact database operations, where the first argument is the environment TYPE and `database:` is a ``KeyPath`` to a `Database.X` handle (key/value/return types bind through the table's own generics).
- ``QuickLMDB/MDB_transacted(_:)`` — the Design-B JOIN marker: inside a boundary it is rewritten into a call to the callee's sibling, threading this boundary's transaction.

### ``QuickLMDB/MDB_transact(_:)`` — the boundary

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

- **modes** (``QuickLMDB/MDB_transact_mode``): `.readOnly` opens read transactions that never commit (a read leaf); `.readWrite` commits each on success. child/relationship composition is NOT a mode — composition is joining (below).
- **the environment set is inferred from the verbs.** every environment type a verb references must be `self` (the boundary is attached to that core type) or a typed parameter of the method — a multi-environment boundary takes the other cores as typed parameters.
- the typed verbs used **outside** a boundary, and ``MDB_transacted(_:)`` written anywhere but inside one, are compile-time diagnostics.
- the annotated method must be an instance method, `throws` (the boundary can fail to open or close), and must not be `async`.
- typing end to end: `#store(BookingCore.self, database: \.sheets, key:…, value:…)` type-checks `key`/`value` against the `Database.Strict<SlotKey, SlotRecord>` the keypath names.

### Composition is JOINING

`#MDB_transacted(callee(args))` is rewritten into the callee's sibling with `tx_<E>` threading — the callee JOINS this boundary's transaction instead of opening its own:

- joined reads see this boundary's own uncommitted state (the "child view");
- joined writes land in ONE transaction — **atomic by construction** (a thrown joined write rolls back the whole boundary);
- a *sibling* read — the last committed state, independent of this boundary — is a plain call (`slotOn(day)` on its own instance opens its own read transaction);
- the equal-env-set contract: the rewrite passes the caller's full tx label set, so the callee's sibling must reference the same environment-type set (a single-env callee called from a multi-env boundary does not compile — loud and named at the call site).
- a bare call to a write boundary inside a live boundary also root-scopes (opens its own transaction) — composition is spelled with the join marker.

### ``QuickLMDB/MDB_environment(file:flags:maxReaders:maxDBs:mode:)`` — schema assembly

Generates a `static func open(at:mapHeadroom:)` that creates the directory as needed, sizes the memory map as current file size plus headroom, opens the environment with the macro-declared flags, and opens every `Database.X` table in one setup write-transaction. Table names are derived from the property names. The struct must store exactly `env` plus `Database.X` tables (plain `Database` raw tables are supported). `.noTLS` is forced on every environment (reader slots bind to the transaction object, making Swift task-based concurrency safe and enabling sibling reads). Writing the optional `version:` derives the on-disk name `<stem>-v<N>.mdb` — the schema version rides in the file name (opt-in; bumping ships a fresh file, old data untouched).

### ``QuickLMDB/MDB_layout()`` — the multi-environment arrangement

``QuickLMDB/MDB_layout()`` on a struct owning N ``QuickLMDB/MDB_environment`` cores generates a single `open(at:mapHeadroom:)` — each core opens at `<base>/<property name>` and a fresh instance is assembled — plus a `mdb_core_names` inventory. no per-core factories, no statics, no baked path; every environment stays its own type and boundaries live on those types.

### Self-scoped committed reads

Verification reads ("what is the last committed state") carry no transaction ceremony. ``QuickLMDB/MDB_db`` protocol-extension members `readCommitted(key:)`, `containsCommitted(key:)`, and (on dupsort databases) `readCommittedDups(key:)` each open their own read-only transaction, perform the read, and close it internally. they are deliberately NOT boundary verbs — a verb's contract is boundary participation, the opposite of a self-scoped verification read — so they are members, not macros.

### Multi-environment boundaries

The same boundary coordinates MORE than one environment — the other cores flow in as **typed parameters**:

```swift
@MDB_transact(.readWrite)
public func scheduleAndMarkSync(_ event: EventID, on day: DayKey,
                                contact: ContactID, at timestamp: Timestamp,
                                contacts: ClubContactsCore) throws {
    try #store(ClubCalendarCore.self, database: \.events, key: day, value: event)
    try #store(ClubContactsCore.self, database: \.lastSync, key: contact, value: timestamp)
}
```

one transaction per referenced environment, all opened up front, ALL aborted on any body throw (nothing lands), write members committed back-to-back. **honest ceiling:** cross-environment commits are best-effort — a crash between the adjacent commit calls can still split the pair. cross-env atomicity is impossible. (within ONE environment, joined writes are fully atomic — the single transaction.)

All macros expand to plain calls through the existing public API — `Environment`, `Transaction`, `Database.*`, `load(key:tx:)`, `store(key:value:tx:)`, `cursor(tx:_:)`. the raw bridge that backs these calls lives in the standalone `QuickLMDBFunctionalInterop` product, along with `LMDBError`: its public api surface is a layer of functions that take `consuming MDB_val` arguments over raw handles (`MDB_dbi`, pointer handles) — the handle-level `MDB_*_static` implementations are module-internal. the C wrapper layer itself (CLMDB) is untouched.

The typed-handle companions the verbs lower to (`load(key:tx:)`, `store(key:value:flags:tx:)`, `delete(key:tx:)`, `contains(key:tx:)`, plus the dupsort pair `delete(key:value:tx:)`) are protocol-extension members of ``QuickLMDB/MDB_db``, so every handle — `Database`, `Database.Strict`, `Database.DupSort`, `Database.DupFixed` — inherits them. the raw ``QuickLMDB/MDB_val`` tier keeps `loadEntry(key:as:tx:)` for value-raw call sites. The raw ``QuickLMDB/Transaction`` surface stays public for code that deliberately manages its own transactions.
