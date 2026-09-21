# 16.0.0 (upcoming — the next tag and release)

NOTE ON HISTORY: the changelog previously carried `16.0.0`/`16.1.0` entries
describing INTERMEDIATE working versions (`@MDB_app`/`@MDB_transact_span`, the
`environments:` attribute form, the `.readWriteChild` mode) that were never
tagged or released. their surface is superseded by the typed-environment
architecture documented below and is NOT in this release; those draft sections
are removed so the version history matches what actually ships (the prior
tagged release is 15.0.0).

- **LMDB 1.0 encryption + checksums through the macro layer** (breaking — new
  engine + new surface). QuickLMDB now builds against CLMDB's LMDB 1.0.2 line
  (branch pin `master`; the 1.0 tag has not been cut yet — tighten the range
  once CLMDB 1.0.x is tagged), which is the only engine with `mdb_env_set_encrypt`,
  per-page checksums, and authenticated encryption. the lift of the hacklash
  `MDB_crypto_impl` / `MDB_checksum_impl` design:
  - `MDB_crypto_impl` / `ChaChaPoly` — public protocol + a ChaCha20-Poly1305
    AEAD conformer (rawdog `RAW_chachapoly`); `MDB_checksum_impl` / `Blake2` —
    an 8-byte keyed/keyless BLAKE2b per-page checksum conformer (rawdog
    `RAW_blake2`).
  - `Environment.EncryptionConfiguration` + `Environment.init(..., encrypt:,
    checksum:)` — registers the callbacks before `mdb_env_open`; the stored
    `flags` reflect `.encrypt` / `.remapChunks` (which `mdb_env_set_encrypt`
    sets internally — they must NOT be passed in the open flags). new 1.0
    `Flags` cases: `.encrypt`, `.remapChunks`, `.previousSnapshot`.
  - `LMDBError.badChecksum` / `.cryptoFail` (the 1.0 `MDB_BAD_CHECKSUM` /
    `MDB_CRYPTO_FAIL` codes).
  - `@MDB_environment(..., encryption: ChaChaPoly.self, checksum: Blake2.self)`
    (breaking — new optional attribute args). an environment that declares
    `encryption:` gets a generated `open(at:mapHeadroom:encryptionKey:)` whose
    `encryptionKey: [UInt8]` parameter is REQUIRED — an encrypted env cannot be
    opened keyless, enforced at compile time. checksum-only envs keep the plain
    `open(at:mapHeadroom:)` signature. unencrypted environments expand
    byte-identically to before.
  - `@MDB_layout` does not thread per-env keys (it cannot statically see the
    env types' attributes) — encrypted envs inside a layout remain a documented
    residual; author a hand-rolled arrangement open for those.
  - LMDB 1.0 nested-txn semantics differ from 0.9: read-only children of a
    write parent are now LEGAL (arbitrarily many; 0.9 pinned `MDB_BAD_TXN`). the
    raw interop probe (`NestedTxnSemanticsProbe`) was re-pinned to the 1.0
    contract. QuickLMDB's own composition never spawns read children, so the
    `.readOnly` boundary stays a composition leaf by construction.
  - on-disk format is now LMDB format v3 — **existing 0.9-format data files
    will not reopen**; migrate via 0.9 `mdb_dump` → 1.0 `mdb_load`.

- **read-twin redirect + committed-read doctrine** (generated-surface + API
  refinement). a READ boundary's `_child` variant is now a THIN REDIRECT to
  its flat sibling (a joined read threads the caller's transaction; LMDB has
  no read-only children — pinned `MDB_BAD_TXN` — so reads never spawn a child
  and a `.readOnly` boundary is a composition LEAF). the demo and docs teach
  committed-only validation via the verb-less `readCommitted(key:)` instead
  of a bare boundary call at depth. the invariance itself (children are
  ALWAYS write-capable; one active child per parent; parent-quiescent while a
  child is active) is pinned by a raw interop probe and stated positively in
  the engine + macro docs.

- **`#MDB_transacted(...)` composes by CHILD TRANSACTION** (breaking, Design B
  re-lift). a joined call runs in a child transaction of the caller's current
  tx per environment — it sees the caller's uncommitted state; on success it
  FOLDS into the caller (nothing durable until the caller commits); on failure
  it aborts ONLY the child — a catching caller keeps its prior writes
  (selective rollback); an uncaught join failure still aborts the whole
  boundary (atomicity preserved). joins nest as child-of-child at arbitrary
  depth; multi-environment joins spawn one child per environment. the channel
  is the peer'd `<name>_child` sibling (`@attached(peer, names: overloaded,
  suffixed(_child))`), with the body run INLINE and authored `return`s
  re-pointed to a labeled exit so every path closes the child before the
  boundary returns. bare same-env write-in-write stays a compile-time error
  pointing at the marker (see the lint entry). breaking only for code that
  observes composed-write failure granularity from inside a `catch`.
- **`Transaction<Write>.init(env:parent:)`** (engine API): opens a CHILD
  transaction of a WRITE parent on the same environment — sees the parent's
  uncommitted writes; `commit()` folds into the parent (not durable until the
  parent commits); `abort()` discards only the child. the underlying LMDB
  build does not guard close-order, so closing every child before its parent
  is a caller contract (the macro's `_child` variants enforce it by
  construction).

- **write-composition lint** (hardening): `@MDB_environment` emits a
  compile-time error when a boundary body bare-calls a same-type
  `@MDB_transact(.readWrite)` boundary — the spell that opens a SECOND root
  write on a live writer and deadlocks LMDB's writer mutex.
  `#MDB_transacted(...)` joins, sibling reads, cross-environment callees
  (typed parameters) and plain methods are unaffected. breaking only for code
  that previously relied on accidental write composition inside a boundary.

