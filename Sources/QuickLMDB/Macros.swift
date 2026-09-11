import SystemPackage
import CLMDB

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
									named(setEntry(key:value:flags:tx:)),
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
///   - version: the schema version, ENGAGED ONLY WHEN WRITTEN. a bare core
///     keeps its exact `file:` name; writing `version:` derives the on-disk
///     name `<stem>-v<N>.mdb` (so `version: 0` gives `-v0`). bumping the
///     version ships a FRESH file — the migration convention is new file +
///     stream, never in-place (old data stays untouched and readable by older
///     binaries; no sentinel table).
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
public macro MDB_environment(file: Swift.String, version: Swift.UInt = 0, flags: [QuickLMDB.Environment.Flags] = [.noSubDir], maxReaders: Swift.UInt32 = 32, maxDBs: Swift.UInt32 = 8, mode: [SystemPackage.FilePermissions] = [.ownerReadWriteExecute, .groupRead, .otherRead]) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_environment_macro")

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

// - MARK: the boundary dialect (the only transaction architecture)

// every environment is its own TYPE (an @MDB_environment core). the
// transaction layer is invisible on the user's surface: @MDB_transact turns
// an INSTANCE method into a transactional unit whose transactions are opened
// and closed for it; the typed verb family (#store/#load/#delete/#contains/
// #cursor/#clear/#stats/#drop) is the database-operation vocabulary inside a
// boundary (environment by `E.Type`, table by `KeyPath<E, Database>`);
// #MDB_transacted is the join marker. the authored signature carries no
// transaction parameters, and the tx labels (`tx_<E>`) are implementation
// detail of the generated shell/sibling pair.

/// makes the annotated INSTANCE method a transaction boundary.
///
/// the environment set is INFERRED from the typed verb calls in the body:
/// every environment type referenced by a verb must be `self` (the boundary
/// is attached to an ``MDB_environment`` core type) or a parameter declared
/// with that exact type. the method's authored signature carries no
/// transaction parameters at all.
///
/// attached BODY + PEER. the body macro replaces the method with a SHELL that
/// opens `Transaction<Read/Write>(env:)` on each inferred environment, calls
/// the peer-generated SIBLING with those transactions, and closes every one —
/// `.readOnly` aborts on throw AND on success (a read leaf never commits);
/// `.readWrite` aborts on throw and COMMITS on success. the peer emits the
/// SIBLING: the same signature plus one `tx_<E>: borrowing Transaction<…>`
/// parameter per environment, whose body is the authored body with the typed
/// verbs lowered to the tx-bearing operations and every
/// ``MDB_transacted(_:)`` join marker rewritten to pass THIS boundary's
/// transactions (Design B — one transaction across the composed call, atomic
/// for writes; joined reads see this boundary's own uncommitted state).
///
/// the method must be `throws` (the boundary can fail to open, commit, or
/// abort), must not be `async`, and must be an instance method.
///
/// calling the method is a ROOT-scoped unit entry (it opens its own fresh
/// transactions per the declared mode and commits-or-aborts alone).
///
/// THE JOIN / SIBLING ASYMMETRY — read this once:
/// - a bare call to a `.readOnly` boundary inside a boundary is a SIBLING
///   read: its own shell opens a fresh READ transaction and sees the last
///   committed state. deliberate, safe.
/// - a bare call to a `.readWrite` boundary inside a boundary ROOT-SCOPES a
///   SECOND WRITE transaction — which BLOCKS on LMDB's per-environment
///   writer mutex until the outer boundary commits, and the outer boundary
///   cannot commit while the inner blocks: a DEADLOCK, not an error.
///   composition is spelled ``MDB_transacted(_:)`` — always.
///
/// the mode is ``MDB_transact_mode`` — `.readOnly` (never commits) and
/// `.readWrite` (commits on success). `.readWriteChild` is not a mode:
/// Design-B joining already composes calls into ONE transaction.
@attached(body)
@attached(peer, names: overloaded)
public macro MDB_transact(_ mode: MDB_transact_mode) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_transact_macro")

/// the call marker for ``MDB_transact(_:)``-wrapped functions (Design B).
/// inside a boundary the call is rewritten onto the callee's SIBLING,
/// threading this boundary's transactions — the callee joins the boundary
/// (one transaction across the composed call, atomic for writes; joined reads
/// see this boundary's own uncommitted state). the callee must reference the
/// SAME environment-type set — the equal-env-set contract, enforced by the
/// rewrite's labels. written anywhere else, this is a compile-time
/// diagnostic.
@freestanding(expression)
public macro MDB_transacted<T>(_ call: T) -> T = #externalMacro(module:"QuickLMDBMacros", type:"MDB_transacted_macro")

