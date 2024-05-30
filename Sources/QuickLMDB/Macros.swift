import QuickLMDBMacros

@attached(member,		names:			named(MDB_compare_f))
@attached(extension,	conformances:	MDB_comparable)
public macro MDB_comparable() = #externalMacro(module:"QuickLMDBMacros", type:"MDB_comparable_macro")

@attached(member,		names:			named(compareEntryValues(_:_:)),
										named(compareEntryKeys(_:_:)),
										named(containsEntry(key:)),
										named(opSetRange(returning:key:)),
										named(opSet(returning:key:)),
										named(opGetCurrent(returning:)),
										named(opGetBoth(returning:key:value:)),
										named(opGetBothRange(returning:key:value:)),
										named(opSetKey(returning:key:)),
										named(setEntry(key:value:flags:)),
										named(containsEntry(key:value:)))
internal macro MDB_cursor_RAW_access_members() = #externalMacro(module:"QuickLMDBMacros", type:"_QUICKLMDB_INTERNAL_cursor_encodable_impl")

@attached(member,		names:			arbitrary)
internal macro MDB_cursor_basics() = #externalMacro(module:"QuickLMDBMacros", type:"_QUICKLMDB_INTERNAL_cursor_init_basics_impl")

@attached(member, names:				named(setEntry(key:value:flags:tx:)),
										named(deleteEntry(key:value:tx:)),
										named(deleteEntry(key:tx:)),
										named(loadEntry(key:as:tx:)),
										named(containsEntry(key:value:tx:)),
										named(containsEntry(key:tx:)))
internal macro MDB_db_strict_impl() = #externalMacro(module:"QuickLMDBMacros", type:"_QUICKLMDB_INTERNAL_database_strict_impl")

/// applies member implementations for the dupsort-based cursor functions.
@attached(member,		names:			named(opGetMultiple(returning:key:)),
										named(opNextMultiple(returning:key:)))
internal macro MDB_cursor_dupfixed() = #externalMacro(module:"QuickLMDBMacros", type:"_QUICKLMDB_INTERNAL_cursor_dupfixed_impl")

@attached(member,		names:			named(opGetBoth(returning:key:value:)),
										named(opGetBothRange(returning:key:value:)),
										named(opFirstDup(returning:)),
										named(opLastDup(returning:)),
										named(opNextNoDup(returning:)),
										named(opNextDup(returning:)),
										named(opPreviousDup(returning:)),
										named(opPreviousNoDup(returning:)))
internal macro MDB_cursor_dupsort() = #externalMacro(module:"QuickLMDBMacros", type:"_QUICKLMDB_INTERNAL_cursor_dupsort_impl")