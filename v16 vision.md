# v16 Vision — journal

A working record of where the v16 transaction architecture landed, what it is,
what is deliberately imperfect, and what remains open. Written from the state
of the tree after the body-macro refactor.

## The architecture in one paragraph

QuickLMDB v16 organizes the transaction layer into **method boundaries** via two
macros, with **zero ambient storage** of any kind (no task-local, no
thread-local, no registry). `@MDB_transact(.readWrite | .readOnly |
.readWriteChild)` is an attached **body macro**: it rewrites the annotated
method's body in place so the method itself owns its transaction scope.
`@MDB_environment(file:flags:maxReaders:maxDBs:mode:)` is schema assembly only:
it generates `open(at:mapHeadroom:)` which sizes the memory map, opens the
environment, and opens every `Database.X` table in one setup write-transaction.
Everything underneath — `Transaction`, `MDB_db`/`MDB_cursor`, and the
`Database.X` handles — is the inherited tagged-release API, unchanged. the
`MDB_*_static` database/cursor functions and `LMDBError` were split out into
the standalone `QuickLMDBFunctionalInterop` target (a handle-level C bridge
below QuickLMDB whose public api surface is the `consuming MDB_val` layer; the
raw handle functions are module-internal, re-exported via `@_exported import`);
see "Functional-interop split" under What is settled.

## The mechanism (the one trick that makes it work)

The body macro wraps the user's body in a **local function that receives the
transaction as an explicit `borrowing` parameter**:

```swift
func publishSlot(_ key: SlotKey, _ record: SlotRecord) throws {
    let tx = try Transaction(env: self.env, readOnly: false)
    func __mdb_body(_ key: SlotKey, _ record: SlotRecord, _ tx: borrowing Transaction) throws {
        try sheets.setEntry(key: key, value: record, flags: [.noOverwrite], tx: tx)
    }
    do {
        try __mdb_body(key, record, tx)
    } catch let error {
        tx.abort()
        throw error
    }
    try tx.commit()
}
```

* Return-rewriting is **not** needed: a `return` inside the user's body returns
  from `__mdb_body`, and the outer function performs commit + return after.
  Returns inside inner closures (cursor handlers) are untouched by construction.
* No capture of the noncopyable transaction: it flows as an explicit parameter.
* The injected name `tx` is the documented contract for composing with helpers
  that take `tx: borrowing Transaction` — a boundary's transaction can be handed
  on without defeating the point.
* Any operation call that already carries an explicit `tx:` is left untouched.

## What is settled (all verified at time of writing)

- **Verification**: clean build at 0 warnings / 0 errors; 75 tests across 8
  suites green across ALL targets — runtime tests against real LMDB
  environments (atomicity, rollback, read-only enforcement, child
  commit-into-parent, child abort leaves parent usable, child sees parent's
  uncommitted writes, helper composition, cursor injection, bare dispatch
  threads), 4 strict expansion fixtures
  freezing the body-macro output, a 6-test transaction-relationship suite
  pinning engine defaults, the MDB_db (12) and MDB_cursor (10)
  protocol-extension bridge suites driven through RAW Database/Cursor handles,
  a usage-pattern demo suite, and functional-interop tests driven by raw
  CLMDB (no QuickLMDB types involved).
- **Modes**: `.readWrite` (commit once, abort exactly once on error),
  `.readOnly` (never commits, aborts on exit), `.readWriteChild` (requires a
  `parent: borrowing Transaction` parameter; child merges on commit, aborts
  independently).
- **Contract**: the annotated method must be untyped `throws`; async and
  typed-throws are diagnosed. `tx` must not collide with a parameter name.
  `.readWriteChild` requires `parent`. the wrapper mirrors the method's
  signature exactly, ownership markers included (no closure ever captures a
  `borrowing`/`consuming` parameter).
