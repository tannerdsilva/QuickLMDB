# AGENTS.md — operational guidance for autonomous agents

quick orientation to the QuickLMDB codebase: what the architecture is, what is
built vs planned, the non-negotiables an agent must not regress, and the
work loop that keeps the tree verifiable. this file is OPERATIONAL guidance,
not API reference. users read `README.md`; the full design record (doctrine,
decision trail, roadmap) is `v16 vision.md`; API docs are the DocC catalog.

---

## 1. what this repository is

QuickLMDB is a Swift integration of LMDB: a full transactional control surface
over an `Environment`, zero-copy memory map access, and a macro layer that
organizes the transaction layer into method boundaries. the tree runs Swift
6.3 (`swift-tools-version: 6.3`, macOS 15+, also Linux). three products read as
one module:

- **`QuickLMDB`** — the handwritten engine: `Transaction<M>` (capability-typed),
  `Environment`, `Database`/`Cursor` (typed handles `Strict`/`DupSort`/`DupFixed`
  + raw), the protocol tree, the typed companions, and the public macro
  declarations (`Macros.swift`).
- **`QuickLMDBFunctionalInterop`** — the C bridge (imports only CLMDB): 19
  `consuming MDB_val` functions over raw handles, `LMDBError`,
  `MDB_cmp_func_t`. re-exported via `@_exported import`.
- **`QuickLMDBMacros`** — the only target that writes Swift that rewrites
  Swift. declared as a `.macro` target (never a `.target`); registered in
  `Plugin.swift`; declared publicly in `QuickLMDB/Macros.swift`.

external dependencies: CLMDB (LMDB headers), rawdog 22 (`RAW_*` byte
coding/comparison), swift-system, swift-syntax 603.

## 2. the architecture (current, ratified)

### the engine surface (unchanged below the macro layer)

- `Transaction<M>` stays PUBLIC: `~Copyable`, capability-typed over a mode
  marker (`Read` / `Write`). `commit()` exists only on `Transaction<Write>`;
  `abort()` on both; reads (`load`/`contains`/`cursor`/`reset`) are generic
  over the mode so write transactions read. raw lifecycle + the explicit-`tx:`
  surface (zero-copy reads, cursors, dup iteration) live here. never wrap,
  box, or store it — it flows as `borrowing` parameters.
- typed companions on `MDB_db`: `load(key:tx:)`, `store(key:value:flags:tx:)`,
  `delete(key:tx:)`, `contains(key:tx:)` (+ dupsort pair `delete(key:value:tx:)`).
  reads are mode-generic; the write companions require `Transaction<Write>` —
  writing on a read transaction is a type-checker error.
- cursor write operations (`setEntry`, `deleteCurrentEntry`) carry a
  `tx: borrowing Transaction<Write>` capability proof (in a readOnly boundary
  no Write transaction is in scope, so the write cannot compile).
- `readCommitted(key:)`, `containsCommitted(key:)` (dupsort `readCommittedDups`)
  are SELF-SCOPED verification reads — protocol members, deliberately NOT verbs.
- `MDB_convertible`/`MDB_comparable` come from rawdog + `@MDB_comparable`
  wraps byte sort/compare into a `MDB_val`-compatible C function.

### the typed-environment transaction layer (the only transaction layer)

every environment is its own TYPE. `@MDB_environment` cores declare their
`env` + `Database.X` tables, and transaction boundaries live ON those types as
instance methods. there is NO transaction vocabulary on the authored surface:

- `@MDB_transact(_ mode: MDB_transact_mode)` — attached body + peer on an
  INSTANCE method. the environment set is INFERRED from the typed verb calls
  in the body: every environment type a verb references must be `self` (the
  boundary is attached to that core type) or a typed parameter of the method.
  the method becomes a SHELL (opens `Transaction<Read/Write>(env:)` per
  inferred environment, calls the sibling, and closes every one — readOnly
  aborts on throw AND success; readWrite commits on success). the peer emits
  the INVISIBLE SIBLING: same signature + `tx_<E>: borrowing Transaction<…>`
  per environment (read-only siblings are generic over the mode so write
  boundaries can join reads), whose body is the authored body with verbs
  lowered and joins rewritten. method contract: instance only, `throws`
  required, not `async`. a body with no verbs is a diagnostic.
- **the typed verb family** (`#store`/`#load`/`#delete`/`#contains`/`#cursor`/
  `#clear`/`#stats`/`#drop`): `#store(E.self, database: \.table, key:…,
  value:…)` — `E` is the environment TYPE, `database:` is a
  `KeyPath<E, Database…>`; key/value/return types bind through the table's own
  generics. inside a boundary they lower to the tx-bearing operation
  (`instance[keyPath: \.table].<op>(…, tx: tx_E)`); standalone use is a
  compile-time diagnostic.
