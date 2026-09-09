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
/// one setup write-transaction (table names are derived from the property names). the
/// generated struct also conforms to ``MDB_environment`` (marking it as an environment core
/// for ``MDB_app`` containers).
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

// - MARK: verb vocabulary (freestanding expression macros)

// the verb macros are the marker-gated call surface inside transaction
// boundaries. each boundary macro (MDB_transact, and the later span boundary)
// CONSUMES the verb calls in the body and lowers them to the tx-bearing
// operation call; this standalone declaration is the fallback for use OUTSIDE
// a boundary, where the shared implementation always emits a diagnostic.
// the boundary macro expands before these standalone expansions, so inside a
// boundary the fallback is never reachable by construction (see
// swift-macro-development references/verb-macro-consumption-architecture.md).

/// stores `value` under `key` in `db`. only meaningful inside a transaction
/// boundary (``MDB_transact``); used elsewhere this is a compile-time error.
@freestanding(expression)
public macro store(_ db: Any, key: Any, value: Any, flags: QuickLMDB.Operation.Flags = []) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// loads the value for `key` from `db`. typed handles infer the value type;
/// raw ``MDB_val`` handles pass `as:` for the value type.
/// only meaningful inside a transaction boundary; used elsewhere this is a
/// compile-time error.
@freestanding(expression)
public macro load(_ db: Any, key: Any) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

@freestanding(expression)
public macro load(_ db: Any, key: Any, as: Any.Type) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// deletes the entry for `key` (or the exact `key`/`value` pairing on
/// duplicate-bearing databases). only meaningful inside a transaction
/// boundary; used elsewhere this is a compile-time error.
@freestanding(expression)
public macro delete(_ db: Any, key: Any) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

@freestanding(expression)
public macro delete(_ db: Any, key: Any, value: Any) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// checks whether `key` (or the exact `key`/`value` pairing, lowered to the
/// cursor GET_BOTH path) exists in `db`. only meaningful inside a transaction
/// boundary; used elsewhere this is a compile-time error.
@freestanding(expression)
public macro contains(_ db: Any, key: Any) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

@freestanding(expression)
public macro contains(_ db: Any, key: Any, value: Any) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// opens a cursor over `db` for the duration of the trailing closure. only
/// meaningful inside a transaction boundary; used elsewhere this is a
/// compile-time error.
@freestanding(expression)
public macro cursor(_ db: Any, _ body: (Any) -> Any) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// removes every entry from `db`. only meaningful inside a transaction
/// boundary; used elsewhere this is a compile-time error.
@freestanding(expression)
public macro clear(_ db: Any) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// marks a struct as an environment CONTAINER: its stored `@MDB_environment` cores
/// become the environment inventory that ``MDB_transact_span(_:)`` routes to.
/// generates the `MDB_environment_container` conformance plus the
/// `mdb_environment_property_names` inventory from the stored properties.
@attached(member, names: named(mdb_environment_property_names))
@attached(extension, conformances: MDB_environment_container)
public macro MDB_app() = #externalMacro(module:"QuickLMDBMacros", type:"MDB_app_macro")

/// per-core mode override for ``MDB_transact_span(_:)``. only used when the bare
/// inference forms are not what you want — forcing a mode or pinning commit order.
///
/// the core is named by its STORED PROPERTY name as a string: `.readWrite("calendar")`.
/// (a naked `.readWrite(calendar)` cannot type-check: attribute arguments are
/// evaluated on the type level, where instance stored properties are not in scope.)
public enum MDB_span_member {
	/// this environment core participates as a read/write member (commits with the span).
	case readWrite(String)
	/// this environment core participates as a read-only member (never commits; aborts on close).
	case readOnly(String)
}

/// makes the annotated method a transaction boundary across MULTIPLE `@MDB_environment`
/// cores (an `@MDB_app` container). one top-level transaction per participating core
/// is opened up front; a thrown body aborts ALL of them; on success the write members
/// commit back-to-back in first-touch (or declaration) order while read-only members
/// just close. cross-environment commits are best-effort (LMDB commits are
/// per-environment); the span narrows the window to the adjacent commit calls.
///
/// BARE form: `@MDB_transact_span` infers the participating cores, their modes, and
/// their commit order from the freestanding verb calls in the body — receiver base
/// names are the cores; any write verb (`#store`/`#delete`/`#clear`) marks a core
/// read-write; read-only access alone marks it read-only.
///
/// OVERRIDE form: `@MDB_transact_span([.readWrite("calendar"), .readOnly("contacts")])`
/// forces modes and order explicitly. cores are named by their stored property
/// names as strings (naked `.readWrite(calendar)` cannot type-check — attribute
/// arguments are evaluated on the type level, outside instance scope).
///
/// injected names are `tx_<core>` (e.g. `tx_calendar`) — the documented composition
/// contract for handing a routed member transaction to a `.readWriteChild(parent:)`
/// boundary. same marker-gated verb lowering as ``MDB_transact(_:)``: only the
/// freestanding verbs are rewritten; every other line is byte-identical.
@attached(body)
public macro MDB_transact_span(_ members: [MDB_span_member]? = nil) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_transact_span_macro")