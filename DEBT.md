# DEBT — resolved items (settled 2026-09-12 on `debt-resolution`)

status: settlement record. every item below was resolved on the
`debt-resolution` branch; each entry records the disposition and the evidence
that closed it. this file was the live working list produced by the
software-skeptic audit (2026-09-12) over wiremand, pricedb, and this library.

---

## 1. multi-env atomic boundaries + multi-label joins — NOW EXERCISED

**disposition: resolved by a committed runtime suite at production shape.**

`Tests/QuickLMDBTests/MultiEnvironmentAtomicityTests.swift` drives a boundary
whose verbs address TWO environment types (self + a typed `LedgerB`
parameter), a `#MDB_transacted` join of a MULTI-env sibling (the
equal-env-set contract), and pins:
- the multi-env shell's commit path (both environments persisted);
- the multi-env abort path (a mid-boundary throw leaves BOTH environments
  untouched — no partial commit);
- the CROSS-ENV JOIN's atomicity (a failure inside the joined callee rolls
  back the outer boundary's own write AND the joined writes as one unit);
- a JOINED read seeing this boundary's uncommitted state across environments
  (Design-B semantics over two envs).

FIRST VERIFICATION ITEM: the multi-env join exposed a REAL latent defect — the
rewrite threaded `tx_<E>` labels in first-verb-appearance order, but Swift
requires call arguments in declaration order, so two boundaries over the same
environment set in different verb orders produced uncompilable joins. FIXED in
`QuickLMDBMacros/MDB_transact.swift`: shells, siblings, and joins now all emit
`tx_<E>` labels in canonical (name-sorted) order. the existing
single-env and already-alphabetical multi-env fixtures are byte-unchanged.

contract precision (audit follow-up): the equal-env-set contract is enforced
by LABEL-NAME equality — the rewrite threads `tx_<E>` by the environment
TYPE NAME as spelled. two types in different modules that share a short name
(MODULE.Env vs OTHER.Env) produce the same label and are NOT type-distinguished
by the rewrite; authors joining across modules must use distinct environment
type names. this is a documented caller responsibility, not a silent
enforcement gap for distinct names.

verified on macOS (4 tests green); the suite is platform-portable and runs on
Linux via the same test binary.

---

## 2. no torn reads under a concurrent writer on a MUTABLE key — NOW PINNED

**disposition: resolved by a committed concurrency test.**

`Tests/QuickLMDBTests/TornReadTests.swift`:
- a concurrent writer OVERWRITES the same (generation, payload) key pair in a
  fresh write transaction every iteration (a mutating-key workload — the
  wiremand shape, not the append-only discipline pricedb happened to hold);
- a boundary repeatedly reads the (key, value) composite through ONE
  transaction and asserts the payload always matches its generation
  (payload = generation * hash constant — any composite assembled from two
  different generations fails);
- 20,000 writer iterations racing 20,000 reader observations, asserting zero
  torn observations.

detection-class precision (audit follow-up): LMDB snapshot isolation makes
ANY single-transaction-per-observation reader internally consistent, so this
pin detects the per-key/per-verb transaction class (reads straddling a write
commit) — the library-level guarantee that ONE boundary reads ONE snapshot.
the larger consumer-facade multiplexing shape (assembling one response from
multiple transactions) is the consumer's composition, not a library guarantee,
and is out of scope for this pin.

shapes: synchronous `Thread`s (the LMDB surface is `noasync`), joined by
counting semaphores in a SYNCHRONOUS test (no Swift-concurrency threads are
blocked, no DispatchQueue), `Mutex`-counted violations (Synchronization).

---

## 3. `open(at:fileName:)` and typed `deleteEntry` — REMOVED (no consumer use)

**disposition: removed, per the "done when": each surface either gains a real
consumer use or is removed with its tests and fixtures. no consumer used
either; both were parent investments built for pricedb plans whose end-states
did not use them.**