- **the transaction layer is now the typed-environment dialect** (breaking).
  every environment is its own `@MDB_environment` type, and transaction
  boundaries are INSTANCE methods on those types. there is no transaction
  vocabulary on the authored surface:
  - `@MDB_transact(_ mode: MDB_transact_mode)` — attached body + peer on an
    instance method. `.readOnly` aborts on throw and on success (a read leaf
    never commits); `.readWrite` aborts on throw and COMMITS on success. the
    environment set is INFERRED from the typed verb calls in the body: every
    environment a verb references must be `self` or a typed parameter of the
    method. the method becomes a shell (opens/closes its own transactions);
    the peer emits an INVISIBLE sibling that carries `tx_<E>: borrowing
    Transaction<…>` per environment (read-only siblings are mode-generic so
    write boundaries can join reads). the method must be `throws`, not
    `async`, and instance. a boundary whose body references no environment is
    a diagnostic.
  - **the typed verb family** — `#store`, `#load`, `#delete`,
    `#contains`, `#cursor`, `#clear`, `#stats`, `#drop` — the database
    operations, typed end to end: `#store(E.self, database: \.table,
    key:…, value:…)` where `E` is the environment type, `database:` is a
    `KeyPath<E, Database…>`, and key/value/return types bind through the
    table's own generics. inside a boundary they lower to the tx-bearing
    operation on `instance[keyPath: \.table]`; outside a boundary they are
    compile-time diagnostics.
  - `#MDB_transacted(call)` — the join marker: rewritten inside a boundary
    into the callee's sibling, threading this boundary's transactions (one
    transaction across the composed call; joined reads see the boundary's own
    uncommitted state; a thrown joined write rolls back the whole boundary).
    the callee must reference the same environment-type set (the equal-env-set
    contract, enforced by the rewrite). standalone use is a compile-time
    diagnostic.
  - `Transaction<M>` capability typing (mode in the type): `commit()` exists
    only on `Transaction<Write>`; reads are generic over the mode; cursor
    write operations carry a `tx: Transaction<Write>` capability proof.
    writing on a read transaction is a type-checker error — the read-only
    write lint is retired as a runtime concept.
  - **`@MDB_layout`** — the multi-environment ARRANGEMENT helper: opens N
    `@MDB_environment` types at `<base>/<name>` in one call plus a
    `mdb_environment_names` inventory. no per-environment factories, no statics, no baked
    path.
  - `@MDB_environment(file:flags:maxReaders:maxDBs:mode:)` and
    `@MDB_table(name:flags:)` unchanged in role (schema assembly + per-table
    declaration); `version:` on `@MDB_environment` derives
    `<stem>-v<N>.mdb` when written (opt-in, fresh-file migration).
  - the prior `environments:` attribute form, the `#MDB_entry_load`/
    `#MDB_entry_store` trailing verbs, the provider-style container, and
    per-environment `Root` shells are REMOVED by this change.
- **`@MDB_environment`'s generated `open(at:)` loses its `fileName:`
  override** (breaking). the factory's file name comes from the `file:`
  attribute (plus the optional `version:` suffix) only; runtime-parameterized
  file names are the consumer's own `open(at:)` over a hand-rolled
  `MDB_environment` conformance. the `fileName:` surface was built for a
  pricedb plan whose end-state did not use it.
- **the raw typed `Database.deleteEntry(key:tx:)` convenience is removed**
  (breaking). no consumer used it (typed metadata tables delete through
  `#delete`). the typed raw `setEntry`/`loadEntry` surfaces remain.
