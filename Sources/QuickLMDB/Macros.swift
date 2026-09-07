import SystemPackage

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

/// the transaction mode for the ``MDB_transact(_:)`` macro.
/// - ``MDB_transact_mode/readWrite`` makes the method a read/write transaction boundary: the body commits once on success and aborts exactly once if any operation throws.
/// - ``MDB_transact_mode/readOnly`` makes the method a read-only transaction boundary: the transaction aborts on exit and never commits.
/// - ``MDB_transact_mode/readWriteChild`` makes the method a child transaction of a `parent: borrowing Transaction` parameter on the method; committing the child merges it into the parent.
public enum MDB_transact_mode:Sendable {
	case readWrite
	case readOnly
	case readWriteChild
}

/// makes the annotated method a transaction boundary.
///
/// this is an attached *body* macro: it rewrites the method's body in place so that the
/// method itself owns its transaction scope, with no task-local or thread-local storage
/// of any kind. call sites of QuickLMDB operations inside the body may omit the `tx:`
/// argument — the expansion appends `tx: tx`, where `tx` is the boundary transaction that
/// the expansion injects as a `let`. the same name can be passed on to helper functions
/// that take `tx: borrowing Transaction`.
///
/// the annotated method must be `throws` (the boundary can fail to open or commit) and
/// must not be `async`. `.readWriteChild` requires a `parent: borrowing Transaction`
/// parameter. operation call sites that already carry an explicit `tx:` argument are left
/// untouched.
@attached(body)
public macro MDB_transact(_ mode:MDB_transact_mode) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_transact_macro")

/// schema assembly for an environment struct: generates a `static func open(at:mapHeadroom:)`
/// that sizes the memory map, opens the environment, and opens every `Database.X` table in
/// one setup write-transaction (table names are derived from the property names).
///
/// - Parameters:
///   - file: the name of the environment file (appended to the base path).
///   - flags: environment flags, e.g. `[.noSubDir, .noReadAhead]`. `.noTLS` is always
///     forced on regardless of this argument — QuickLMDB relies on per-transaction
///     reader slots (thread-agnostic for Swift concurrency, and the enabler for
///     sibling read transactions inside boundaries).
///   - maxReaders: maximum reader slots for the environment.
///   - maxDBs: maximum named databases for the environment.
///   - mode: file permissions used when creating the environment file.
///
/// the struct must store exactly an `env: Environment` property plus `Database.X` tables.
@attached(member, names: arbitrary)
public macro MDB_environment(file: Swift.String, flags: [QuickLMDB.Environment.Flags] = [.noSubDir], maxReaders: Swift.UInt32 = 32, maxDBs: Swift.UInt32 = 8, mode: [SystemPackage.FilePermissions] = [.ownerReadWriteExecute, .groupRead, .otherRead]) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_environment_macro")

@attached(member, names:			named(setEntry(key:value:flags:tx:)),
									named(deleteEntry(key:value:tx:)),
									named(deleteEntry(key:tx:)),
									named(loadEntry(key:as:tx:)),
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