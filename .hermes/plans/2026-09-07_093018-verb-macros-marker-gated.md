# Marker-Gated Verb Macros (replace TXInjectionRewriter name-list) — Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.
> Scope note: `~/workspace/rawdog` is **read-only reference** — the rawdog macro convention
> (transform only explicitly-marked code) is the inspiration, never modified here.

**Goal:** Make `@MDB_transact`'s transaction threading fully predictable by replacing the
name-list `TXInjectionRewriter` with explicit freestanding verb macros
(`#store` / `#load` / `#delete` / `#contains` / `#cursor` / `#clear`) as the *only*
auto-`tx:` surface inside transaction boundaries.

**Architecture:** Inside a boundary, the body macro consumes verb macro calls
(`MacroExpansionExprSyntax` from a closed, documented set) and lowers them to the
tx-bearing operation call (`#store(db, key:, value:)` → `db.store(key:, value:, tx: tx)`).
Outside a boundary, each verb's own expression-macro expansion throws a compile-time
diagnostic ("must only appear inside an @MDB_transact body"). All non-verb code in the
body is left byte-identical — no callee-name matching, so a user function named
`setEntry`/`cursor`/… is unreachable by the rewriter. The `let tx` injection, the nested
`__mdb_body` formulation, do/catch commit-once/abort-once, and
`.readWriteChild(parent:)` all stay unchanged.

**Tech Stack:** SwiftSyntax / SwiftSyntaxMacros (already in `QuickLMDBMacros`),
QuickLMDB protocols, Swift Testing.

---

## Baseline (verified at plan time)

- Branch `v22-rewrite` @ `192b463`. Build: 0 warnings. Tests: 48 / 6 suites green.
- `TXInjectionRewriter` (private `SyntaxRewriter`, `MDB_transact.swift:107-145`) appends
  `tx: tx` to `FunctionCallExprSyntax` whose callee name ∈ `txOperationNames`
  (`MDB_transact.swift:77-80`: loadEntry/setEntry/containsEntry/deleteEntry/deleteAllEntries/
  cursor/reserveEntry/dbStatistics/dbFlags/deleteDatabase), unless an explicit `tx:`
  is already present.
- Standalone verb macros are **not yet declared** anywhere; `Macros.swift` currently
  declares only the three public macros; `Plugin.swift` registers 8 types.

## Proposed approach

1. Add typed-handle convenience companions so verbs are type-complete without
   `as:`/`flags: []`: `load(key:) -> V?`, `store(key:value:flags: = [])`,
   `delete(key:)`, `delete(key:value:)`, `contains(key:)`, `contains(key:value:)`
   (all `tx:`-bearing) on `Database.Strict` / `Database.DupSort` / `Database.DupFixed`.
2. Declare six public **freestanding expression macros** (`#store`, `#load`, `#delete`,
   `#contains`, `#cursor`, `#clear`) whose own expansion **always throws a diagnostic**
   — the context-consuming fallback for use outside a boundary.
3. Rewrite the body macro's rewriter to match **only** `MacroExpansionExprSyntax` with a
   macro name in the verb set, and emit the lowered operation call (deterministic,
   same fixture-hardening discipline as today). Delete the `FunctionCallExpr`/name-list
   path entirely (no dual mode).
4. Migrate every in-repo boundary body to verbs; the compiler becomes the migration
   checker (any operation call omitting `tx:` now fails to compile — intentional).
5. Update strict expansion fixtures to the new contract; add fixtures for verbs in all
   three modes, the outside-boundary diagnostic, explicit-`tx:`-untouched, and a
   user-defined `setEntry` helper remaining untouched.
6. Update docs (README, DocC, changelog, journal) — the verb vocabulary moves from
   "Planned" to shipped; the name-list imperfection is deleted.

---

## Phase 1 — typed-handle companions (prerequisite)

### Task 1: `load(key:) -> V?` companion

**Objective:** give typed handles a value-type-inferred load.

**Files:**
- Modify: `Sources/QuickLMDB/Database/Database.swift` (or new `Database/DBTypedConvenience.swift`)
- Test: `Tests/QuickLMDBTests/QuickLMDBTests.swift` or `MacroRuntimeTests.swift`

**Step 1:** Add (for `Database.Strict<K,V>`; DupSort/DupFixed are generated handle types —
put the extension on the `Database.Strict`/`DupSort`/`DupFixed` structs):

