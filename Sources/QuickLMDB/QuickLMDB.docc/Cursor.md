#  ``QuickLMDB/Cursor``

An advanced traversal handle over a ``QuickLMDB/Database``: positional movement, duplicate-set navigation, and direct entry reads and writes. cursors are bound to the transaction they were created in.

## Creating a Cursor

A ``Cursor`` is created from a database handle through ``QuickLMDB/MDB_db/cursor(tx:_:)``, which scopes the cursor to a trailing closure:

```
// any interactions with the cursor should happen here, under an active transaction
try database.cursor(tx: thisTransaction) { cursor in
    // position, read, and write through the cursor
}
```

the cursor type is paired with the database handle type: `Database` uses ``QuickLMDB/Cursor``; the typed handles use ``QuickLMDB/Cursor/Strict``, ``QuickLMDB/Cursor/DupSort``, and ``QuickLMDB/Cursor/DupFixed``.

## Zero-copy by default

- ``QuickLMDB/Cursor`` (over a raw `Database`) returns `MDB_val` objects straight from the memory map — no copies, no decoding. you own the lifetime: those buffers are only valid while the cursor's transaction is alive.
- the typed cursors (`Strict` / `DupSort` / `DupFixed`) decode entries into the database's Swift key/value types as they are returned — the `MDB_cursor_dbtype.MDB_db_key_type` / `MDB_db_val_type` the cursor is generic over.
- cursors have an exclusive relationship with the transaction they were created in — they cannot outlive it, and they are the only way to navigate duplicate entries on `dupSort` / `dupFixed` tables.

## Looping Database Contents with Cursor

```
try database.cursor(tx: currentTransaction) { cursor in
    for entry in cursor {
        // each entry is the database's (key, value) pair type
    }
}
```

``QuickLMDB/Cursor`` and its typed variants conform to `Sequence`, and ``QuickLMDB/DatabaseIterator`` / ``QuickLMDB/DatabaseDupIterator`` back the iteration.

## Cursor operations

the `op*` member family on ``QuickLMDB/MDB_cursor`` covers the LMDB cursor operations: first/last, next/previous (including the `*Dup` / `*NoDup` traversal forms), the `get*` read forms (`opGetCurrent`, `opGetBoth`, `opGetBothRange`), the `set*` seeking forms (`opSet`, `opSetKey`, `opSetRange`), and the `*Multiple` batch forms. write operations (`setEntry(key:value:flags:tx:)`, `deleteCurrentEntry(flags:tx:)`) require a write transaction.

## Topics

### Cursor types

- ``QuickLMDB/Cursor/Strict``
- ``QuickLMDB/Cursor/DupSort``
- ``QuickLMDB/Cursor/DupFixed``

### The cursor protocol

- ``QuickLMDB/MDB_cursor``

### Iteration

- ``QuickLMDB/DatabaseIterator``
- ``QuickLMDB/DatabaseDupIterator``
- ``QuickLMDB/Cursor/makeIterator()``

### Operation vocabulary

- ``QuickLMDB/Operation``
- ``QuickLMDB/Operation/Flags``
