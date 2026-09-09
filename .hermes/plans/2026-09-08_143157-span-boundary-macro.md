# Span Boundary Macro (@MDB_transact_span) — Cross-Environment Transactions

> **For Hermes:** Execute task-by-task after the user approves this outline. The verb-macro plan
> (`2026-09-07_093018-verb-macros-marker-gated.md`) is the **prerequisite** — the span boundary is a
> second consumer of the same freestanding verbs. Rawdog boundary honored: nothing here touches
> `~/workspace/rawdog`; the rawdog *principle* (transform only lines that are explicitly-marked
> freestanding expression macros) is the governing rule of this plan.

**Goal:** A body-macro transaction boundary that coordinates **multiple LMDB environments** — opening
all participating transactions up front (full staging overlap, writes invisible to readers), aborting
**all** of them if the body throws, and committing them back-to-back in a narrow, deterministic window.
One effortless-looking app method; two real transactions behind the seams.

**Honest ceiling (stated up front):** LMDB commits are per-environment; cross-environment **atomicity is
impossible**. This macro's job is to maximize transactional OVERLAP and minimize the commit window, not
to fake atomicity. The residual window — a crash or commit failure between the first and last commit —
is unavoidable and is documented, not hidden.

## The governing principle (rawdog-style marker-gating)

**No macro touches a line that is not a freestanding expression macro.** Every transaction boundary —
single-env `@MDB_transact` AND the span — lowers *only* the verb calls (`#store` / `#load` / `#delete` /
`#contains` / `#cursor` / `#clear`). Every other line in the body is emitted byte-identical. Consequence:
a plain op call (`calendar.events.setEntry(...)`) inside a boundary fails to compile unless it carries
`tx:` explicitly. No name-lists, no receiver scanning, no callee-name attribution — the marker-gated
rewriter replaces the `TXInjectionRewriter` entirely (verb plan Phase 2, Task 5).

## Decisions (locked during design refinement, 2026-09-08)

- **Bare marker, full inference.** `@MDB_transact_span` takes **no arguments** in the default form.
  The member list and per-env modes are inferred from the verb calls in the body:
  - **envs** = the base names of the verb receivers (`#store(calendar.events, …)` ⇒ env `calendar`);
  - **modes** = any write verb (`#store`/`#delete`/`#clear`) on an env ⇒ `.readWrite`; a read-only
    access (`#load`/`#contains`/`#cursor`) alone ⇒ `.readOnly`. An env with both ⇒ `.readWrite`.
  - **commit order** = first-touch order in the body (deterministic; source-of-truth env written first
    commits first).
  - `#cursor` counts as readOnly-inducing. (A `cursor.deleteCurrentEntry` inside a readOnly txn is the
    existing documented `EACCES` runtime path, not a compile lint — noted in usage rules.)