- **Transaction relationships** are the engine's own defaults, verified by
  probe and pinned by tests:
  * a `readOnly` boundary inside a `readWrite` boundary is a **sibling read** —
    its own top-level read txn, seeing the last committed state, not the
    enclosing write's uncommitted view;
  * inside another `readOnly` boundary it is a sibling read when the
    environment uses `.noTLS` (each txn owns its reader slot), else the
    engine's `badReaderSlot`;
  * a `readWrite` boundary inside a `readOnly` boundary is a **sibling write** —
    legal, commits independently, survives the enclosing read's close;
  * write-instance composition is explicit via `.readWriteChild(parent:)`;
  * a raw `.readWrite` nested inside another `.readWrite` WITHOUT `parent:` is a
    **documented forbidden pattern — lmdb DEADLOCKS** (mdb_txn_begin reuses the
    preallocated write txn and blocks on the thread's own non-recursive
    `me_wmutex`; source-verified, no guard exists).
  * multi-level write nesting is LEGAL and atomic: `top → child → grandchild`
    commits cleanly and, when the grandchild throws, NOTHING in the chain lands
    (both legs pinned by `multiLevelWriteNestingIsAtomic`). the "max 1
    child" comment in mdb.c is about one ACTIVE child per parent, not depth.
- **Ambient-free composition is a CONFIRMED DESIGN DECISION**: seamless
  cross-boundary composition via an ambient per-thread boundary stack
  (auto-parenting nested writes per the matrix) was designed, demonstrated,
  and explicitly rejected. write reuse stays explicit via
  `.readWriteChild(parent:)`; nested `.readWrite` without `parent:` remains a
  documented deadlock.
- **No ambient state of any kind**: sibling semantics removed the last reason a
  boundary tracker could exist. the macros have zero global state; every
  relationship is either a top-level open or an explicit-parameter child.
- **`@MDB_environment`**: forces `.noTLS` unconditionally (reader slots bound
  to the Transaction object — the enabler for sibling reads and the 
  thread-agnostic requirement for Swift task-based concurrency). table names
  are the property names; plain `Database` (raw MDB_val) tables are supported;
  `mapHeadroom` defaults to 1 GiB; the base directory must pre-exist.
- **Zero-copy / raw control intact**: `loadEntry(key:as:MDB_val.self, tx:)` and
  manual `Transaction(env:)` remain exactly as before — the macro layer is a
  convenience on top, never a removal.
- **Cursor-get provenance has one documented exception**: for every op EXCEPT
  `MDB_SET`, `MDB_cursor_get_entry` returns key/value pointers into LMDB-owned
  storage. `MDB_SET` leaves the key object unchanged (lmdb.h / mdb.c), so the
  returned key aliases the caller's consumed buffer — documented on the
  function and pinned by `setOpReturnsCallerKeyPointerUnchanged`, so a future
  LMDB that rewrites it surfaces loudly. the typed layer is unaffected: opSet
  returns the value only.
- **Functional-interop split**: the database + cursor `MDB_*_static` functions
  and `LMDBError` moved into a new standalone target `QuickLMDBFunctionalInterop`
  — a handle-level bridge (`MDB_dbi`, `OpaquePointer` tx/cursor handles,
  `MDB_cursor_op`, `UInt32` flags, `MDB_cmp_func_t`) that imports only CLMDB and
  sits BELOW QuickLMDB. the `MDB_*_static` implementations are module-INTERNAL;
  the target's public api surface is the `consuming MDB_val` functional layer —
  19 functions in total (11 `MDB_db_*`: get/set/contains/delete(x2)/
  delete-all/delete-database/statistics/flags/assign-compare-key/
  assign-compare-val; 8 `MDB_cursor_*`: set/delete-current/contains(x2)/
  get/dupcount/compare-keys/compare-values) — plus `MDB_cmp_func_t` and
  `LMDBError`. QuickLMDB depends on it and re-exports it via
  `@_exported import`, so `LMDBError` stays visible to consumers and macro
  expansions unchanged. every member of the main-target protocol-extension
  bridges routes through these 19 (see "Public API surface" below); behavior
  preserved and pinned by raw-CLMDB-driven tests (see
  `Tests/QuickLMDBFunctionalInteropTests/`).

