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

- A transaction created directly (``QuickLMDB/Transaction/init(env:readOnly:)``) is closed explicitly by calling ``QuickLMDB/Transaction/commit()`` or ``QuickLMDB/Transaction/abort()``. as a safety net, the deinit of a transaction that was never closed aborts it.

- An ``QuickLMDB/MDB_transact(_:environments:)`` boundary closes its transactions exactly once: on success a `.readOnly` boundary aborts every one (a read leaf never commits) and a `.readWrite` boundary commits every one; on a thrown body it aborts every one.

- At any time, a developer may call ``QuickLMDB/Transaction/commit()``, ``QuickLMDB/Transaction/abort()``, ``QuickLMDB/Transaction/reset()``, or ``QuickLMDB/Transaction/renew()`` to force their own behavior on a transaction.

## Transaction boundaries with macros

QuickLMDB organizes the transaction layer into **method boundaries** with no ambient state of any kind (no task-local, no thread-local, no registry). the current architecture is a single boundary dialect:

- ``QuickLMDB/MDB_transact(_:environments:)`` — attached **body + peer**. the body scrapes the method and replaces it with a SHELL (one `tx_<E>` per listed environment, the wrapped-sibling call, and the mode-driven close); the peer emits the WRAPPED SIBLING that carries the real body.
- ``QuickLMDB/MDB_transacted(_:)`` — the Design-B join marker: inside a boundary it is rewritten into a call to the callee's wrapped sibling, threading this boundary's transaction.
- ``QuickLMDB/MDB_entry_load(_:database:key:)`` / ``QuickLMDB/MDB_entry_store(_:database:key:value:)`` — the trailing verbs, lowered inside a boundary.

### ``QuickLMDB/MDB_transact(_:environments:)`` — attached body + peer

```swift
@MDB_environment(file: "booking.mdb", flags: [.noSubDir], maxReaders: 32, maxDBs: 8)
public struct BookingCore: Sendable {
    public let env: Environment
    public let sheets: Database.Strict<SlotKey, SlotRecord>
}

enum BookingApp {
    static let booking = BookingCore.open(at: "...")

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

- **modes** (``QuickLMDB/MDB_transact_mode``): `.readOnly` opens read transactions that never commit (a read leaf); `.readWrite` commits each on success. child/relationship composition is NOT a mode — composition is joining (below).
- **`environments:`** lists the `@MDB_environment` cores that transact within the method; one `tx_<E>` per core, derived from its name. attribute arguments are evaluated at type scope, so the cores must be attribute-reachable (e.g. static stored properties).
- **marker gating (the rawdog principle):** only the trailing verbs and the join marker are rewritten; every other line is emitted byte-identical. a plain operation call inside a boundary is untouched — cursors, dup iteration, and zero-copy reads work directly with the injected `tx_<E>` name.
- the trailing verbs used **outside** a boundary, and ``MDB_transacted(_:)`` written anywhere but inside one, are compile-time diagnostics.
- the annotated method must be `throws` (the boundary can fail to open or close) and must not be `async`.

### Composition is JOINING

`#MDB_transacted(callee(args))` is rewritten into `callee(args, tx_<E>: tx_<E>, …)` — the callee JOINS this boundary's transaction instead of opening its own:

- joined reads see this boundary's own uncommitted state (the new "child view");
- joined writes land in ONE transaction — **atomic by construction** (a thrown joined write rolls back the whole boundary);
- a *sibling* read — the last committed state, independent of this boundary — is a plain call (`slotOn(day)` opens its own read transaction);
- the equal-env-set contract: the rewrite passes the caller's full tx label set, so the callee's wrapped sibling must declare exactly those labels (a single-env helper called from a multi-env boundary does not compile — loud and named at the call site).

### ``QuickLMDB/MDB_environment(file:flags:maxReaders:maxDBs:mode:)`` — schema assembly

Generates a `static func open(at:mapHeadroom:)` that creates the directory as needed, sizes the memory map as current file size plus headroom, opens the environment with the macro-declared flags, and opens every `Database.X` table in one setup write-transaction. Table names are derived from the property names. The struct must store exactly `env` plus `Database.X` tables (plain `Database` raw tables are supported). `.noTLS` is forced on every environment (reader slots bind to the transaction object, making Swift task-based concurrency safe and enabling sibling reads).

### Self-scoped committed reads

Verification reads ("what is the last committed state") carry no transaction ceremony. ``QuickLMDB/MDB_db`` protocol-extension members `readCommitted(key:)`, `containsCommitted(key:)`, and (on dupsort databases) `readCommittedDups(key:)` each open their own read-only transaction, perform the read, and close it internally. they are deliberately NOT boundary verbs — a verb's contract is boundary participation, the opposite of a self-scoped verification read — so they are members, not macros.

### Multi-environment boundaries

The same boundary coordinates MORE than one environment — list every core that needs to transact:

```swift
@MDB_transact(.readWrite, environments: calendar, contacts)
static func scheduleAndMarkSync(_ event: EventID, on day: DayKey,
                                contact: ContactID, at timestamp: Timestamp) throws {
    try #MDB_entry_store(environment: calendar, database: calendar.events, key: day, value: event)
    try #MDB_entry_store(environment: contacts, database: contacts.lastSync, key: contact, value: timestamp)
}
```

one transaction per listed core, all opened up front, ALL aborted on any body throw (nothing lands), write members committed back-to-back. **honest ceiling:** cross-environment commits are best-effort — a crash between the adjacent commit calls can still split the pair. cross-env atomicity is impossible. (within ONE environment, joined writes are fully atomic — the single transaction.)

All macros expand to plain calls through the existing public API — `Environment`, `Transaction`, `Database.*`, `load(key:tx:)`, `store(key:value:tx:)`, `cursor(tx:_:)`. the raw bridge that backs these calls lives in the standalone `QuickLMDBFunctionalInterop` product, along with `LMDBError`: its public api surface is a layer of functions that take `consuming MDB_val` arguments over raw handles (`MDB_dbi`, pointer handles) — the handle-level `MDB_*_static` implementations are module-internal. the C wrapper layer itself (CLMDB) is untouched.

The typed-handle companions the verbs lower to (`load(key:tx:)`, `store(key:value:flags:tx:)`, `delete(key:tx:)`, `contains(key:tx:)`, plus the dupsort pair `delete(key:value:tx:)`) are protocol-extension members of ``QuickLMDB/MDB_db``, so every handle — `Database`, `Database.Strict`, `Database.DupSort`, `Database.DupFixed` — inherits them. the raw ``QuickLMDB/MDB_val`` tier keeps `loadEntry(key:as:tx:)` for value-raw call sites. The raw ``QuickLMDB/Transaction`` surface stays public for code that deliberately manages its own transactions.
