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

- **`QuickLMDB`** — the handwritten engine: `Transaction`, `Environment`,
  `Database`/`Cursor` (typed handles `Strict`/`DupSort`/`DupFixed` + raw),
  the protocol tree, the typed companions, and the public macro declarations
  (`Macros.swift`).
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

- `Transaction` stays PUBLIC: `~Copyable`, `consuming commit()/abort()`,
  `borrowing reset()/renew()`. raw lifecycle + the explicit-`tx:` surface
  (zero-copy reads, cursors, dup iteration) live here. never wrap, box, or
  store it — it flows as `borrowing` parameters.
- typed companions on `MDB_db`: `load(key:tx:)`, `store(key:value:flags:tx:)`,
  `delete(key:tx:)`, `contains(key:tx:)` (+ dupsort pair `delete(key:value:tx:)`).
- `readCommitted(key:)`, `containsCommitted(key:)` (dupsort `readCommittedDups`)
  are SELF-SCOPED verification reads — protocol members, deliberately NOT verbs.
- `MDB_convertible`/`MDB_comparable` come from rawdog + `@MDB_comparable`
  wraps byte sort/compare into a `MDB_val`-compatible C function.

### the schema layer (environments + databases)

- `@MDB_environment(file:flags:maxReaders:maxDBs:mode:)` — core declaration.
  generates `open(at:mapHeadroom:)` (creates the dir, sizes the map as current
  file size + headroom, forces `.noTLS`, opens every table in one setup
  write-transaction) and the `MDB_environment` conformance. contract: exactly
  `env` + `Database.X` stored properties.
- `@MDB_table(name:flags:)` — per-table declaration ON a `Database.X` stored
  property inside a core. name override + extra `MDB_db_flags`
  (`reverseKey`, `reverseDup`, `dupSort`, `dupFixed`, `integerKey`,
  `integerDup` — all PUBLIC). comparators are NOT a knob: the sort comes with
  the type via `MDB_comparable`. zero attributes = identity (name = property
  name = property name, flags `[.create]`) — the derived-default rule, byte-frozen.
  consumes: the env macro reads the attribute; on-disk name may differ from
  the property name, but generated locals and `Self(...)` labels are always
  the PROPERTY names.
- `@MDB_layout` — PLANNED, NOT built. container of cores: compile-time
  `basePath`, generated static attribute-reachable `try!` core accessors, a
  generated container `open`, and a static core inventory. (roadmap §3 in
  `v16 vision.md`.)

### the IO/transaction layer (the boundary dialect — the only transaction layer)

- `@MDB_transact(_ mode: MDB_transact_mode, environments: any MDB_environment...)`
  — attached BODY + PEER. modes: `.readOnly` (opens read transactions, aborts
  on throw AND success — a read leaf never commits) and `.readWrite` (aborts
  on throw, COMMITS on success). per listed environment the body derives
  `tx_<E>`; the peer emits the wrapped sibling (`tx_<E>: borrowing
  Transaction` per env) carrying the scraped body with verbs lowered and joins
  rewritten. ownership shape: tx values flow in as `borrowing` params; the
  shell owns the lifecycle; each tx consumed once per path.
- `#MDB_transacted(call)` — the Design-B JOIN marker: inside a boundary it is
  rewritten into `callee(args, tx_<E>: tx_<E>, …)`, joining this boundary's
  transaction (reads see this boundary's own uncommitted state; writes are
  atomic with the boundary). standalone use is a hard diagnostic. the
  equal-env-set contract: the rewrite passes the caller's full label set, so a
  callee sibling must declare exactly those labels.
- `#MDB_entry_load(environment:database:key:)` → `database.load(key:tx_<E>)`
  and `#MDB_entry_store(environment:database:key:value:)` →
  `database.store(key:value:tx_<E>)`. the `try` belongs AT the verb and the
  join (both lower to throwing calls). verbs standalone are hard diagnostics.
- the two read modes inside a write boundary: `#MDB_transacted(eventOn(day))`
  = JOINED (sees own uncommitted); plain `eventOn(day)` = SIBLING (its shell
  opens a separate read txn, committed-only).

### removed — do not resurrect

`@MDB_transact`, `.readWriteChild( parent:)`, `@MDB_transact_span`,
`@MDB_app`, `MDB_span_member`, `MDB_environment_container`, and the
receiver-based verb vocabulary (`#store`, `#load(db, key:)`, `#delete`,
`#contains`, `#cursor`, `#clear`, `#stats`, `#drop`). they were shed in the
phase-2 removal; `#cursor`, dup iteration, and the explicit-`tx:` surface do
that work inside boundaries today.