- `fileName:` override: `@MDB_environment`'s generated factory is now
  `open(at:mapHeadroom:)` — the file name comes from `file:` (plus optional
  `version:`). removed from the macro, its docs
  (`Macros.swift`, `MDB_environment.swift`), and
  `EnvironmentFileOverrideTests.swift`; the three byte-frozen
  `@MDB_environment` oracles in `MDB_tableExpansionTests.swift` were
  respliced from the real expansion. consumers never called the macro's
  `fileName:` — pricedb's FiatCore/SpotCore hand-roll their OWN `open(at:…)`
  over raw `MDB_environment` conformances.
- typed raw `deleteEntry(key:tx:)`: removed from
  `DBRawTypedConvenience.swift` and its test in `RawTypedConvenienceTests.swift`.
  zero consumer `.deleteEntry(` call sites exist. the typed raw
  `setEntry`/`loadEntry` surfaces remain (pricedb's raw tables use them).

changelog: both removals documented as breaking changes.

---

## 4. the spurious-`try` before `#cursor` — RESOLVED at the lowering level

**disposition: (b) — the lowering was changed so the emitted call never
requires a CONDITIONAL `try`, with byte-frozen fixtures for `#if` and
non-`#if` closure bodies. the (a) "recommended spelling" (`try` retained) is
now the DESIGNED behavior, documented on the macro.**

mechanism: the `#cursor` handler type is `throws(E)`, so a non-throwing
closure made `try` spurious (pricedb's 5 warnings) and an `#if`-gated closure
made try-ness configuration-dependent. the sibling lowerer now injects an
explicit `throws` annotation into the trailing closure (after the parameter
clause, before any `->` return type) when the authored site carries `try` or
the closure contains `#if` — an explicitly-throwing closure forces E away
from `Never`, so:
- `try #cursor(...)` with a NON-throwing closure: always valid, never warns;
- `#if`-gated closures: compile identically in EVERY configuration (no more
  statement-join trivia corruption on the no-`try` + `#if` path — injection
  makes it a deterministic "call can throw, not marked with 'try'" with the
  standard fix-it);
- a bare `#cursor` on a pure non-`#if` closure keeps compiling without `try`
  (the `Never` path) — all five consumer no-`try` sites are untouched;
- closures that already declare `throws`, and `$0`-style closures (no
  parameter clause — injection impossible), keep their authored form.
- capture lists are PRESERVED under injection (`{ [weak self] c throws in
  … }`); signatures the emitter cannot mirror byte-faithfully (attributes,
  `async`, or any unexpected parse nodes — a silent-corruption guard added
  after an adversarial audit) fall back to the verbatim closure.

evidence: 6 byte-frozen fixtures in
`Tests/QuickLMDBMacroTests/MDB_transactExpansionTests.swift`
(`CursorTryExpansionTests`), runtime compile pins in
`Tests/QuickLMDBTests/CursorTryRuntimeTests.swift`, and a CLEAN build with 0
warnings (the `try #cursor` runtime sites no longer emit the spurious-try
warning).

---

## 5. the cross-repo gate — COMMITTED as `scripts/verify-consumers.sh`

**disposition: resolved with a script (the consumer repos live outside this
tree, so a committed script + documented invocation is the honest unit of
"on every parent change"; wiring it into CI/pre-commit is a follow-up).**

`scripts/verify-consumers.sh [--sync-only] [consumer-dir ...]`:
- pins each consumer to THIS tree's CURRENT WORKING TREE (a pre-commit gate
  mirrors the tree — the change under test): the consumer resolves QuickLMDB
  via a local path pin (`<consumer>/../QuickLMDB`, the migration-stage
  layout) and the script resyncs that staged clone from the parent (build
  artifacts excluded);
- a passing suite must run a NON-ZERO test count (an empty green suite is a
  failure, not a PASS);
- then `swift build --build-tests` and `swift test` per consumer, reporting
  pass/fail with a non-zero exit on any failure;
- defaults to the migration-stage pricedb/wiremand pair; positional args
  override.

consumer-leg note: wiremand's suite is Linux-targeted — the script run on
macOS builds and runs the macOS-capable suites and reports wiremand's build
result honestly; the Linux leg is the same script on the Linux box after pull.