## Public API surface — what ships from where

The three-target stack, as it stands after the interop split and the
protocol-extension bridge work (verified against the per-module symbol graphs):

```
QuickLMDBMacros (codegen)        QuickLMDBFunctionalInterop (the C bridge)
└─ 3 public macro impls          └─ 19 consuming-MDB_val functions
   MDB_transact (body)              MDB_db_* (11) + MDB_cursor_* (8)
   MDB_environment (schema)         MDB_cmp_func_t, LMDBError
   MDB_comparable (comparator)      └─ internal MDB_*_static inout tier
                 │ imports only CLMDB below
                 ▼
QuickLMDB (the library)
└─ handwritten core: Transaction, Environment, Database, Cursor, iterators,
   MDB_db_flags, Operation(+Flags), MDB_transact_mode, MDB_comparable proto
└─ protocol tree (11): MDB_db(_basic/_strict/_dupsort/_dupfixed),
   MDB_cursor(_basic/_strict/_dupsort/_dupfixed)
└─ protocol-extension bridges (the member-level API):
   extension MDB_db (11 ops) + extension MDB_cursor/_dupsort (cursor ops)
└─ internal macro aliases into QuickLMDBMacros (typed-handle/variant members)
└─ @_exported re-exports: QuickLMDBFunctionalInterop, CLMDB.MDB_val, RAW
   (MDB_convertible = RAW_accessible & RAW_decodable & RAW_encodable)
```

**ownership in one line each:**

| public API you see | where it actually lives |
|---|---|
| `MDB_val`, `MDB_stat`, `MDB_cursor_op`, `MDB_dbi` | CLMDB (re-exported) |
| all 19 `MDB_db_*` / `MDB_cursor_*` top-level functions | `QuickLMDBFunctionalInterop` — the main module declares NONE of them; they appear in its symbol graph because of `@_exported` |
| `LMDBError` (30 members) | `QuickLMDBFunctionalInterop` |
| `Transaction`, `Environment` (lifecycle, relationships, `.noTLS` env policy) | `QuickLMDB`, handwritten |
| every member on `Database`, `Database.Strict/DupSort/DupFixed`, `Cursor`, `Cursor.Strict/DupSort/DupFixed` (`setEntry`, `loadEntry`, `opFirst`, iterators, …) | `QuickLMDB`, `extension MDB_db` / `extension MDB_cursor` — written ONCE on the protocol, inherited by every conformer, each member body delegating to the interop function |
| the typed-handle / typed-cursor members that CANNOT be extension members (`borrowing`-typed access members, cursor inits, dup-set members) | generated per variant by the INTERNAL macros (`@MDB_db_strict_impl`, `@MDB_cursor_basics`, `@MDB_cursor_RAW_access_members`, `@MDB_cursor_dupsort`, `@MDB_cursor_dupfixed`) — declared `internal` in `QuickLMDB/Macros.swift`, implemented in the macro target |
| `@MDB_transact`, `@MDB_environment`, `@MDB_comparable` | `QuickLMDBMacros` (the only target that writes Swift that rewrites Swift) |
| `MDB_db_flags`, `Operation(+Flags)`, `DatabaseIterator`, `DatabaseDupIterator`, `MDB_transact_mode` | `QuickLMDB`, handwritten |
| `MDB_convertible` | typealias over three RAW protocols; `MDB_comparable` refines `RAW_comparable` |

**why the macro layer exists at all (the DRY rule in action):** the library's
hard rule — never write the same code twice across different variants — is
satisfied in two complementary ways, and the split between them is a Swift
compiler limitation, not a preference:

