# ``QuickLMDB/Database``

A typed handle to one LMDB database (a named table) inside an ``QuickLMDB/Environment``. `Database` itself is the raw, `MDB_val`-based handle; typed variants wrap it so keys and values flow through Swift types end to end.

## Opening a Database

A ``Database`` handle is created inside a **write** transaction — creating a handle registers the database name (and any typed comparators) with the environment, which is a mutating operation:

```
// open a write transaction (mode lives in the type)
let someTransaction = try Transaction<Write>(env: someEnvironment)

// open a database named "my database". specify flags as needed.
let database = try Database(env: someEnvironment, name: "my database", flags: [.create], tx: someTransaction)

// any interactions with the database should happen here.
try someTransaction.commit()
```

When you declare your schema with ``QuickLMDB/MDB_environment(file:version:flags:maxReaders:maxDBs:mode:encryption:checksum:)``, every `Database.X` table is opened for you in the generated `open(at:)`'s setup write-transaction — no manual `Database.init(env:name:flags:tx:)` calls on the authored surface.

- ``QuickLMDB/Database/init(env:name:flags:tx:)`` — the raw handle initializer.
- ``QuickLMDB/Database/Strict`` — a typed handle where both keys and values are ``QuickLMDB/MDB_convertible`` and keys are ``QuickLMDB/MDB_comparable`` (sorted).
- ``QuickLMDB/Database/DupSort`` — a typed handle for `dupSort` tables: values share a key and are themselves sorted.
- ``QuickLMDB/Database/DupFixed`` — a typed handle for `dupFixed` tables: keys and values are both fixed-size (`RAW_staticbuff`).

## Reading and writing entries

The typed companions are protocol-extension members of ``QuickLMDB/MDB_db``, so every handle inherits them:

- ``QuickLMDB/MDB_db/load(key:tx:)`` — read a value (nil when the key is absent); mode-generic, so write transactions read too.
- ``QuickLMDB/MDB_db/store(key:value:flags:tx:)`` — write a value; requires a write transaction.
- ``QuickLMDB/MDB_db/delete(key:tx:)`` and ``QuickLMDB/MDB_db_dupsort/delete(key:value:tx:)`` — remove an entry (or an exact key/value pairing on duplicate-bearing tables); require a write transaction.
- ``QuickLMDB/MDB_db/contains(key:tx:)`` — key existence check; mode-generic.
- ``QuickLMDB/MDB_db/readCommitted(key:)`` / ``QuickLMDB/MDB_db/containsCommitted(key:)`` — self-scoped verification reads that open their own short-lived read transaction (a committed-only view, no boundary ceremony).

the raw ``Database`` handle additionally keeps the protocol's `loadEntry(key:as:tx:)` / `setEntry(...)` / `containsEntry(key:tx:)` surface for `consuming MDB_val` call sites.

## Iterating with cursors

``QuickLMDB/MDB_db/cursor(tx:_:)`` opens a cursor over the database for the duration of a trailing closure:

```
try database.cursor(tx: tx) { cursor in
    // traverse the database here
}
```

Each handle type pairs with a cursor type named the same way (`Cursor`, `Cursor.Strict<D>`, `Cursor.DupSort<D>`, `Cursor.DupFixed<D>`).

## Topics

### Database handles

- ``QuickLMDB/Database/init(env:name:flags:tx:)``
- ``QuickLMDB/Database/Strict``
- ``QuickLMDB/Database/DupSort``
- ``QuickLMDB/Database/DupFixed``

### The protocol surface

- ``QuickLMDB/MDB_db``

### Typed companions

- ``QuickLMDB/MDB_db/load(key:tx:)``
- ``QuickLMDB/MDB_db/store(key:value:flags:tx:)``
- ``QuickLMDB/MDB_db/delete(key:tx:)``
- ``QuickLMDB/MDB_db_dupsort/delete(key:value:tx:)``
- ``QuickLMDB/MDB_db/contains(key:tx:)``
- ``QuickLMDB/MDB_db/readCommitted(key:)``
- ``QuickLMDB/MDB_db/containsCommitted(key:)``
- ``QuickLMDB/MDB_db/cursor(tx:_:)``