- **`#cursor`'s emitted call never requires a CONDITIONAL `try`.** the
  trailing closure is lowered with an explicit `throws` annotation when the
  authored site carries `try` (the recommended spelling) or when the closure
  contains `#if` — the handler type is `throws(E)`, and an explicitly-throwing
  closure forces `try` to be always-required and never spurious, so the
  "no calls to throwing functions occur within 'try' expression" warnings on
  non-throwing cursor closures are gone and `#if`-gated closures compile
  identically in every configuration. a bare `#cursor` on a pure non-`#if`
  closure keeps compiling without `try`. capture lists are preserved under
  the injection (`{ [weak self] c throws in … }`); signatures the emitter
  cannot mirror byte-faithfully (attributes, `async`, unexpected parse
  nodes) fall back to the verbatim closure.
- **cross-environment joins: the tx labels are canonically ordered by
  environment type name** (fix). the join rewrites the callee sibling's
  arguments by label, and Swift requires call arguments in declaration order —
  two boundaries over the SAME environment set in different verb orders
  previously produced uncompilable joins. shells, siblings, and joins now all
  emit `tx_<E>` labels in name order.
- **`scripts/verify-consumers.sh`** — the cross-repo gate: pins each consumer
  (defaults: the migration-stage pricedb/wiremand) to this tree's HEAD by
  resyncing its staged QuickLMDB clone, then builds and runs its suite.
- **new runtime coverage**: multi-environment atomic boundaries + cross-env
  `#MDB_transacted` joins (commit, abort, joined-read-sees-uncommitted), a
  torn-read concurrency test (a boundary repeatedly reading a (key, value)
  composite while a concurrent writer mutates it), and cursor-`try` compile
  pins for the non-throwing / `#if` / no-`try` closure shapes.

- **the `concord` product** (new): a typed, transport-agnostic negentropy
  reconciliation engine over QuickLMDB. a reconcile round brings two stores
  with the same fixed-size-byte-key schema into agreement — range fingerprints
  over mmap key bytes skip matching regions, mismatches split and recurse, and
  the resulting have/need diff moves values AS BYTES (never decoded, never
  re-encoded). the protocol trio `ConcordIndex` / `ConcordTransport` /
  `ConcordSession` plus the `ConcordLMDBIndex` driver (one long-lived write
  transaction per round; release the index before the commit). ships as its
  own library product with its own DocC catalog and test target.
- **typed-handle companions + self-scoped committed reads** (the surface the
  verbs lower to, and the verb-less verification reads — consolidated here):
  `load(key:tx:)`, `store(key:value:flags:tx:)`, `delete(key:tx:)` and the
  dupsort pair `delete(key:value:tx:)`, `contains(key:tx:)` on
  `MDB_db`/`MDB_db_dupsort`; `readCommitted(key:)`, `containsCommitted(key:)`
  and (dupsort) `readCommittedDups(key:)`, each opening its own short-lived
  read transaction; `@MDB_environment`'s generated `open(at:)` creates the
  base directory as needed and forces `.noTLS` (reader slots bind to the
  transaction object, the enabler for sibling reads under task concurrency).
- **`QuickLMDBFunctionalInterop` target extraction** (breaking for code that
  reached the raw handle surface directly): `LMDBError` and the handle-level
  `MDB_db_*` / `MDB_cursor_*` statics moved into a standalone C bridge target
  (CLMDB-only imports, `consuming MDB_val` public functions, module-internal
  statics), re-exported via `@_exported import`; public behavior unchanged;
  covered by a new `QuickLMDBFunctionalInteropTests` target.
- **reserve / registry cleanup** (breaking): all `MDB_RESERVE` support removed
  (`reserveEntry`, the returning `setEntry` overload, `Operation.Flags.reserve`);
  the `value:` parameter of the DB-level `containsEntry` removed (it was a
  silent no-op — pair-existence checks live on cursors via `MDB_GET_BOTH`);
  the internal `_MDBTransactionScope` registry removed; `Transaction`'s deinit
  no longer aborts an already-committed transaction.

# 15.0.0

- Changed relationships of various database and cursor protocols such that the most restrictive of these types are now based on their `XXX_strict` counterparts.

# 14.0.0

- Now requires Swift v6.2.

# 13.0.0

- Added ability to access the `Environment` instance of a `MDB_db` compliant database.

# 12.0.0

- Fixed critical internal error with `Cursor.getBoth` and `Cursor.getBothRange` functions, where `key` was expected to be returned from MDB functions but was not. The API of these protocol functions have been updated to reflect corrections in this mistake.

### 11.1.1

- Now supporting `rawdog` v18 in addition to existing v17 and v16 support.

## 11.1.0

- Restored function to delete databases from an environment.

