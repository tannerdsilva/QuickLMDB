# ``QuickLMDBFunctionalInterop``

The C bridge over raw LMDB handles. This module imports only CLMDB and contains
the handle-level functional surface: `throws(LMDBError)` operations that take
`consuming MDB_val` arguments and raw handles (`OpaquePointer`,
`MDB_dbi`). it is re-exported by the `QuickLMDB` module via
`@_exported import`, so `LMDBError` and every function here are available
wherever QuickLMDB is.

the handle-level `MDB_*_static` implementations behind these functions are
module-internal; this public surface is the supported bridge.
`LMDBError` carries the full LMDB return-code space as typed cases.

## Topics

### Database operations

- ``MDB_db_get_entry(db:key:tx:)``
- ``MDB_db_set_entry(db:key:value:flags:tx:)``
- ``MDB_db_contains_entry(db:key:tx:)``
- ``MDB_db_delete_entry(db:key:tx:)``
- ``MDB_db_delete_entry(db:key:value:tx:)``
- ``MDB_db_delete_all_entries(db:tx:)``
- ``MDB_db_delete_database(db:tx:)``
- ``MDB_db_get_statistics(db:tx:)``
- ``MDB_db_get_flags(db:tx:)``
- ``MDB_db_assign_compare_key(db:compare:tx:)``
- ``MDB_db_assign_compare_val(db:compare:tx:)``

### Cursor operations

- ``MDB_cursor_set_entry(cursor:key:value:flags:)``
- ``MDB_cursor_delete_current_entry(cursor:flags:)``
- ``MDB_cursor_contains_entry(cursor:key:)``
- ``MDB_cursor_contains_entry(cursor:key:value:)``
- ``MDB_cursor_get_entry(cursor:op:key:value:)``
- ``MDB_cursor_get_dupcount(cursor:)``
- ``MDB_cursor_compare_keys(tx:db:lhs:rhs:)``
- ``MDB_cursor_compare_values(tx:db:lhs:rhs:)``

### Types

- ``LMDBError``
- ``MDB_cmp_func_t``