1. **extension-membership**: every operation that CAN be written once on a
   protocol is written once, in `extension MDB_db` / `extension MDB_cursor`
   family. all of `Database`, `Database.Strict`, `Database.DupSort`,
   `Database.DupFixed` (and all four cursor variants) inherit the identical
   body through the protocol tree; that body delegates to the single
   interop C-facing copy. zero duplication across the 8 db/cursor variants.
2. **macro-generation**: the members that the compiler REFUSES to accept as
   protocol-extension members — the `borrowing`-typed RAW access tier
   (`@MDB_cursor_RAW_access_members`; per the in-source comment, "when the
   same code is applied as an extension, the compiler does not allow the
   functions to be `borrowing`"), the generic cursor inits, and the
   database-strict set/delete family on typed handles — are generated per
   variant from ONE template in the macro target. the template is the single
   copy; the expansion is applied by attaching `@MDB_*` attributes to each
   variant declaration. users never see these macros; they are `internal`
   aliases in `Macros.swift`, with the public entry points being only
   `@MDB_transact` / `@MDB_environment` / `@MDB_comparable`.

the interop target is the third leg of the DRY story: it is where the raw
`consuming MDB_val` mechanics live exactly once, below BOTH the protocol
extensions and the macro templates. a future non-LMDB backend could swap
bodies behind the same 19 functions without touching the member API.

## The journey (why this shape)

1. The original ask: "design away the direct usage of transactions for every io
   operation" as the environment surface expands. The corpora showed the pain —
   pricedb ~30 `Transaction(env:)` sites, wiremand's 17-table monster.
2. Explored store/view wrappers, IO bundles, a scope engine with
   `Environment.readOnly/readWrite`. Rejected progressively: the wrapper types
   added ceremony with no correctness payoff; the protocol surface already
   carried the real guarantees (noncopyable `Transaction`, `@noasync`,
   non-escaping `cursor(tx:)`).
3. A scope registry with ambient discovery was built and verified on
   `pthread TLS`, then moved to `@TaskLocal` (more Swift-native, auto-restore).
   Two hard findings emerged:
   * `TaskLocal.withValue`'s operation is `@escaping` in the stdlib — a
     noncopyable transaction can't cross it, forcing `@escaping body` on the
     registry runner.
   * An *owning*-box class over a noncopyable is **not expressible** on this
     toolchain: classes can't move a noncopyable out of a stored property, and
     `borrowing`/`consuming` property accessors haven't shipped (the
     `get`+`_modify` escape hatch compiles and segfaults at runtime).
   The user rejected the escaping-block requirement outright.
4. The resolution: **attached body macros**. A direct probe proved the role is
   shipped (Swift 6.3.3), that it *rewrites existing bodies*, and that the
   nested-function-with-explicit-borrow formulation avoids both capturing and
   return-rewriting. Ambient storage of any kind became unnecessary — deleted
   `_MDBTransactionScope.swift` entirely.

## Known imperfections (deliberately recorded, honestly)

- **`cursor ( tx: tx)`**: calls that were trailing-closure-only get
  re-parenthesized; the serialized spacing is cosmetic and deterministic (frozen
  into a fixture) but not hand-beautiful. A candidate for later polish.
- **Call attribution is by name list** over `loadEntry/setEntry/containsEntry/
  deleteEntry/deleteAllEntries/cursor/dbStatistics/dbFlags/
  deleteDatabase`. A user function with one of these names inside a boundary
  would be rewritten. No opt-out attribute yet; the contract is documented.
  the planned verb vocabulary (`#store`/`#load`/`#delete`/`#contains`, see the
  Planned section) is the agreed principled replacement for new code.
- **Write-inside-`readOnly` is a runtime `EACCES`** from LMDB (asserted in
  tests), not a compile-time error. A body-scan lint later could diagnose it.
