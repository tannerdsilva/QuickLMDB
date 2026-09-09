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

- An ``QuickLMDB/MDB_transact(_:)`` boundary commits its transaction exactly once when the body returns normally, and aborts exactly once when the body throws.

- At any time, a developer may call ``QuickLMDB/Transaction/commit()``, ``QuickLMDB/Transaction/abort()``, ``QuickLMDB/Transaction/reset()``, or ``QuickLMDB/Transaction/renew()`` to force their own behavior on a transaction.

## Transaction boundaries with macros

QuickLMDB ships two macros that organize transactions into method boundaries with no ambient state of any kind.

### ``QuickLMDB/MDB_transact(_:)`` — attached body macro

`@MDB_transact(.readWrite)` (or `.readOnly`, or `.readWriteChild`) makes the annotated method a transaction boundary. the expansion:

1. opens the boundary transaction (`Transaction(env: self.env, ...)`) as a `let tx`,
2. wraps the original body in a local function that receives `tx` as an explicit `borrowing` parameter,
3. lowers the freestanding verb macros — `#store`, `#load`, `#delete`, `#contains`, `#cursor`, `#clear` — to their tx-bearing calls, threading `tx`; every other line is emitted byte-identical (**marker gating**: a user function named like an operation can never be reached by the rewriter),
4. commits once on success and aborts exactly once if the body throws.

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

The verb vocabulary: `#store(db, key:, value:, flags: = [])`, `#load(db, key:)` (and `#load(db, key:, as:)` on raw ``QuickLMDB/MDB_val`` handles), `#delete(db, key:)` (and `#delete(db, key:, value:)` on duplicate-bearing tables), `#contains(db, key:)` (the `key:, value:` pair form lowers to the cursor's real ``MDB_GET_BOTH`` path — a database-level pair check would be a silent no-op), `#cursor(db) { cursor in ... }`, `#clear(db)`, `#stats(db)` (metadata read), and `#drop(db)` (deleteDatabase — destructive and handle-consuming; receiver must be a locally-owned raw ``QuickLMDB/Database``, never a stored `self.X` table). Each verb used **outside** a boundary is a compile-time diagnostic.

The injected name `tx` is also the documented way to hand a boundary transaction to a shared helper that takes `tx: borrowing Transaction` (e.g. `try applyDeltas(item, tx: tx)`). composable helpers that take an existing transaction keep their explicit `tx:` parameter and can be called from inside a boundary using the injected name. `.readWriteChild` requires a parent transaction parameter: `func commitBatch(_ items: [Item], parent: borrowing Transaction) throws`.

The annotated method must be `throws` (the boundary can fail to open or commit) and must not be `async`; non-verb operation calls inside the boundary must carry an explicit `tx:` argument (they are left byte-identical by the marker gate).

### ``QuickLMDB/MDB_environment(file:flags:maxReaders:maxDBs:mode:)`` — schema assembly

Generates a `static func open(at:mapHeadroom:)` that sizes the memory map as current file size plus headroom, opens the environment with the macro-declared flags, and opens every `Database.X` table in one setup write-transaction. Table names are derived from the property names. The struct must store exactly `env` plus `Database.X` tables (plain `Database` raw tables are supported).

Both macros expand to plain calls through the existing public API — `Environment`, `Transaction`, `Database.*`, `load(key:tx:)`, `store(key:value:flags:tx:)`, `cursor(tx:_:)`. the raw bridge that backs these calls lives in the standalone `QuickLMDBFunctionalInterop` product, along with `LMDBError`: its public api surface is a layer of functions that take `consuming MDB_val` arguments over raw handles (`MDB_dbi`, pointer handles) — the handle-level `MDB_*_static` implementations are module-internal. the C wrapper layer itself (CLMDB) is untouched.

The typed-handle companions the verbs lower to (`load(key:tx:)`, `store(key:value:flags:tx:)`, `delete(key:tx:)`, `contains(key:tx:)`, plus the dupsort pair `delete(key:value:tx:)`) are protocol-extension members of ``QuickLMDB/MDB_db``, so every handle — `Database`, `Database.Strict`, `Database.DupSort`, `Database.DupFixed` — inherits them. the raw ``QuickLMDB/MDB_val`` tier keeps `loadEntry(key:as:tx:)` for value-raw call sites.

### ``QuickLMDB/MDB_app(_:)`` + ``QuickLMDB/MDB_transact_span(_:)`` — cross-environment boundaries

Apps that own MORE than one ``QuickLMDB/Environment`` can coordinate all of them behind one method. ``MDB_app(_:)`` marks the struct as an environment **container** (its stored ``MDB_environment`` cores become the routing inventory), and ``MDB_transact_span(_:)`` opens ONE top-level transaction per core up front, aborts ALL of them on any body throw, and commits the write members back-to-back in first-touch/declaration order on success (read members simply close).

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

- the **bare form infers everything from the verbs**: environments = the verb receivers' base names, modes = any write verb (`#store`/`#delete`/`#clear`) marks a core read-write (read-only access alone marks it read-only), commit order = first-touch order.
- the **override form** forces modes/order: `@MDB_transact_span([.readWrite("calendar"), .readOnly("contacts")])` names cores by their stored property as strings (naked `.readWrite(calendar)` cannot type-check — attribute arguments are evaluated on the type level, outside instance scope).
- injected names are `tx_<core>` (e.g. `tx_calendar`) — the composition contract for handing a routed member transaction to a ``QuickLMDB/MDB_transact(_:)`` `.readWriteChild(parent:)` boundary so it merges into the member and commits with the span.
- the span requires `@MDB_app` on its containing type (gated at expansion).

**Honest ceiling:** cross-environment commits are best-effort. opening all members up front means a body throw aborts ALL of them (nothing lands), but a crash between the two adjacent commit calls can still split the pair. cross-env atomicity is impossible — the span narrows the window to the commit pair itself, it does not fake atomicity. reader-side consistency across the pair (never straddling the commit window) is a separate post-v1 primitive.