// - MARK: the typed verb vocabulary (database operations inside a boundary)

// the freestanding verbs are the exact operations, typed end to end: the
// first argument is the environment TYPE (`E.self`), the `database:` is a
// ``KeyPath`` to a `Database.X` handle on that type, and key/value/returns
// are bound through the handle's own generic types. inside an
// ``MDB_transact(_:)`` body the boundary consumes and lowers these to the
// tx-bearing operations; anywhere else they are compile-time diagnostics.
// LIFETIME: on a raw `Database` (MDB_val) handle, `#load`/`#cursor` return
// ZERO-COPY views into the memory map, valid only until the boundary's
// transactions close — use typed handles (Strict/DupSort/DupFixed), which
// decode immediately.

/// stores `value` under `key` in the table `database` of environment `env`.
@freestanding(expression)
public macro store<E: MDB_environment, DB: MDB_db>(_ env: E.Type, database: KeyPath<E, DB>, key: DB.MDB_db_key_type, value: DB.MDB_db_val_type, flags: QuickLMDB.Operation.Flags = []) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// loads the value for `key` from the table `database` of environment `env`;
/// a missing key yields nil.
@freestanding(expression)
public macro load<E: MDB_environment, DB: MDB_db>(_ env: E.Type, database: KeyPath<E, DB>, key: DB.MDB_db_key_type) -> DB.MDB_db_val_type? = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// deletes the entry for `key` (or the exact `key`/`value` pairing on
/// duplicate-bearing tables) from the table `database` of environment `env`.
@freestanding(expression)
public macro delete<E: MDB_environment, DB: MDB_db>(_ env: E.Type, database: KeyPath<E, DB>, key: DB.MDB_db_key_type) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")
@freestanding(expression)
public macro delete<E: MDB_environment, DB: MDB_db>(_ env: E.Type, database: KeyPath<E, DB>, key: DB.MDB_db_key_type, value: DB.MDB_db_val_type) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// checks whether `key` exists in the table `database` of environment `env`.
@freestanding(expression)
public macro contains<E: MDB_environment, DB: MDB_db>(_ env: E.Type, database: KeyPath<E, DB>, key: DB.MDB_db_key_type) -> Bool = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// opens a cursor over the table `database` of environment `env` for the
/// duration of the trailing closure.
@freestanding(expression)
public macro cursor<E: MDB_environment, DB: MDB_db, R>(_ env: E.Type, database: KeyPath<E, DB>, _ body: (DB.MDB_db_cursor_type) throws -> R) -> R = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// removes every entry from the table `database` of environment `env`.
@freestanding(expression)
public macro clear<E: MDB_environment, DB: MDB_db>(_ env: E.Type, database: KeyPath<E, DB>) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// returns the statistics for the table `database` of environment `env`.
@freestanding(expression)
public macro stats<E: MDB_environment, DB: MDB_db>(_ env: E.Type, database: KeyPath<E, DB>) -> MDB_stat = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

/// deletes the table `database` and all of its contents from environment
/// `env`. `deleteDatabase` CONSUMES the handle — `instance[keyPath: …]`
/// yields a copy, so dropping a STORED table PERMANENTLY POISONS the stored
/// property (its DBI closes under it; later operations on it throw
/// ``LMDBError/badTransaction``). treat a dropped stored table as dead.
@freestanding(expression)
public macro drop<E: MDB_environment, DB: MDB_db>(_ env: E.Type, database: KeyPath<E, DB>) = #externalMacro(module:"QuickLMDBMacros", type:"MDB_verb_error_macro")

// - MARK: schema layer — the arrangement (MDB_layout)

/// marks a struct as an ENVIRONMENT ARRANGEMENT: it owns N ``MDB_environment``
/// cores as stored instance properties and gets a single
/// `open(at:mapHeadroom:)` (each core opens at `<basePath>/<property name>`,
/// path-stemming) plus a `mdb_core_names` inventory. every environment is its
/// own type and transaction boundaries live ON those types; the layout is
/// purely the multi-environment initialization and arrangement story.
///
/// generated members:
/// - `static func open(at:mapHeadroom:) throws -> Self` — opens every core and
///   assembles a fresh instance.
/// - `static let mdb_core_names: [String]` — the core inventory, declaration
///   order (for docs/tooling).
///
/// no per-core factories, no static singletons, no baked base path.
@attached(member, names: named(open(at:mapHeadroom:)), named(mdb_core_names))
public macro MDB_layout() = #externalMacro(module:"QuickLMDBMacros", type:"MDB_layout_macro")

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