- **DB-level `containsEntry(key:value:)` was REMOVED, not pinned**: the value
  parameter was a silent no-op (mdb_get resolves by key only, so the pair form
  answered false-TRUE for any existing key). the pair check is now CURSOR-ONLY
  (`cursor.containsEntry(key:value:)`, which is real MDB_GET_BOTH); the DB
  level exposes key-only containment and nothing else.
- **Implicit nesting of WRITE boundaries is forbidden, by engine necessity**: a
  `.readWrite` nested inside another `.readWrite` without an explicit `parent:`
  deadlocks on LMDB's non-recursive writer mutex (source-verified; see
  "Transaction relationships" above). Composition is the explicit `.readWriteChild(parent:)`
  route, which matches pricedb's actual style. Read boundaries nest as innocent
  top-level siblings everywhere — no ambient state is involved in either.
- **Cross-environment misuse can't be caught**: injecting `tx` into a call to
  *another* environment's table would compile. Documented contract; a richer
  attribution pass could diagnose later.
- **`@MDB_environment` is optional**: nothing in the boundary macro depends on
  it. It earns its place only by being the schema-open convenience; projects
  with unusual path types (URL / bedrock.Path) keep hand-written setup.
- **Toolchain floor**: body macros require this generation of the toolchain
  (Swift 6.3 / Xcode 26 era). Consumers on older toolchains can't expand
  `@MDB_transact` (the rest of the library is unaffected).
- **Toolchain quirk recorded**: bare `throw` inside a `catch` is rejected on
  6.3.3 ("expected expression"), forcing `catch let error { … throw error }`.
- **Noncopyable-in-class restriction** means the owning-box pattern stays on the
  shelf until `borrowing`/`consuming` accessors ship — at which point the
  registry story could be revisited if macro-in-body ever feels too clever.

## Planned: the operation-verb macro vocabulary (AGREED DIRECTION — not yet implemented)

The call-site form shown above (plain `setEntry`/`loadEntry` calls during the
v16 work) is the stepping stone, not the destination. the agreed direction —
and the designated follow-on to this v16 base — makes every DB statement inside
a boundary a **freestanding verb macro**, lowered by the same `@MDB_transact`
body macro:

```swift
@MDB_transact(.readWrite)
public func recordCharge(_ acct: AccountKey, _ delta: Balance) throws {
    try #store(entries, key: acct, value: newBalance(acct, delta))
}

@MDB_transact(.readOnly)
public func currentBalance(_ acct: AccountKey) throws -> Balance? {
    try #load(entries, key: acct)
}

@MDB_transact(.readWriteChild)
public func appendEvent(_ acct: AccountKey, _ event: EventID, parent: borrowing Transaction) throws {
    try #store(events, key: acct, value: event)
}
```

The architecture of the plan:

- **`#store` / `#load` / `#delete` / `#contains` are context-consuming
  macros**: used OUTSIDE a boundary, their own expansion is a compile-time
  diagnostic (`must only appear inside an @MDB_transact body`); used INSIDE one,
  the body macro consumes the verb call and emits the tx-bearing operation call
  (`#store(t, key:, value:)` → `t.setEntry(key:, value:, flags: [], tx: tx)`,
  `#load(t, key:)` → `t.load(key:, tx: tx)`). the diagnostic is the payoff no
  method call can give: boundary-only misuse becomes a compile error, where
  today forgetting `tx:` compiles and crashes at runtime.
- **the typed handle makes the verbs type-complete with no `as:`**:
  `Database.Strict<K,V>` already carries both types statically, so companion
  methods `load(key:) -> V?`, `store(key:value:flags: = [])`, `delete(key:)`,
  `contains(key:)` (all `tx:`-bearing) are added alongside. the raw `Database`
  handle keeps `loadEntry(key:as:tx:)` for value-raw call sites.
- **UNCHANGED by the evolution**: the relationship matrix, explicit
  `.readWriteChild(parent:)`, forced `.noTLS`, the zero-ambient contract, the
  nested-write deadlock rule, raw/manual transactions, cursor closures.
