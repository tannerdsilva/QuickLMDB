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
3. appends `tx: tx` to every QuickLMDB operation call in the body that omits the `tx:` argument,
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
        try sheets.setEntry(key: key, value: record, flags: [])   // tx: omitted
    }

    @MDB_transact(.readOnly)
    public func nearestSlot(to date: SlotKey) throws -> SlotRecord? {
        var found: SlotRecord? = nil
        try sheets.cursor { cursor in                              // tx: omitted
            if let first = try? cursor.opSetRange(key: date).value {
                found = first
            }
        }
        return found
    }
}
```

The injected name `tx` is also the documented way to hand a boundary transaction to a shared helper that takes `tx: borrowing Transaction` (e.g. `try applyDeltas(item, tx: tx)`). composable helpers that take an existing transaction keep their explicit `tx:` parameter and can be called from inside a boundary using the injected name. `.readWriteChild` requires a parent transaction parameter: `func commitBatch(_ items: [Item], parent: borrowing Transaction) throws`.

The annotated method must be `throws` (the boundary can fail to open or commit) and must not be `async`; operation calls that already carry an explicit `tx:` argument are left untouched.

### ``QuickLMDB/MDB_environment(file:flags:maxReaders:maxDBs:mode:)`` — schema assembly

Generates a `static func open(at:mapHeadroom:)` that sizes the memory map as current file size plus headroom, opens the environment with the macro-declared flags, and opens every `Database.X` table in one setup write-transaction. Table names are derived from the property names. The struct must store exactly `env` plus `Database.X` tables (plain `Database` raw tables are supported).

Both macros expand to plain calls through the existing public API — `Environment`, `Transaction`, `Database.*`, `loadEntry(key:as:tx:)`, `setEntry(key:value:flags:tx:)`, `cursor(tx:_:)`. the raw bridge that backs these calls — the database/cursor `MDB_*_static` functions and `LMDBError` — lives in the standalone `QuickLMDBFunctionalInterop` product: a handle-level C layer (`MDB_dbi`, raw pointer handles) with no QuickLMDB types, re-exported by QuickLMDB. the C wrapper layer itself (CLMDB) is untouched.

**Planned evolution (agreed direction, not yet shipped):** DB statements inside boundaries are slated to become freestanding verb macros — `#store`, `#load`, `#delete`, `#contains` — lowered by `@MDB_transact` into the same tx-bearing calls shown above, with a compile-time diagnostic when a verb appears outside a boundary. The typed `Database.Strict<K,V>` handle already carries both key and value types statically, so the verbs need no `as:` and no `flags: []`. The relationship matrix, `.readWriteChild(parent:)`, forced `.noTLS`, and the zero-ambient contract are all unaffected by this evolution.