# 11.0.0

- Dropped `QuickLMDB.CursorAccessError` error type from the cursor access function. Now in v11, errors thrown within the cursor handler block will be transparently thrown (aka rethrows, but type strict). Any errors encountered in creating the cursor before the handler is called will result in a fatal error.

# 10.0.0

- Any LMDB function that associates with an active `Transaction` has now been marked as `@available(*, noasync)` to guarantee safe thread-local usage. While LMDB offers a `.noTLS` flag, it only applies to read transactions. As such, LMDB is always using TLS to some extent or another, and as such, this `noasync` requirement is most optimal to ensure safe usage in all contexts.

- Elimination of integrated logging functions. More effort to support this than it was worth. On the upside, one less dependency to rely on for building this project.

### 9.0.1

- Also supporting `rawdog` v17.

# 9.0.0

- `rawdog` requirement is now v16.

# 8.0.1

- Will also support `rawdog` v17 in addition to v16.

# 8.0.0

- Revised `MDB_db` protocol.

	- Improved clarity on thrown errors for `cursor` function.
	
- Revised `Transaction` to throw strict error types.

# 7.0.0

- PackageDescription and encompassing source code is now strictly Swift 6.

- No longer `throws` any type. Every function within the core API of QuickLMDB now throws a strict type.

# 6.0.0

- Updated PackageDescription to require rawdog v13 or above. This is considered a breaking change because rawdog v13 requires sendable on RAW_staticbuff and this cannot be applied automatically by the macro.

### 5.0.1

- Updated PackageDescription to include rawdog v12 within the supported scope.

# 5.0.0

- Another relatively small "breaking change". This update restores the correct return type on `Database.loadEntry` function. Since any type may be stored in a general (non-strcit) database, the decoding of any given type may fail, hence the need for a nullable return type.

# 4.0.0

- This update does not change any code in the QuickLMDB project, however, it modifies the requirements of its sister project `rawdog`, moving from `10.1.0..<11.0.0` of QuickLMDB v3 to `11.0.0...` in this v4 release.

	- `rawdog` v11 is in itself a negligibly small "major release", as it is identical to the outgoing v10, only adding Sendable conformance to a few key protocols to make the framework more friendly for concurrent applications.

- In light of the above, QuickLMDB 4.0.0 can be seen as a "Sendable friendly" re-release of QuickLMDB v3. This version is only being tagged as a major release to keep in line with the SemVer semantics and the breaking changes that this new Sendable requirement in `rawdog` entails.

# 3.0.0

- Revised the structure of various protocols and extensions to make it less easy to pass a type into a struct Database or Cursor.

- Now requires ``rawdog`` version `10.1.0` or later.

- Full documentation coming soon.

# 2.0.0

- Foundation-free implementation.

- Introduction of ``changelog.md`` to document the changes to this library over time.

- Eliminates all default implementations for serialization. QuickLMDB 2.0.0 leaves the serialization techniques entirely up to the developer.

- Added peer dependency ``rawdog``, a sophisticated library for defining how types serialize into portable binary formats with minimal copies (and code) in between.

	- Dependencies for QuickLMDB are deeply scrutinized and considered. ``rawdog`` is being added not only because of the functionality it provides for developers, but also because it was forged from this very library in many ways. rawdog started as a way for me to use MDB_val-like structures in other projects, and quickly grew to become the "final word" on native binary handling in Swift (imo ofc). The amount of work and code required to reach this point spanned far beyond the code I would ever expect QuickLMDB to take on, which is why it is being added as a dependency here.

	- In light of the removal of the built-in serialiation extensions of prior releases, QuickLMDB now offers ``rawdog`` as the answer to defining how abstract types transcode to the database as binary.

	- By committing to use QuickLMDB in v2.x.x and beyond, you are making an equal commitment to use ``rawdog`` library for serialization. Plan your development accordingly.

- Eliminated optional transactions on all argument types.

- Introduction of attached macro ``MDB_comparable`` which applies the native ``RAW_comparable`` protocol of rawdog into c convention funcs that LMDB can use for native sorting.

	- ``MDB_comparable``

- High-level naming scheme for arguments (mostly in ``Database`` and ``Cursor`` types) has changed to simple "key" | "value" names. While the previous naming scheme was arguably more aligned with the cultured naming conventions found in the Swift ecosystem, this change is being made in the name of simplicity and in preparation for more complex syntax macros in future releases.

- Introduction of database variants `Strict`, `DupFixed` and `DupSort` (and their respective protocols) that help enforce safe and efficient use of flag-variant databases using type safety.

	- Corresponding cursor variants to match.

- This tag is not completely documented and will see further coverage in the coming releases.