- the verbs give the body macro a **principled attribution signal**,
  superseding the name-list rewrite for new code (see the call-attribution
  imperfection below).

The full inner-transaction vocabulary (one verb per tx-requiring entry point):

| tx-requiring API call             | verb form                              | phase |
|-----------------------------------|----------------------------------------|-------|
| `setEntry(key:value:flags:tx:)`   | `#store(db, key:, value:, flags: = [])` | 1    |
| `loadEntry(key:as:tx:)`           | `#load(db, key:)` · raw: `#load(db, key:, as: V.self)` | 1 |
| `containsEntry(key:tx:)`          | `#contains(db, key:)`                   | 1    |
| `cursor` pair check               | `#contains(db, key:, value:)` lowers to the CURSOR's GET_BOTH path | 1 |
| `deleteEntry(key:tx:)`            | `#delete(db, key:)`                     | 1    |
| `deleteEntry(key:value:tx:)`      | `#delete(db, key:, value:)` (dupsort)   | 1  |
| `cursor(tx:_:)`                   | `#cursor(db) { cursor in … }`           | 1    |
| `deleteAllEntries(tx:)`           | `#clear(db)`                            | 1    |
| `reserveEntry(key:reservedSize:flags:tx:_:)` | `#reserve(db, key:, size:, flags:) { buffer in … }` | 2 |
| `dbStatistics(tx:)`               | `#stats(db)` → `MDB_stat`               | 2    |
| `deleteDatabase(tx:)`             | `#drop(db)` (consumes the handle)       | 3    |
| `dbFlags(tx:)`                    | skipped — flags are compile-time on typed handles | — |

(deliberately ABSENT: `reserveEntry`/`MDB_RESERVE` — write-without-initialize
support was dropped outright; the reserve footguns (uninitialized stores,
caller-buffer provenance on the returning set path) outweighed the memcpy
savings, so there is no `#reserve` verb and no returning-set surface.)

deliberately NOT verb candidates: cursor OPERATIONS (`opSet`/`opNext`/dup ops/
`deleteCurrentEntry` — cursor-bound, tx-free), `makeDupIterator`,
`dbName`/`dbHandle`/`dbEnvironment` (tx-free metadata), `Environment.sync`/
`readerCheck`, and the `Transaction` lifecycle (`commit`/`abort`/`reset`/`renew`
belong to the boundary itself). `#cursor` keeps its trailing-closure,
non-escaping form; the body macro lowers it exactly as it lowers
`cursor(tx:)` today (already in the attribution name list).

Implementing this is the top backlog item; picky details (exact lowering,
naming, expansion fixtures) are deferred until then.

## Backlog / next candidates

- **AGREED NEXT DIRECTION — the operation-verb macro vocabulary**:
  implement the phase-1 verbs `#store` / `#load` / `#delete` / `#contains` /
  `#cursor` / `#clear` as context-consuming verb macros (plus `#stats` /
  `#drop` in later phases — see the Planned section table), the
  `@MDB_transact` body-macro lowering, the typed-handle companions
  (`load(key:)`, `store(key:value:flags: = [])`, `delete(key:)`,
  `contains(key:)`), the outside-a-boundary diagnostic, and strict expansion
  fixtures for the verbs inside all three boundary modes.
- Expansion polish (the `cursor ( tx:)` spacing; parameter trivia).
- Call-attribution opt-out + cross-env diagnostic.
- `.readOnly` write lint (macro-level body scan).
- DocC for the two macros and the transaction-boundary article (docc catalog
  currently carries a prose section; symbol docs for the macros pending).
- Downstream canaries: migrate pricedb / wiremand / ascension slices to the
  macro layer as the migration corpus; verify the injected-`tx` helper story
  against their actual composable helpers.
- Decide the release vehicle and consumer-facing macro product packaging.
- Revisit the owning-box pattern when the toolchain grows consuming accessors.