- `#MDB_transacted(call)` — the Design-B JOIN marker: rewritten inside a
  boundary into the callee's sibling, threading this boundary's transactions
  (reads see this boundary's own uncommitted state; writes are atomic with the
  boundary). the callee must reference the SAME environment-type set — the
  equal-env-set contract, enforced by the rewrite's labels. standalone use is
  a hard diagnostic.
- two read modes inside a write boundary: `#MDB_transacted(eventOn(day))` =
  JOINED (same transaction, sees this boundary's uncommitted state); a plain
  `eventOn(day)` = SIBLING read (its shell opens a separate read txn,
  committed-only — "validate against durable data").
- `@MDB_layout` — the multi-environment ARRANGEMENT helper (member macro,
  fixed names): opens N `@MDB_environment` cores at `<base>/<name>` in one
  call (`open(at:mapHeadroom:)`) plus a `mdb_core_names` inventory. no
  per-core factories, no statics, no baked path.
- `@MDB_environment(file:flags:maxReaders:maxDBs:mode:)` — schema assembly:
  generates `open(at:mapHeadroom:) throws -> Self` (creates the dir, sizes the
  map as current file size + headroom, forces `.noTLS`, opens every table in
  one setup write-transaction). `version:` when WRITTEN derives the on-disk
  name `<stem>-v<N>.mdb` (opt-in fresh-file migration).
- `@MDB_table(name:flags:)` — per-table declaration on a `Database.X` stored
  property inside a core. name override + extra `MDB_db_flags`. zero
  attributes = identity (name = property name, flags `[.create]`).

### macro-mechanics facts (verified, do not relitigate)

- freestanding-expression macro ARGUMENTS are type-checked — a marker whose
  argument is intentionally ill-typed bare can never compile (this killed a
  `#MDB_root(call)` entry marker). inside a boundary body, markers are
  consumed by the enclosing attached macro BEFORE type-checking.
- attribute arguments resolve before macro-generated members exist — a
  boundary cannot route through statics another macro generates. the
  typed-environment architecture avoids the wall by using INSTANCE methods
  and body-inferred environments (no attribute-routed cores exist).
- a freestanding macro's trailing closure is a SEPARATE node (`trailingClosure`)
  — not an argument (`#cursor` reads it there).
- the typed verb names (`store`/`load`/…) SHADOW bare same-named member calls
  in scope — generated calls are `self.`-qualified.
- `@attached(peer, names: arbitrary)` combined with attribute args referencing
  same-type members = circular reference (use `overloaded` or fixed names).

### removed — do not resurrect

- the `environments:` attribute form of `@MDB_transact`, the
  `#MDB_entry_load`/`#MDB_entry_store` trailing verbs, per-core `Root` shell
  entries, the provider-style layout with `_mdb_open_*` factories and authored
  statics, `MDB_transact_mode.readWriteChild`, and any ambient state
  (task-local/thread-local/registry) for transaction routing.

## 3. operating principles (do not regress these)

- **compile-time-first.** the compiler knows the schema shape at build time;
  a macro layer expresses it. no runtime registry, no reflection.
- **zero ambient state.** no task-local, no thread-local, no global. every
  generated artifact is local and explicit. composition is spelled
  (`#MDB_transacted`), never inferred from context.
- **typed-verb gating.** only the typed verb family and the join marker are
  rewritten in a boundary body; every other line is byte-identical. the verbs
  carry type information (environment type + KeyPath), so no name-shape
  guessing is involved.
- **invisible plumbing.** the `tx_<E>` labels are implementation detail of the
  generated shell/sibling pair; the user's method signatures and call sites
  carry no transaction vocabulary.
- **explicit composition by joining**, never by nesting a second write.
- **derived defaults, explicit only where Swift fails.**
- **the UX mandate:** every macro goes to all lengths possible within its
  scope — anything technically implementable that is in-scope is in scope, and
  validation failures are friendly diagnostics, never compiler foreignness.

## 4. what is built vs planned (honest status)

BUILT and verified (full suite green, 0 warnings on a clean build):
- `Transaction<M>` capability typing, `@MDB_environment`, `@MDB_table`,
  `version:`, `@MDB_layout`, `@MDB_transact` (typed-environment boundaries),
  the typed verb family, `#MDB_transacted` joining, `@MDB_comparable`, the
  engine surface, typed companions, `readCommitted` family, interop.

PLANNED:
- `@MDB_layout` as the home of application-level convenience beyond the
  arrangement open (none committed yet).
- versioned-environment MIGRATION tooling (fresh-file + stream workflow) stays
  documentation/consumer code.

agents must not assume the planned surface exists.

## 5. the work loop

- build and test: `swift build --build-tests` and `swift test`. full-suite
  green with 0 warnings is the release gate. BELIEVE ONLY a clean rebuild for
  warning truth — incremental builds cache diagnostics. run
  `swift package clean && swift build --build-tests` before declaring
  "0 warnings".
- filter suites by target/name: `swift test --filter <Name>`.
- drop a new macro into three places, or it does not exist: the declaration
  (`QuickLMDB/Macros.swift`), the implementation (`QuickLMDBMacros/<file>.swift`),
  the plugin registration (`QuickLMDBMacros/Plugin.swift`).
- new macro code must be Foundation-free; generate diagnostics, never
  `fatalError()`.
- tests use Swift Testing (`import Testing`, `@Test`, `#expect`). runtime
  suites drive the REAL engine (fresh temp dirs); expansion suites freeze the
  macro output byte-exact.

## 6. macro testing conventions

- `assertMacroExpansion`'s default failure handler is XCTFail — a NO-OP under
  Swift Testing. always pass a `failureHandler` that records a Swift Testing
  `Issue`, and `@testable import QuickLMDBMacros` for the impl types.
- for macro validation that throws from the BODY/PEER roles, the seeded
  `file.expand(macros:contextGenerator:)` path records the diagnostics; when a
  body also contains freestanding verb markers, filter out the
  `verbOutsideBoundary` fallback messages before comparing.
- `assertMacroExpansion` does NOT capture thrown diagnostics from MEMBER or
  STRUCT-target macro roles — use the seeded path for those.
- freeze expected expansions from the REAL expansion, never by hand: dump the
  actual to a file, then splice byte-exact. member-level indentation matches
  the input's; generated bodies are 4 SPACES; the blank separator between
  generated declarations is EMPTY — reproduce exactly. flush-left multi-line
  `"""` literals (closing delimiter at column 0, no dedent) carry the exact
  bytes without escape ambiguity.
- DiagnosticSpec requires explicit `line:`/`column:`; positions shift across
  swift-syntax generations — message-only comparison is the robust default.
- variadic attribute arguments FLATTEN (trailing elements arrive unlabeled) —
  parse by position (index 0 = mode), never by label.
- attribute names carry trailing trivia: compare
  `attr.attributeName.trimmedDescription`.
- Swift Testing `#expect(try op(...))` does not compose with typed
  `throws(LMDBError)` — hoist the `try` into a local first.

## 7. compile-to-fix pitfalls (each cost real cycles)

- **double diagnostics**: when a macro has two attached roles (body+peer,
  member+peer), both can throw for the same bad input. the peer must yield a
  SILENT empty sibling for validation failures the body already owns, so users
  see exactly one error.
- **`try` belongs at the verb and the join**: `#store(...)` and
  `#MDB_transacted(...)` lower to throwing calls — user code writes
  `try #store(...)` / `try #MDB_transacted(...)`.
- **`type-checking of macro args`: a freestanding marker cannot wrap a call
  that is ill-typed bare (WALL-1). the typed verbs work because their
  arguments are complete on their own.
- **noncopyable `Transaction`**: never capture it in a closure; pass it as a
  `borrowing` parameter; the shell owns lifecycle (consuming `abort()` /
  `commit()`); each tx consumed exactly once per path — no `defer` aborts, no
  `withCheckedContinuation`, no DispatchQueue threading of LMDB work.
- **no NS-prefixed APIs / `size_t`**: `Int` everywhere, Swift-native
  alternatives over Foundation where the standard library suffices.
- **one struct per environment core** owning its tables and transaction
  scopes — no multi-env god objects, no ambient boundary stacks.
- **map sizing at every open** = actual file size + headroom; never under-size
  an environment.
- clean-build warnings after ownership/mechanical refactors: `var`→`let`,
  spurious `try` on rethrows closures (both only surface on a CLEAN build).
- the patch/write tools have historically DOUBLE-ESCAPED backslashes in
  macro-source string literals — after any edit containing `\(`, collapse
  doubled runs (`\\` → `\`) or the generated code silently degrades to literal
  `\(` text.

## 8. releases

the library is SemVer 2.0. before release: squasheable warnings gone
(clean-build verified), DocC builds warning-free
(`swift package --disable-sandbox generate-documentation`), the changelog
matches the shipped API (breaking changes documented), and the full suite is
green. the public macro vocabulary is the contract — never remove or rename a
shipped macro without the changelog saying so.