```swift
extension Database.Strict {
    // typed load — the value type rides on the handle; notFound returns nil
    @available(*, noasync)
    public borrowing func load(key: borrowing K, tx: borrowing Transaction) throws -> V? {
        try? loadEntry(key: key, as: V.self, tx: tx)
    }
}
```

**Step 2:** Verify compile + runtime: `swift test --filter MacroRuntimeTests` green.

### Task 2: remaining companions

Same pattern on the three typed handles: `store(key:borrowing K, value:consuming V, flags: Operation.Flags = [], tx:) throws`, `delete(key:borrowing K, tx:) throws`, `delete(key:borrowing K, value:consuming V, tx:) throws`, `contains(key:borrowing K, tx:) throws -> Bool`, `contains(key:borrowing K, value:consuming V, tx:) throws -> Bool`.

**Verify:** `swift build` 0 warnings; write one test per companion in `MacroRuntimeTests.swift`
(round-trip store→load, delete→notFound, contains present/absent, value-form on a `DupSort` table).

### Task 3: commit phase 1

```bash
git add -A && git commit -m "feat: typed-handle companions (load/store/delete/contains) for verb macros"
```

---

## Phase 2 — verb macros + rewriter change

### Task 4: declare the six public verb macros

**Files:**
- Modify: `Sources/QuickLMDB/Macros.swift`
- Modify: `Sources/QuickLMDBMacros/Plugin.swift`
- Create: `Sources/QuickLMDBMacros/MDB_verbs.swift`

**Step 1:** Declare in `Macros.swift` (freestanding):

```swift
public macro store(_ db: some Any, key: some Any, value: some Any, flags: QuickLMDB.Operation.Flags = []) = #externalMacro(module: "QuickLMDBMacros", type: "store_macro")
```

(Repeated for `load`, `delete`, `contains`, `cursor`, `clear` with their signature shapes;
`load` gains an optional `as:` argument for the raw `Database` handle.)

**Step 2:** `MDB_verbs.swift`: one `internal struct store_macro: ExpressionMacro` (etc.).
Each implementation **throws a diagnostic unconditionally** and returns a placeholder
expression — it never runs inside a boundary (the body macro consumes the call first):

```swift
internal struct store_macro: ExpressionMacro {
    static func expansion(of node: some FreestandingMacroExpansionSyntax,
                          in context: some MacroExpansionContext) throws -> ExprSyntax {
        context.diagnose(Diagnostic(node: Syntax(node), message: "must only appear inside an @MDB_transact body"))
        return "nil"
    }
}
```

**Step 3:** register all six in `Plugin.swift`.

**Verify:** `swift build` 0 warnings; a scratch file using `#store(...)` outside a boundary
reports the diagnostic (compile-time).

### Task 5: rewrite the injector to a verb-lowering rewriter

**Files:**
- Modify: `Sources/QuickLMDBMacros/MDB_transact.swift:107-145` (replace `TXInjectionRewriter`)
- Modify: `Sources/QuickLMDBMacros/MDB_transact.swift:77-80` (delete `txOperationNames`)

**Step 1:** Replace with `VerbLoweringRewriter: SyntaxRewriter` whose `visit` matches
`MacroExpansionExprSyntax`, reading `node.macroName.text` against the closed set
`["store","load","delete","contains","cursor","clear"]`. Lowering (all emit `tx: tx`):

| verb call (as written) | lowered expression (emitted by body macro) |
|---|---|
| `#store(db, key:, value:)` | `db.store(key: key, value: value, tx: tx)` |
| `#store(db, key:, value:, flags: f)` | `db.store(key: key, value: value, flags: f, tx: tx)` |
| `#load(db, key:)` | `db.load(key: key, tx: tx)` |
| `#load(db, key:, as: V.self)` (raw) | `db.loadEntry(key: key, as: V.self, tx: tx)` |
| `#delete(db, key:)` / `#delete(db, key:, value:)` | `db.delete(key: key, tx: tx)` / `db.delete(key: key, value: value, tx: tx)` |
| `#contains(db, key:)` / `(db, key:, value:)` | `db.contains(...)` / `db.contains(key:, value:, tx: tx)` |
| `#cursor(db) { c in … }` | `db.cursor(tx: tx) { c in … }` (trailing closure preserved) |
| `#clear(db)` | `db.deleteAllEntries(tx: tx)` |