- **Swift-macro reality: no type-level body rewriting.** A member macro cannot rewrite existing member
  bodies, so the per-method marker is the floor (same as rawdog's per-member markers). The marker is
  deliberately name-free so the only repetition left is the stored property name + the verb base name.
- **Container-level `@MDB_app` member macro** — the "higher-level" macro. It scans the container's
  stored properties, builds the **environment inventory** (property name → core), and emits a
  `MDB_environment_container` conformance carrying it. The span body macro consumes that inventory to:
  1. resolve a core name to its environment (`calendar` → `calendar.env`) so the explicit-override form
     is `.readWrite(calendar)` (no `.env` on the user's side), and
  2. produce real diagnostics: a verb whose receiver base is not an inventory member, or a write verb
     on an env the method inferred read-only.
  `@MDB_app` is **required** for span methods (the inventory is routing + diagnostics); single-env
  `@MDB_transact` is unaffected.
- **Explicit override remains, as an escape hatch only**: `@MDB_transact_span([.readWrite(calendar)])`
  overrides inference (force a mode, pin commit order) — same expansion, list supplied explicitly.
  Default is bare.
- **Injected names**: `tx_<env>` (`tx_calendar`, `tx_contacts`), the documented composition contract
  (same role as single-env `tx`). Used to pass a routed parent to `.readWriteChild` boundaries inside
  the span. Deliberately not a composite struct (`tx.calendar`) — borrowing accessors over stored
  noncopyables aren't safely expressible on this toolchain.
- **Separate macro**, not a mode on `@MDB_transact`. Different rewriters, different state; one body
  macro per declaration anyway. Sprawl avoidance is the point.
- **Single-env `@MDB_transact` keeps its explicit mode** (`.readWrite`/`.readOnly`/`.readWriteChild`)
  for now. A later unification (bare `@MDB_transact` inferring mode from verbs) is possible but is NOT
  part of this plan — changing the single-env contract is out of scope.

## Architecture (expansion sketch)

```swift
@MDB_app
public struct HybridApp {
    public var calendar: CalendarCore
    public var contacts: ContactCore

    @MDB_transact_span
    public func scheduleMeeting(_ event: EventID, on day: DayKey,
                                invitees: [ContactID], at timestamp: Timestamp) throws {
        try #store(calendar.events, key: day, value: event)
        for invitee in invitees {
            try #store(calendar.invitees, key: event, value: invitee)
        }
        try #store(contacts.lastSync, key: invitees[0], value: timestamp)
    }
}
```

expands (`@MDB_app` inventory → span macro inference: `calendar` readWrite, `contacts` readWrite,
order calendar, contacts) to:

```swift
public func scheduleMeeting(_ event: EventID, on day: DayKey,
                            invitees: [ContactID], at timestamp: Timestamp) throws {
    // 1. open one top-level txn per inferred member, first-touch order (full staging overlap)
    let tx_calendar = try Transaction(env: self.calendar.env, readOnly: false)
    let tx_contacts = try Transaction(env: self.contacts.env, readOnly: false)
    // 2. nested-function formulation — no closures, no ambient storage (inherited from single-env)
    func __mdb_body(_ event: EventID, on day: DayKey, invitees: [ContactID],
                    at timestamp: Timestamp,
                    _ tx_calendar: borrowing Transaction,
                    _ tx_contacts: borrowing Transaction) throws {
        // ONLY verb lines are lowered; everything else is byte-identical:
        try calendar.events.store(key: day, value: event, tx: tx_calendar)
        for invitee in invitees {
            try calendar.invitees.store(key: event, value: invitee, tx: tx_calendar)
        }
        try contacts.lastSync.store(key: invitees[0], value: timestamp, tx: tx_contacts)
    }
    // 3. body throw -> abort ALL (nothing lands)
    do { try __mdb_body(event, on: day, invitees: invitees, at: timestamp, tx_calendar, tx_contacts) }
    catch let error {
        tx_calendar.abort()
        tx_contacts.abort()
        throw error
    }
    // 4. commit pair, first-touch order, nothing between them (narrow window)
    try tx_calendar.commit()
    try tx_contacts.commit()
}
```

Routing: for each `MacroExpansionExprSyntax` with a name in the verb set, read the first argument's
member-access **base identifier** → look up in the inferred env set → emit
`<receiver>.store(..., tx: <route>)`. The only text matching done is base-identifier lookup against the
verb set; no callee-name lists, no receiver scanning beyond the declared/inferred envs.

## What this buys (guarantees vs. the demo's current two-step state)

| Failure mode | Today (two isolated boundaries) | With the span |
|---|---|---|
| body throws in the contacts step | calendar committed, contacts lost — partial logical op durable | both txns abort — nothing lands |
| crash mid-method | full-body window between two separated commits | microseconds between two adjacent commits, deterministic order |
| visibility of partial state | calendar's half visible to readers while contacts pending | nothing visible until the commit pair begins (writes staged in open, uncommitted txns) |
| cross-env atomicity | impossible | impossible (stated honestly; residual window documented) |

Reader-side consistency *across* the pair ("I read both envs and never straddle the commit window") is
the **post-v1 cross-env reader-writer gate** — a separate primitive, out of scope here.

## Usage rules (documented contract)

- Inside a span body, **verb calls** are required for auto-threading; plain op calls must carry
  `tx: tx_calendar` explicitly or they fail to compile (marker-gating, not silent).
- **Forbidden:** calling a single-env `@MDB_transact` boundary on a listed environment inside the span
  (nested `.readWrite` → LMDB writer-mutex deadlock, per env — same forbidden pattern as single-env).
- **Allowed:** `.readWriteChild(parent:)` boundaries with a routed parent (`parent: tx_calendar`) —
  child merges into the span's member txn, committed with the pair.
- Verb on an undeclared receiver base / non-member-access first arg → compile diagnostic (needs the
  `@MDB_app` inventory). `#cursor`-with-delete inside a readOnly member → runtime `EACCES`, documented.
- `@MDB_transact_span` on a method whose body has **no** verbs → diagnostic (an empty boundary).

## Phase 0 — verbs (PREREQUISITE, already planned)

Execute `2026-09-07_093018-verb-macros-marker-gated.md` through its Phase 2: typed-handle companions +
six verb macros + the single-env rewriter that consumes ONLY verb lines (deleting `TXInjectionRewriter`
and `txOperationNames`). The span is built on that machinery.

## Phase 1 — `@MDB_app` container macro + inventory

- `Sources/QuickLMDB/Protocols/` or `Macros.swift`: `public protocol MDB_environment_container {
  associatedtype EnvKey: Hashable; static var mdb_env_inventory: [(name: String, env: Environment)] { get } }`
  (shape TBD at implementation; the point is a compile-time inventory of name → Environment).
- `Sources/QuickLMDBMacros/MDB_app.swift`: `internal struct MDB_app_macro: MemberMacro` — scans stored
  properties whose type conforms to a tiny `MDB_environment` marker protocol (added to the
  `@MDB_environment` core conformance list), emits the inventory member + conformance. Register in
  `Plugin.swift`.
- `@MDB_environment` gains the `MDB_environment` conformance (one-line addition to its expansion).

## Phase 2 — `MDB_transact_span` body macro + inference

- `Sources/QuickLMDB/Macros.swift`: `public macro MDB_transact_span(_ members: [MDB_span_member]? = nil) =
  #externalMacro(...)` (bare form = nil ⇒ infer; explicit list = override). `MDB_span_member` enum:
  `.readWrite(Environment)` / `.readOnly(Environment)` (used only when the override is exercised).
- `Sources/QuickLMDBMacros/MDB_transact_span.swift`: `internal struct MDB_transact_span_macro: BodyMacro`.
  - scan body for verb macro calls → infer envs (base names), modes (write-vs-read), order (first touch);
  - look up each base in the `@MDB_app` inventory (resolve `name` → `name.env` splice);
  - generate K locals, `__mdb_body` (ownership-marked signature mirror), do/catch all-abort,
    commit-pair/close tail; lower verbs via the shared Phase-0 helper with a routing closure
    `{ baseName in tx_<baseName> }`;
  - diagnostics: unknown base, write-verb-on-readOnly-inferred env (only when override pins readOnly),
    empty body, non-verb op without explicit `tx:` is left alone (compiler produces the missing-`tx:` error).
- Register in `Plugin.swift`.

## Phase 3 — expansion fixtures (`MDB_transact_spanExpansionTests`)

Frozen expansions (same `failureHandler` discipline):
- bare span, two readWrite envs, verbs routed to the correct `tx_<env>`;
- inference: an env touched only by `#load` expands to `readOnly: true` + close-without-commit tail;
- mixed: write env commits, read env closes;
- `.readWriteChild(parent: tx_calendar)` boundary call emitted byte-identical (not a verb, untouched);
- non-verb op call WITHOUT `tx:` emitted byte-identical (compiler error is the intentional signal);
- non-verb op call WITH explicit `tx:` untouched;
- explicit-override form (`[.readWrite(calendar)]`) — same expansion, forced mode;
- verbs on a user function named `store`/`load` untouched; unknown-base diagnostic recorded.

## Phase 4 — runtime tests in the hybrid demo

Extend `Tests/QuickLMDBTests/HybridAppDemo.swift` (or a new `SpanRuntimeTests.swift`):
- `HybridApp` becomes `@MDB_app`; `scheduleMeeting`/`dayOverview` become bare spans; same durable-state
  assertions as today's two-step versions;
- **body-throw → nothing lands in EITHER env** (headline guarantee; impossible today);
- mixed-mode span: write calendar + `#load` contacts committed value inside one boundary;
- `.readWriteChild` boundary inside a span (audit row, routed parent) merges then commits with the pair;
- `dayOverview` as an all-read span (readOnly members, no commits);
- explicit-override span (mode forcing) reaches identical state;
- negative: a boundary body with a plain `calendar.events.setEntry` without `tx:` fails to compile
  (covered by fixtures; not a runtime test).

## Phase 5 — docs

- README "Planned evolution" → shipped sections: marker-gated boundaries (verb-only lowering), span
  attribute (bare + override), the `@MDB_app` inventory, best-effort semantics + residual-window note,
  forbidden patterns;
- DocC: `@MDB_transact_span`, `@MDB_app`, `MDB_span_member` symbol docs + transaction-boundary article;
- changelog: verb-only lowering is breaking for the earlier preview (omit-`tx:` op calls in boundaries
  stop compiling); span adds the cross-env guarantee upgrade;
- `v16 vision.md`: planned section gains the span + marker-gating; verification counts refresh.

## Risks / tradeoffs / open questions

- **Inference is a contract change**: with bare form, the mode/order signal lives in *which verbs you
  write and their order*. The override exists for when that's too implicit. Document both clearly.
- **`#cursor` mode**: readOnly by default; writes through a cursor inside a span member need the
  explicit override to `.readWrite` (or a `#cursor` write-variant later). Runtime `EACCES` otherwise.
- **`@MDB_app` required for spans**: adds a one-line attribute on the container. Falls back to a
  diagnostic ("span methods require @MDB_app on the containing type") if forgotten.
- **Attribute signature**: `[MDB_span_member]? = nil` optional array — concrete, existential-free;
  bare form is the default idiomatic use.
- **Noncopyable safety**: K explicit params replicate the proven single-env formulation; no
  borrowed-return-of-stored-noncopyable anywhere (composite-struct temptation documented + rejected).
- **Nested spans / span-under-single-env (child members, v2)**: a span whose members are
  `.readWriteChild(env, parent:)` would make spans composable as subroutines under outer boundaries.
  Deferred — new machinery; flat span lands first.
- **Cross-env reader-writer gate (post-v1)**: closes the straddle-window for participant readers.
  Separate primitive; out of scope here.
- **Verbs must not regress single-env**: Phase 0 is the compatibility surface; span work must not
  change its fixtures.

## Deliverables checklist

- [x] `@MDB_app` container macro: inventory + conformance; `@MDB_environment` emits the marker conformance.
- [x] `@MDB_transact_span` body macro: bare inference (envs/modes/order) + explicit override.
- [x] Verb-only lowering (marker-gating) shared by single-env and span; name-list rewriter deleted.
- [x] Diagnostics: empty body, no-`@MDB_app`, write-on-pinned-readOnly (unknown core names surface as compiler errors at the `self.<name>.env` splice — a body macro cannot see the enclosing type's stored members; recorded in code).
- [x] Expansion fixtures frozen (5 cases: bare/mixed/override/child-pass-through/requires-MDB_app).
- [x] Hybrid demo adopted: `@MDB_app` container; scheduleMeeting/dayOverview as bare spans; body-throw-all-abort test green; override test green.
- [x] Docs aligned (README/DocC/changelog/journal); 0-warning build; full suite green (106 / 12).

### Toolchain deviations recorded (approved outline adjusted where the toolchain forbids the sketched shape)

1. **override payload is `String`** (`.readWrite("calendar")`), not a naked `.readWrite(calendar)` — attribute arguments are type-checked on the type level where instance stored properties are not in scope.
2. **`@MDB_app`'s generated inventory is the public surface, not the span's scan input** — a body macro's lexicalContext exposes the enclosing type's name + attributes but NOT its stored members (verified both via lexicalContext empty member shell and declaration.parent stopping at the function decl). the span gates on the `@MDB_app` attribute (visible) and validates core names through the compiler at the `self.<name>.env` splice.
3. expansion fixtures seed `BasicMacroExpansionContext(lexicalContext:)` by walking the node's parent chain (in-process only; the real compiler supplies it for the runtime path).
