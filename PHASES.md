# PHASES — QuickLMDB landing journal

implementation journal for the post-16.1.0 design. each phase is independently
buildable and verifiable; the release gate is a clean
`swift package clean && swift build --build-tests` at 0 warnings with the full
suite green. `v16 vision.md` is the design record.

## CURRENT ARCHITECTURE (2026-09-11 — the typed-environment rework)

the surface the user demanded: ZERO visible transaction vocabulary. the
typed-environment architecture supersedes the Route A / layout-with-statics
designs below:

- every environment is its own TYPE (@MDB_environment core). boundaries are
  INSTANCE methods on the core type; multi-env boundaries take other cores as
  TYPED parameters. no container walls, no `environments:` attribute.
- @MDB_transact(_ mode:) infers the environment set from the typed VERB calls
  in the body (the verb's `E.Type` argument); the method becomes a SHELL
  (opens/commits/aborts its own txns) and the peer emits the invisible
  SIBLING carrying `tx_<E>` params. read-only siblings are mode-generic so
  write boundaries can join reads.
- the typed verb family (#store/#load/#delete/#contains/#cursor/#clear/
  #stats/#drop): `(E.Type, database: KeyPath<E, Database...>, key/value/…)`.
  compiler-typed end to end; lowered to `instance[keyPath: KP].<op>(…, tx:)`.
  standalone use = diagnostic. trailing closures on a freestanding macro live
  in `trailingClosure` (NOT arguments) — the cursor verb reads it there.
- verb names (store/load/…) SHADOW bare same-named member calls — generated
  calls are `self.`-qualified.
- #MDB_transacted(call) = the join verb; equal-env-set by type-set.
- @MDB_layout = arrangement helper only: open(at:mapHeadroom:) + mdb_core_names
  inventory; no basePath, no factories, no statics, fixed names.
- residuals (documented): the join marker; cursor-write explicit tx; a
  boundary with NO direct verbs is a diagnostic (nothing to infer envs from);
  the bare write-call-inside-a-boundary footgun (root-scopes).

JS phase notes below are HISTORICAL — the typed-environment rework replaced
Route A and the layout-with-statics design.

---

## ratified design summary (2026-09-10)

- **capability-typed transactions.** `Transaction<M>` — the mode lives in the
  type (`Transaction<Read>` / `Transaction<Write>`). `commit()` exists only on
  `Write`; reads are generic over `M` (write txns still read). cursors carry
  the mode; write ops exist only `where M == Write`. this retires the
  read-only-write lint outright: writing on a read transaction is a
  type-checker error, for direct verbs, joined callees, user helpers, and
  cursor writes alike.
- **Route A boundaries.** the boundary method IS the joined primitive: its
  authored signature carries the derived `tx_<E>` params (read boundaries
  spell `Transaction<some Mode>`, write boundaries `Transaction<Write>`). the
  peer emits one `<name>Root` shell per boundary — the root-scoping entry that
  opens fresh transactions from the attribute's mode and commits/aborts alone.
- **marker-mandatory entry.** the two entry verbs into a transactional unit:
  `#MDB_transacted(call)` = run it on MY transaction (join, participant entry);
  `#MDB_root(call)` = run it as its own fresh unit (root, unit entry; rewrites
  onto the `<name>Root` shell). a bare call to a boundary method is a
  missing-argument compile error — root-scoping cannot happen by accident.
- **schema layer.**
  - `@MDB_layout` — required `basePath` (the single path authority; every
    core resolves to `<basePath>/<coreName>`), generated static `try!` core
    accessors (the production-singleton contract), a container
    `open(at:mapHeadroom:)` for dynamic-path consumers, and a static core
    inventory. path-stemming (reading 1): the static accessors splice the
    basePath expression; dynamic consumers use the generated open. tests
    route through the wrapped siblings + raw surface.
  - `version:` on `@MDB_environment` — optional, engaged only when written
    (bare cores keep their exact name); engaged ⇒ derived on-disk name
    `file-v<N>.mdb` (so `version: 0` gives `-v0`). fresh-file + copy is the
    migration convention; no sentinel table; no library migration helper.
- **non-goals / residuals.** no ambient state anywhere (no task-local guard —
  the auto-parenting stack stays rejected). `#MDB_root` of a write boundary
  inside a live write boundary still hangs (deliberate; marker makes intent
  visible). direct manual `tx:` filling still compiles (joins correctly — a
  feature). raw-C forging remains the universal escape hatch.

---

## phase 1 — engine: capability-typed Transaction

- `Transaction` → `Transaction<M>` (`M: MDB_transaction_mode`; public `Read` /
  `Write` markers, phantom). init re-spelled `Transaction<Write>(env:)` /
  `Transaction<Read>(env:)`; the `readOnly:` bool disappears.
- `commit()` on `Write` only; `abort()` on both; `load`/`contains`/`cursor`/
  `reset` generic over `M`.
- cursor families gain the mode (`Cursor`, `Strict`/`DupSort`/`DupFixed`,
  iterators); write ops gated `where M == Write`.
- `MDB_db` companions: reads generic, writes `<Write>`. interop +
  `readCommitted` family untouched.
- verification: clean build 0 warnings; engine suites re-spelled.
  micro-check: `borrowing Transaction<some M>` in authored params — if `some`
  fights the ownership modifier, fall back to an explicit `<M>` generic on
  read boundaries.

status: DONE (2026-09-10) — clean build 0 warnings, 98 tests / 16 suites green.
  capability typing landed. NOTE on cursor writes: gating cursor write ops by
  member-existence on a mode-typed cursor is blocked by the `MDB_db_cursor_type`
  associatedtype (it cannot be mode-parameterized), so cursor writes carry a
  `tx: borrowing Transaction<Write>` capability-proof parameter instead —
  inside a readOnly boundary no Write transaction is in scope, so the write is
  a type-checker error either way; the passed tx must be the cursor's own
  transaction (engine enforces). the write-on-readOnly runtime pin was REMOVED
  (now a compile error by construction).

## phase 2 — macro: @MDB_transact Route A

- body macro stops wrapping: the authored body IS the joined primitive
  (verbs lowered, `#MDB_transacted` joins rewritten against the DECLARED
  `tx_<E>` params).
- peer emits one `<name>Root` shell per boundary — opens
  `Transaction<Read/Write>(env:)` per env from the attribute's mode, calls the
  joined primitive, commit/abort per mode.
- validation: declared tx labels must exactly match the `environments:` list;
  read mode → `some`-typed param, write mode → `Transaction<Write>` param.
- fixtures: full re-pin + Route A shapes.

status: DONE (2026-09-10) — clean build 0 warnings, 97 tests / 15 suites green.
  Route A landed: authored joined primitives (tx params, Write/some-Mode
  typed), the body IS the lowered joined body, and the peer emits the
  `<name>Root` shells. two compiler walls hit and resolved: (1) `@attached(peer,
  names: arbitrary)` + same-type-static attribute args = circular reference —
  fixed with `names: suffixed(Root)`; (2) the #MDB_root ENTRY MARKER is
  mechanically impossible: freestanding macro arguments are type-checked, and
  the marker's whole point is wrapping a call that is intentionally ill-typed
  (missing tx). the unit entry is the generated `<name>Root` SHELL as a plain,
  deliberately-named function — the same "bare name can never root-scope"
  property. expansion fixtures regenerated byte-exact with flush-left raw-bytes
  literals (no escapes, no dedent).

## phase 3 — macro: #MDB_root marker

- new freestanding expression macro: `#MDB_root(f(args))` → `<f>Root(args)`.
  plugin registration + declaration. argument-must-be-a-call validation.
- fixtures + runtime pins: entry via `#MDB_root`, join via `#MDB_transacted`,
  sibling read via `#MDB_root`, and the bare-call compile-error fixture.

status: DONE (2026-09-10) — folded into phase 2's landing (they are one
  change; the demo cannot compile between them). see the phase-1-journalnote
  on the entry marker: `#MDB_root` was probed and KILLED by the freestanding-
  argument type-check wall; entry is the `<name>Root` shell by name.

## phase 4 — schema: @MDB_layout

- required `basePath` (spliced type-scope expression); generated static `try!`
  core accessors; container `open(at:mapHeadroom:)` (base + per-core subdirs,
  opens each core, assembles Self); static inventory; validation surface
  (struct-only, cores-only stored props, name collisions).
- migrate the demo container (ClubApp) onto it; pin the one-core-container
  (single-env-owner) case.

status: DONE (2026-09-10) — clean build 0 warnings, 105 tests / 17 suites green.
  @MDB_layout landed: required basePath (path-stemming), per-core `_mdb_open_<name>`
  factories, `mdb_core_names` inventory, dynamic `open(at:mapHeadroom:)`, and
  validation (struct-only, missing basePath, empty core set, missing statics —
  negatives via the SEEDED file.expand path, since assertMacroExpansion does
  not capture thrown member-macro diagnostics). the demo (ClubApp) and a new
  single-core container pin the one-core-container single-env-owner resolution.
  THE ATTRIBUTE-REACHABILITY WALL (verified): attribute arguments resolve
  BEFORE macro-generated members exist, so `environments:` cannot name
  generated accessors — each core needs ONE authored
  `static let <name> = try! _mdb_open_<name>()` (the irreducible floor the
  wall sets; the layout validates its presence with a friendly diagnostic,
  and removes every other piece of the hand-rolled scaffold). member-line
  DeclSyntax fragments mangle whitespace — emit each full declaration as one
  multi-line string.

## phase 5 — schema: version: on @MDB_environment

- optional `version: UInt = 0`, engaged only when the attribute is WRITTEN
  (syntactic presence, not value default) — bare cores keep `calendar.mdb`;
  engaged ⇒ derived name `file-v<N>.mdb` (so `version: 0` gives `-v0`).
- fresh-file + copy workflow documented; no sentinel.

status: DONE (2026-09-10) — clean build 0 warnings, 110 tests / 18 suites green.
  version: landed on @MDB_environment, engaged ONLY when the attribute is
  WRITTEN (bare cores byte-identical — existing fixtures untouched): derived
  on-disk name `<stem>-v<N>.mdb` (version: 0 → -v0), computed at runtime so
  non-literal version expressions splice too. fresh-file pins: v2 never sees
  v1's data (different file by construction) and v1 stays readable after v2
  writes; bare core keeps its exact name; version: 0 derives -v0; fixture
  byte-freezes the versioned targetPath line. escape-drift struck the patch
  tool's macro-source compile again — repaired with the collapse pass.

## phase 6 — docs + full verification

- `v16 vision.md` (all decisions closed, Route A + capability typing
  recorded), `AGENTS.md`, README + DocC, changelog `Unreleased`.
- full demo rewrite to the final surface; the "lint is a later pass" note
  removed (lint retired).
- clean-build 0 warnings; full suite green; expansion fixtures byte-frozen.

status: PENDING