Wrinkle from today's code to carry over: if the verb call's argument list serializes
without parens (trailing-closure-only), rebuild explicit parens the same way
`MDB_transact.swift:126-132` does, so output stays deterministic for fixtures.
An explicit `tx:` on a verb is **not** supported (verbs are tx-free by contract — explicit
threading uses the method/helper form); if one is seen, emit a diagnostic.

**Step 2:** delete the `FunctionCallExprSyntax` matching branch and `txOperationNames`.

**Verify:** `swift build --build-tests` — expect compile errors in migrated files only
(none yet — tests still call methods without `tx:`, so the build will fail loudly here;
that is the intended signal for Phase 3).

### Task 6: expansion fixtures for the new contract

**Files:**
- Modify: `Tests/QuickLMDBMacroTests/MDB_transactExpansionTests.swift`
- Create: `Tests/QuickLMDBMacroTests/MDB_verbExpansionTests.swift`

**Step 1:** In `MDB_verbExpansionTests.swift`, fixture `#store`/`#load`/`#delete`/
`#contains` in `.readWrite` and `.readOnly`, `#cursor` with a closure, `#clear`, and the
three-mode coverage; assert the exact lowered text (freeze spacing, same discipline as
today's fixtures, with the recorded `failureHandler`).

**Step 2:** a fixture proving a user function named `setEntry` (different arg list)
inside a boundary is emitted **byte-for-byte untouched**.

**Step 3:** a fixture for verb-inside-boundary output has **no** diagnostic, and a
standalone `#store(...)` (spelled in a bare `func`) records the diagnostic via the
`failureHandler`.

**Verify:** run only this suite: `swift test --filter "verb expansion"`.

---

## Phase 3 — migrate in-repo call sites, delete the name list

### Task 7: migrate `Tests/QuickLMDBTests/MacroRuntimeTests.swift`

Boundary bodies (omit-`tx:` sites) become verbs:
- `writePrimary` L40 → `#store(primary, key: key, value: value)`
- `writeBoth` L45-46, `writeBothThrowing` L51-52 → two `#store`
- `readOnlyRead` L58 → `try #load(primary, key: key)`
- `readOnlyWriteAttempt` L63 → `#store` (still asserts `EACCES`)
- `writePrimaryViaHelper` L74 (explicit `tx: tx`) — stays
- `writeNested` L83, `writeNestedThrowing` L88 → `#store(primary, ...)`
- `outerWrite` L94, `outerWriteChildAbort` L100 → `#store(primary, ...)`
- `scanAll` L110-116, `scanCount` L120-127 → `#cursor(primary) { cursor in … }`
- `storeOne` L74, `loadEntryDirect` L134, `readDupsViaRawTX` L164, `containsDupViaRawTX`
  L176 (explicit `tx:`) — stay

**Verify:** `swift test --filter "body macro architecture"` green.

### Task 8: migrate `Tests/QuickLMDBTests/RelationshipBoundaries.swift`

- `innerRead` L29 → `try #load(primary, key: key)`
- `touchWrite` L39 → `#store(primary, key:, value:)`
- `writeThenSiblingRead` L45 → `#store` then `#load`
- `siblingReadThenWrite` L52 → `#load`, then `#store`
- `outerReadThenInnerRead` — unchanged (calls another boundary)

**Verify:** `swift test --filter "Transaction relationship"` green.

### Task 9: migrate `Tests/QuickLMDBTests/UsagePatternDemo.swift` (the showcase)

`store` L41 → `#store`; `fetch` L47 → `#load`; `storeBoth` L64-65 → two `#store`;
`storeWithAudit` L74 + `logAudit` L80 → two `#store`; `validateThenStore` L89 → `#load` then
`#store`; `currentValue` L95 → `#load`; `storeOne` L58 and `readRaw` L131 (explicit `tx:`) — stay.
Update the header NOTE comment (verb vocabulary is now shipped, not planned).

**Verify:** `swift test --filter "Boundary usage patterns"` green.

### Task 10: compiler-driven sweep

`swift build --build-tests` → fix any remaining omit-`tx:` call site the compiler flags
(none should remain); confirm `QuickLMDBTests.swift` (commented legacy code) untouched.

**Verify:** full `swift test` — original 48 tests + phase-1 companion tests all green.

### Task 11: commit phases 2–3

```bash
git add -A && git commit -m "feat: marker-gated verb macros; drop TXInjectionRewriter name-list attribution"
```

---

## Phase 4 — new runtime/negative tests

### Task 12: regression tests for untouched bodies

In `MacroRuntimeTests.swift` (or new `VerbSafetyTests.swift`):
- a boundary that calls a **user-defined helper named `setEntry`** (unrelated signature —
  e.g. `func setEntry(_ label: String) -> Int`) and asserts it ran untouched;
- a boundary that mixes verbs and explicit-`tx:` method calls (both paths work);
- runtime `#cursor` + `#clear` + `#delete(key:value:)` (DupSort) exercises.

**Verify:** `swift test --filter VerbSafety` green.

### Task 13: commit phase 4

```bash
git add -A && git commit -m "test: verb-macro safety + negative coverage"
```

---

## Phase 5 — documentation alignment

### Task 14: README + DocC

- Move the "Planned evolution" paragraph (README L34 / DocC L124) into the shipped
  `@MDB_transact` description: verbs are the auto-`tx:` surface; non-verb operation calls
  in a boundary must carry `tx:` explicitly; a short verb table + example.
- Add the typed companions to the `Database struct`/macros note.

### Task 15: changelog (v16.1 or amends the 16.0.0 entry)

- "verb macros (`#store/#load/#delete/#contains/#cursor/#clear`)" replace the name-list
  attribution; outside-boundary use is a compile-time diagnostic; plain method calls
  inside a boundary now require explicit `tx:` (breaking for the earlier preview);
  typed-handle companions added.

### Task 16: `v16 vision.md`

- Planned section → new "Implemented" note (verbs shipped phase 1; `#reserve/#stats/#drop`
  stay phased); delete the "Call attribution is by name list" imperfection bullet;
  add settled bullet for marker-gated attribution; refresh verification/tests counts.

### Task 17: commit docs

```bash
git add -A && git commit -m "docs: verb macros shipped; name-list attribution removed"
```

---

## Phase 6 — final verification

### Task 18: clean build + full suite + docc pass

- `swift package clean && swift build` → **0 errors / 0 warnings**.
- `swift test` → all suites green (list the final count; record it in the journal).
- Read-through of README/docc/changelog for consistency with shipped API (like the last
  doc pass). Commit any stragglers.

---

## Risks / tradeoffs / open questions

- **Breaking for the preview shape:** existing bodies that omitted `tx:` on plain method
  calls stop compiling; they must use verbs or explicit `tx:`. That is the entire point
  (predictability), and it is loud (compile-time), never silent. Call this out in the
  changelog entry.
- **Two idioms coexist** (verbs for auto-threading, explicit `tx:` for deliberate
  threading) — no magic in between. Decide whether the README frames verbs as "the"
  idiom.
- **Raw `Database` (MDB_val) handles** need the `as:` form of `#load`; typed handles do
  not. Covered by the two `#load` shapes above.
- **Verb naming** — `#store` vs the user-suggested `#setEntry`: locked to the planned
  `#store` here; trivially renamable before Task 4 if you prefer API alignment.
- **No `tx:` override on verbs** (explicit threading stays on the method/helper surface).
  Revisit if a genuine use case appears.
- **`#cursor`/`#clear` in phase 1** grow the surface; both are cheap and were in the
  phase-1 plan already. `#reserve/#stats/#drop` remain later phases.
- **rawdog boundary honored:** nothing in this plan touches `~/workspace/rawdog`.
- **Unknown unknowns:** macro-expansion ordering (body macro consumes the verb call
  before the standalone verb expands — the standalone expansion must *never* be
  reachable inside a boundary; verified by the outside-boundary fixture in Task 6).

---

## Deliverables checklist

- [ ] Six public verb macros declared + registered + diagnostic-bearing fallbacks.
- [ ] Typed-handle companions with tests.
- [ ] Body macro lowers verbs (deterministic, fixture-frozen); name list deleted.
- [ ] All in-repo call sites migrated; compiler-driven sweep clean.
- [ ] Expansion fixtures: verbs all modes + outside-diag + user-`setEntry`-untouched.
- [ ] Runtime safety suite green (verb + explicit hybrid, user helpers untouched).
- [ ] README/DocC/changelog/journal aligned; 0-warning build; full suite green.