## 3. operating principles (do not regress these)

- **compile-time-first.** the compiler knows the schema shape at build time;
  a macro layer expresses it. no runtime registry, no reflection.
- **zero ambient state.** no task-local, no thread-local, no global. every
  generated artifact is local and explicit.
- **marker-gated rewriting.** only the freestanding verbs and the join marker
  are rewritten in a boundary body; every other line is byte-identical — the
  raw surface works directly inside a boundary with the injected `tx_<E>`.
- **derived names.** environment `E` ↔ `tx_<E>`. one spelling, one derivation.
- **explicit composition by joining**, never by nesting a second write.
- **derived defaults, explicit only where Swift fails.** a bare `Database.X`
  property needs zero attributes; a boundary body writes verbs with no
  transaction plumbing.
- **the UX mandate:** every macro goes to all lengths possible within its
  scope — anything technically implementable that is in-scope is in scope, and
  validation failures are friendly diagnostics, never compiler foreignness.
- **attribute-type-scope wall:** macro attribute arguments are evaluated at
  TYPE scope, so instance stored properties are not reachable in
  `environments:` — cores must be attribute-reachable (static stored
  properties today; `@MDB_layout` is the planned proper home).

## 4. what is built vs planned (honest status)

BUILT and verified (full suite green, 0 warnings):
- `@MDB_environment`, `@MDB_table(name:flags:)`, `@MDB_transact` (+
  `#MDB_transacted`, `#MDB_entry_load`, `#MDB_entry_store`), `@MDB_comparable`,
  the engine surface, typed companions, `readCommitted` family, interop.

PLANNED / in-flight (in `v16 vision.md` §3):
- `@MDB_layout` (compile-time base path; static `try!` accessors; container
  open; core inventory) — the next build.
- `.readWriteChild` relationship design is superseded by joining.
- the read-only-write compile lint (writing on a `.readOnly` boundary's
  transaction is TODAY a runtime engine access violation, pinned by a test).
- versioned environment filenames — deferred.

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
- for macros that gate on the ENCLOSING type (the table macro's core check),
  `assertMacroExpansion`'s contexts have EMPTY lexicalContext and spuriously
  fail them — use the seeded `file.expand(macros:contextGenerator:)` path,
  walking each node's parent chain to the enclosing struct. positives
  byte-compare `String(describing:)`; negatives collect
  `context.diagnostics.map(\.message)` and compare message arrays (immune to
  position drift).
- freeze expected expansions from the REAL expansion, never by hand: dump the
  actual to a file, then splice byte-exact. member-level indentation is TABs,
  generated bodies are 4 SPACES, and the blank separator between generated
  declarations is EMPTY — reproduce exactly, including blank lines, and
  prefix every expected-content line with the literal's base indentation so
  the strip yields the true bytes.
- DiagnosticSpec requires explicit `line:`/`column:`; positions shift across
  swift-syntax generations — message-only comparison is the robust default.
- variadic attribute arguments FLATTEN (trailing elements arrive unlabeled) —
  parse by position (index 0 = mode), never by label.
- attribute names carry trailing trivia: compare
  `attr.attributeName.trimmedDescription`.

## 7. compile-to-fix pitfalls (each cost real cycles)

- **double diagnostics**: when a macro has two attached roles (body+peer,
  member+peer), both can throw for the same bad input. the peer must yield a
  SILENT empty sibling for validation failures the body already owns, so users
  see exactly one error.
- **`try` at the verb/join**: `#MDB_entry_store` and `#MDB_transacted` lower to
  throwing calls — user code writes `try #MDB_entry_store(...)` /
  `try #MDB_transacted(...)`. omitting it fails with "call can throw".
- **generated `Self(...)` labels are PROPERTY names**: a table name override
  applies to the on-disk `name:` only; locals and memberwise-init labels stay
  the property names — using the resolved name breaks the memberwise init.
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

## 8. releases

the library is SemVer 2.0. before release: squasheable warnings gone
(clean-build verified), DocC builds warning-free
(`swift package --disable-sandbox generate-documentation`), the changelog
matches the shipped API (breaking changes documented), and the full suite is
green. the public macro vocabulary is the contract — never remove or rename a
shipped macro without the changelog saying so.
