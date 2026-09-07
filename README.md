# QuickLMDB

QuickLMDB is designed to be a easy, efficient, and uncompromising integration of the LMDB library. QuickLMDB does not hide access to the underlying LMDB core, allowing you to directly utilize the core LMDB API at any time. Likewise, QuickLMDB makes it very easy to write high-level code that is simultaneously memory-safe and high-performance. 

- QuickLMDB is the only known Swift library to allow full transactional control over an Environment. This is crucial to achieving high performance.

- QuickLMDB allows direct access to the LMDB memorymap without overhead or copies. This is also a unique feature for Swift-based LMDB wrappers.

## Transaction boundaries with macros

QuickLMDB ships two macros that organize the transaction layer into method boundaries, with no ambient state of any kind (no task-local, no thread-local, no registry):

- `@MDB_transact(.readWrite | .readOnly | .readWriteChild)` — an attached **body macro**. It rewrites the annotated method's body in place: the method itself owns its transaction scope. Operation call sites inside the body may omit the `tx:` argument (the expansion injects the boundary transaction), and the scope commits exactly once on success / aborts exactly once on error.

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
}
```

- `@MDB_environment(file:flags:maxReaders:maxDBs:mode:)` — schema assembly: generates `static func open(at:mapHeadroom:)` which sizes the memory map, opens the environment, and opens every `Database.X` table in one setup write-transaction.

Both macros expand to plain calls through the existing public API (`Environment`, `Transaction`, `Database.*`, `loadEntry(key:as:tx:)`, `setEntry(key:value:flags:tx:)`, `cursor(tx:_:)`). The raw bridge that backs these calls — the database/cursor `MDB_*_static` functions and `LMDBError` — lives in the standalone `QuickLMDBFunctionalInterop` product: a handle-level C layer (`MDB_dbi`, raw pointer handles) with no QuickLMDB types, re-exported by QuickLMDB. The C wrapper layer itself (CLMDB) is untouched.

**Planned evolution (agreed direction, not yet shipped):** DB statements inside boundaries are slated to become freestanding verb macros — `#store`, `#load`, `#delete`, `#contains` — lowered by `@MDB_transact` into the same tx-bearing calls shown above, with a compile-time diagnostic when a verb appears outside a boundary. The typed `Database.Strict<K,V>` handle already carries both key and value types statically, so the verbs need no `as:` and no `flags: []`. The relationship matrix, `.readWriteChild(parent:)`, forced `.noTLS`, and the zero-ambient contract are all unaffected by this evolution.

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
