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

/// the operation mode for the ``MDB_transact(_:environments:)`` macro.
/// - ``MDB_transact_mode/readOnly`` makes the boundary a read-only transaction boundary: it opens read transactions, never commits, and aborts every one on throw and on success (a read leaf).
/// - ``MDB_transact_mode/readWrite`` makes the boundary a read/write transaction boundary: it opens write transactions, aborts every one on throw, and COMMITS each on success.
///
/// the mode enum is the ratified pair. child/relationship composition is not a
/// mode here — Design-B joining (``MDB_transacted(_:)``) composes calls into ONE
/// transaction instead (see ``MDB_transact(_:environments:)``).
public enum MDB_transact_mode:Sendable {
	case readOnly
	case readWrite
}

/// schema assembly for an environment struct: generates a `static func open(at:mapHeadroom:)`
/// that sizes the memory map, opens the environment, and opens every `Database.X` table in
/// one setup write-transaction. the generated struct also conforms to ``MDB_environment``,
/// which is what ``MDB_transact(_:environments:)`` accepts in its `environments:` list.
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
@attached(extension, conformances: MDB_environment)
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

// - MARK: the boundary dialect (the current transaction architecture)

// the legacy transactional surface — the mode-only `@MDB_transact` (nested
// `__mdb_body` form), `@MDB_transact_span`, `@MDB_app`, and the receiver-based
// verb vocabulary — was SHED in the phase-2 removal; see the archive section
// of v16 vision.md. the boundary dialect below is the only transaction layer:
// `@MDB_transact` (attached body + peer), the `#MDB_transacted` join marker,
// and the `#MDB_entry_load` / `#MDB_entry_store` trailing verbs.

/// makes the annotated method a transaction boundary across one or more
/// `@MDB_environment` cores.
///
/// attached BODY + PEER macro. the body SCRAPES the method's body and replaces
/// it with a SHELL: opens `tx_<E> = try Transaction(env: <E>.env, readOnly: <mode>)`
/// per listed environment, calls the WRAPPED SIBLING with those transactions,
/// and closes every one — a read only boundary aborts on throw AND on success
/// (a read leaf never commits); a `.readWrite` boundary aborts on throw and
/// COMMITS on success. the peer emits the WRAPPED SIBLING: the same signature
/// plus one `tx_<E>: borrowing Transaction` parameter per environment, whose
/// body is the scraped body with the trailing verbs lowered and every
/// ``MDB_transacted(_:)`` call rewritten to join this boundary's transaction
/// (Design B — one transaction across the composed call, atomic for writes).
///
/// the mode is ``MDB_transact_mode`` — `.readOnly` and `.readWrite` are the
/// approved operating modes on this boundary. `.readWriteChild` is not a mode:
/// relationship composition is designed separately — Design-B joining already
/// composes calls into ONE transaction.
///
/// the `environments:` variadic receives environment cores by their stored
/// property names — attribute arguments are evaluated at type scope, so the
/// cores must be attribute-reachable (e.g. static stored properties).
@attached(body)
@attached(peer, names: overloaded)
public macro MDB_transact(_ mode: MDB_transact_mode, environments: any MDB_environment...) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_transact_macro")

/// the call marker for ``MDB_transact(_:environments:)``-wrapped functions
/// (Design B). inside a boundary the call is rewritten to the callee's
/// WRAPPED SIBLING, threading this boundary's transactions — the callee joins
/// the boundary (one transaction across the composed call, atomic for writes;
/// joined reads see this boundary's own uncommitted state). written anywhere
/// else, this is a compile-time diagnostic.
@freestanding(expression)
public macro MDB_transacted<T>(_ call: T) -> T = #externalMacro(module:"QuickLMDBMacros", type:"MDB_transacted_macro")

/// trailing verb: reads `key` through `database`'s environment's transaction.
/// only meaningful inside an ``MDB_transact(_:environments:)`` body, which
/// lowers it to `database.load(key:tx:)`; used elsewhere it is a compile-time
/// diagnostic.
@freestanding(expression)
public macro MDB_entry_load(_ environment: Any, database: Any, key: Any) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_entry_load_macro")

/// trailing verb: stores `value` under `key` in `database`'s environment's
/// transaction. only meaningful inside an ``MDB_transact(_:environments:)``
/// body, which lowers it to `database.store(key:value:tx:)`; used elsewhere it
/// is a compile-time diagnostic. writing on a `.readOnly` boundary's
/// transaction surfaces as the engine's access violation at runtime (the
/// read-only write lint is a later pass).
@freestanding(expression)
public macro MDB_entry_store(_ environment: Any, database: Any, key: Any, value: Any) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_entry_store_macro")

// - MARK: schema layer — table declaration

/// per-table declaration inside an ``MDB_environment(_:file:flags:maxReaders:maxDBs:mode:)``
/// core, attached to a `Database.X` stored property. the environment scan
/// consumes this attribute when it opens the tables in the setup transaction.
///
/// - Parameters:
///   - name: the LMDB table name. defaults to the property name (derived) —
///     the explicit override is for when the Swift property name is not the
///     on-disk table name you want.
///   - flags: extra ``MDB_db_flags`` the declared Swift type cannot express,
///     e.g. `.reverseKey`/`.reverseDup`, or `.dupSort`/`.dupFixed` on a raw
///     ``Database`` handle. the typed subtype (Strict/DupSort/DupFixed) and its
///     comparators come from the key/value types (``MDB_comparable``) — never
///     from this macro.
///
/// zero attributes = the default case: a bare `Database.X` property needs no
/// decoration and behaves byte-identically to today.
@attached(peer, names: arbitrary)
public macro MDB_table(name: Swift.String? = nil, flags: [QuickLMDB.MDB_db_flags] = []) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_table_macro")
