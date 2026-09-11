# QuickLMDB — consolidated design

The single design document for the current QuickLMDB transaction architecture.
consolidates the earlier `v16 vision` journal and the clean-slate iterated
design journal into one record, then adds the schema-layer roadmap
(environments + databases: their declarations and initializations).

**Status (2026-09-11):** the tree carries the **typed-environment
transaction layer** — every environment is its own `@MDB_environment` type;
`@MDB_transact` makes INSTANCE methods on those types transactional units with
no transaction vocabulary on the authored surface; the typed verb family
(`#store(E.self, database: \.table, key:…)`) carries the environment type and
a KeyPath to the table; the environment set is inferred from the verbs;
multi-environment boundaries take the other cores as typed parameters;
`#MDB_transacted` is the join marker; `@MDB_layout` is the arrangement helper
(open + inventory). sections 1–3 below describe the PRIOR "boundary dialect"
and schema-roadmap shapes and are HISTORICAL — the typed-environment layer
superseded the `environments:` attribute form, the trailing
`#MDB_entry_load`/`#MDB_entry_store` verbs, the per-core `Root` shells, and
the layout's `_mdb_open_*` factory/static design. the operating principles
(compile-time-first, zero ambient state, explicit composition by joining,
derived defaults) still hold; `Transaction<M>` capability typing is ratified.

---

## 0. the architecture at a glance

- **IO/transaction layer (DONE)** — `@MDB_transact(_:environments:)` (attached
  body + peer; shell/wrapped-sibling), `#MDB_transacted(_:)` (Design-B join
  marker), `#MDB_entry_load` / `#MDB_entry_store` trailing verbs,
  `@MDB_environment` (schema assembly, kept). `struct Transaction` stays
  public; the raw engine surface (`Environment`, `Database`/`Cursor`, typed
  companions, `readCommitted` family, the interop tier) is unchanged below the
  boundary layer.
- **the legacy v16 surface (REMOVED)** — `@MDB_transact`, `@MDB_transact_span`,
  `@MDB_app`, and the receiver-based verbs were shed; section 2 archives what
  they were.
- **schema layer (PLANNED)** — section 3: the visionary roadmap for how
  environments and databases are DECLARED and INITIALIZED, aligned with the
  foundation's principles.

test surface: 10 expansion fixtures byte-frozen + 16 real-engine runtime tests
(port slice + club-app demo) across 11 suites, 0 warnings.

---

## 1. foundation — the IO/transaction layer (ratified, built, verified)

### 1.1 operating principles (what every layer must honor)

- **compile-time-first.** the compiler knows the schema shape at build time; a
  macro layer expresses that knowledge — the runtime never registers or
  discovers anything.
- **zero ambient state.** no task-local, no thread-local, no registry. every
  generated artifact is local and explicit.
- **marker-gated rewriting.** only the freestanding verbs and the join marker
  are rewritten in a boundary body; every other line passes byte-identical, so
  the raw surface (cursors, dup iteration, zero-copy) works directly inside a
  boundary with the injected `tx_<E>` name.
- **derived names.** environment `E` ↔ transaction variable `tx_<E>`: one
  spelling, one derivation, no hand-written plumbing.
- **explicit composition by joining.** `#MDB_transacted(callee(args))` rewrites
  into the callee's wrapped sibling threading this boundary's transaction —
  one transaction across the composed call (atomic for writes; joined reads
  see this boundary's own uncommitted state).
- **"repeat as few characters and names as possible."** ceremony is added only
  where Swift's type system cannot express the intent.

### 1.2 modes + orchestration

`MDB_transact_mode` is the ratified pair — `.readOnly` and `.readWrite`.
`@MDB_transact` is attached **body + peer**:

- the body scrapes the method and replaces it with a SHELL: `let tx_<E> = try
  Transaction(env: <E>.env, readOnly: <mode>)` per listed environment, a call
  into the wrapped sibling (`tx_<E>: tx_<E>`, overload resolution selects the
  sibling), and the mode-driven close — readOnly aborts on throw AND success
  (a read leaf never commits); readWrite aborts on throw and COMMITS on
  success.
- the peer emits the WRAPPED SIBLING: same signature + `tx_<E>: borrowing
  Transaction` per environment; its body is the scraped body with verbs
  lowered and joins rewritten. ownership shape is the proven v16 formulation
  (tx values flow in as `borrowing` params; the shell owns the lifecycle;
  each tx consumed once per path).

### 1.3 the two read modes inside a write boundary

- `#MDB_transacted(eventOn(day))` — JOINED read: same transaction, sees the
  boundary's own uncommitted state ("child view").
- `eventOn(day)` plain — SIBLING read: its shell opens a separate read
  transaction, last committed state only ("validate against durable data").

### 1.4 verbs, the `try` rule, the equal-env-set contract

- `#MDB_entry_load(environment:database:key:)` → `database.load(key:tx_<E>)`
- `#MDB_entry_store(environment:database:key:value:)` →
  `database.store(key:value:tx_<E>)`

`try` belongs AT the verb and the join (both lower to throwing calls).
standalone use is a hard diagnostic. the join rewrite passes the CALLER's full
tx label set, so a callee's wrapped sibling must declare exactly those labels —
the equal-env-set contract (a single-env helper called from a multi-env
boundary does not compile; loud and named at the call site). an escape hatch
(a per-call environments subset) is recorded but not designed.

### 1.5 engine facts still load-bearing

- sibling opens are legal per the relationship matrix (.noTLS owns each
  read's reader slot; Swift tasks may migrate threads); a second top-level
  write on a thread with a live write deadlocks LMDB's writer mutex — joining
  avoids it entirely.
- cross-env commits are best-effort: a body throw aborts ALL member
  transactions, but a crash between adjacent commit calls can split the pair.
  within one environment, joined writes are fully atomic.

### 1.6 constraints + port findings

- `environments:` attribute arguments are evaluated at TYPE scope → cores must
  be attribute-reachable (today: static stored properties). the schema-layer
  roadmap (section 3) resolves this properly.
- naming is final: `@MDB_transact` (adopted 2026-09-10), `#MDB_transacted`,
  `#MDB_entry_load` / `#MDB_entry_store`, `@MDB_environment`, `@MDB_table`.
- read-only-write on a `.readOnly` boundary is the engine's runtime access
  violation, pinned; the compile-time lint is a later pass.
- fixtures are byte-frozen against the real compiler's re-indentation (tabs at
  member level, one abort item per env, blank separators).

### 1.7 covered-by-declaration (no new macros here)

cursors and the DB convenience functions are handled: the typed companions
(`load`/`store`/`delete`/`contains` + `readCommitted` family) are
protocol-extension members every handle inherits, and the explicit-`tx:`
surface works inside boundaries. transactions are handled by the boundary
dialect itself. the remaining un-architected layer is the SCHEMA layer.

---

## 2. archive — the shipped 16.1.0 surface (REMOVED 2026-09-10, history)

The entire legacy transactional-boundary surface was shed: `@MDB_transact`,
`@MDB_transact_span`, `@MDB_app`, `MDB_span_member`,
`MDB_environment_container`, the receiver-based verb vocabulary (`#store`,
`#load`, `#delete`, `#contains`, `#cursor`, `#clear`, `#stats`, `#drop`), and
their expansion suites and runtime pins. `MDB_transact_mode` was trimmed to
the ratified pair (`.readWriteChild`'s child-object relationship is superseded
by Design-B joining; the boundary keeps a syntactic diagnostic).

what it was (briefly): `@MDB_transact` was an attached body macro wrapping the
body in a nested local `__mdb_body(_ tx: borrowing Transaction)` — the wrapped
sibling of the new dialect is that nested function promoted to a peer-emitted
overload. child composition used explicit `parent:` handoff and a separate
child transaction object. the wrapped sibling / join replaces it.

## 3. the schema layer — environments & databases: visionary roadmap (PLANNED)

### 3.1 the gap

Two pieces are currently un-architected relative to the foundation:

1. **databases have no declaration macro.** a table is spelled entirely as a
   stored property type — `public let sheets: Database.Strict<SlotKey,
   SlotRecord>` — plus the `@MDB_environment` scan that opens it. there is no
   surface for a table NAME override (name = property name is the fixed rule),
   for flags that the Swift type cannot express, or for custom comparators at
   declaration time.
2. **the layout story is gone.** the shed `@MDB_app` provided a multi-core
   container (`open(at:)` creating per-core subdirs, opening every core with
   no per-env path plumbing, attribute-reachable inventory). removing it left
   the new dialect with the hand-rolled container in the demo app: manual
   static-core `try!` factories, manual path joining, manual per-core open —
   ceremony the foundation promised to eliminate. the attribute-type-scope
   wall (section 1.6) is the direct symptom.

### 3.2 principles for the schema layer (mirroring the foundation)

1. **derived defaults everywhere, explicit only where Swift fails.**
   - table name = property name (existing); subtype (Strict/DupSort/DupFixed)
     = the declared type; env file = declared at the core; per-core subdir =
     property name; map size = current file size + headroom, recomputed at
     every open; one setup write-transaction opens all tables.
   - a bare `Database.X` property needs ZERO attributes — byte-identical to
     today. the table macro exists only for the non-derivable knobs.
2. **attribute-reachability doctrine.** boundary methods live on CONTAINERS,
   and the container carries attribute-reachable core accessors — resolving
   both the type-scope wall and the single-env-owner case (a boundary method
   ON a core dissolves: the single-env case is a one-core container).
3. **zero ambient state, all generated.** the schema macro emits static
   inventories and static accessors; nothing registers at runtime.
4. **initialization semantics retained.** typed dup tables assign their native
   comparator in the setup transaction (already the typed-handle inits'
   behavior); the env macro's "exactly env + Database.X tables" contract
   stands and extends naturally.

### 3.3 the proposed macro surface

**A. `@MDB_environment(...)` — KEPT as the core declaration.** no contract
change. candidate v2 addition (optional): a generated static table inventory
(name → type) for docs and tooling.

**B. NEW — the layout/container macro: `@MDB_layout(...)` (RATIFIED name;
the shed name `@MDB_app` stays retired — the umbrella term is gone).** attached
to the container struct owning N cores:

- scans stored properties that are `@MDB_environment` core structs (the
  inventory; core = property whose type conforms to `MDB_environment`),
- generates a container `open(at:mapHeadroom:)`: creates the base directory +
  one subdirectory per core (named after the stored property), opens every
  core through its generated `open(at:)`, assembles `Self` — the demo's
  hand-rolled ceremony becomes the macro,
- generates the ATTRIBUTE-REACHABLE core accessors (the boundary's
  `environments:` needs the cores as static stored properties — see decision
  #3 below for the mechanism), plus a static inventory (name → type) for
  docs/tooling,
- becomes the documented home of `@MDB_transact` methods (single-env case:
  one core; no more manual static cores).

**C. NEW — per-table declaration via `@MDB_table(name:flags:)`** (RATIFIED
surface: **name and flags only**), attached to `Database.X` stored properties
inside a core:

- `name: String = <property name>` — the explicit-name escape hatch,
- `flags: <MDB_db_flags> = []` — flags the Swift type cannot express
  (`reverseKey`, `reverseValue`, `integerKey`, `integerDup`, …); the subtype
  (Strict/DupSort/DupFixed) stays in the type,
- **comparators are NOT a knob.** the sort implementation comes WITH the type
  strictness of the key and value types: `MDB_comparable` is the protocol that
  wraps rawdog's byte-sort/compare into an `MDB_val`-compatible C function, and
  the typed handle inits already assign those comparators in the setup
  transaction. a table's ordering is guaranteed by its key/value types — there
  is nothing left for a macro to declare.
- ZERO attributes = the default case (bare property, name from property,
  no extra flags).

the `@MDB_environment` scan CONSUMES `@MDB_table` when it builds the setup
table opens (name override, extra flags), keeping one setup transaction and
the derived-defaults rule.

### 3.4 layout & initialization theory (mapped to the design)

- **one table per access pattern, subtype = cardinality** (Strict / DupSort /
  DupFixed) remains the consumer's schema discipline; the macro layer
  reflects it rather than inventing a new table DSL — the typed handle IS the
  declaration.
- **environments split by workload** — the container maps core → its own
  subdir/file; per-env flags/readers/dbs are declared at the core; map sized
  per env at every open. the layout macro is the lever-5 machinery.
- **migration/versioning — deferred.** not in scope now (ratified); a later
  pass may add versioned env filenames or a documented convention.

### 3.5 decisions (ratified) + open questions

**RATIFIED:**

1. the container macro is `@MDB_layout`. the shed `@MDB_app` name stays
   retired (no umbrella naming).
2. the table macro is `@MDB_table(name:flags:)` — NAME and FLAGS only.
   comparators are type-derived via `MDB_comparable` and are not a macro knob.
4. versioned-env migration — deferred entirely.
5. raw `Database` (MDB_val) tables stay supported in the schema.
6. **the UX mandate (ratified, emphatically):** every macro goes to all
   lengths possible within its scope and place — anything technically
   implementable that is in-scope is IN SCOPE, no missed opportunities. the
   validation surface below is mandatory, not aspirational.

**OPEN — decision #3 (the attribute-reachability mechanism), restated
clearly:**

the boundary's `environments: calendar, contacts` spelling demands the cores
resolve at ATTRIBUTE scope, which forces them to be STATIC STORED properties.
static stored property initializers cannot throw, and opening an environment
throws. so the generated accessor is necessarily a lazy factory:
`static let calendar = { try! CalendarCore.open(at: <path>) }()`. the tradeoff
is a crash (not a catchable error) on first use when the environment cannot
open. the only degree of freedom left is the PATH SOURCE, since a runtime
path would require mutable/ambient static state (off the table):

- **(a) compile-time base path on the macro** — `@MDB_layout(basePath:
  "data")` (or a fixed derivation); the accessors bake resolved paths;
  zero per-core ceremony; dynamic-path consumers (tests) declare their own
  base or keep a hand-rolled static-core container (the current demo pattern).
- **(b) keep only `Self.open(at:) throws -> Self` and drop the static
  accessors** — loses the ratified `environments: calendar, contacts` spelling
  (attribute scope can't name value-typed properties).
- **(c) mutable static setup** — rejected (ambient state, doctrine).

working model: (a).

### 3.6 the validation & UX surface (no missed opportunities)

each schema macro validates everything it can diagnose at expansion time, with
friendly diagnostics instead of compiler foreignness:

**`@MDB_environment` (existing contract, extended):**
- struct only; must contain exactly `env: Environment` + `Database.X` tables;
  `file:` argument required and non-empty.
- table name uniqueness within the core; collision with the auto-reserved LMDB
  internal names diagnosed.

**`@MDB_table` (new):**
- target must be a stored property whose type is `Database` or `Database.X<…>`
  — otherwise a clear "target must be a table property" diagnostic.
- must be declared inside an `@MDB_environment` core struct (else a
  "tables belong inside an environment core" diagnostic).
- `name:` must be non-empty, a valid LMDB table name (no `/`, no NUL), and
  unique within the core; a name-absent zero-attribute property still derives
  from the property name (identity case pinned by fixture).
- `flags:` consistency with the declared type: a `dupSort`/`dupFixed` flag on
  a `Database.Strict`, or a flag contradicting the typed subtype, is a
  suspicion the macro diagnoses (the Swift type is the source of truth);
  `integerKey`/`integerDup` requiring integer-mapped key/value types is
  cross-checked against the RAW backing where possible.
- a `@MDB_table` on a `let` vs the property shape: only stored properties
  are valid targets.

**`@MDB_layout` (new):**
- struct only; every stored property that is not a core (a type conforming to
  `MDB_environment`) is rejected with a "layout containers hold only
  environments" diagnostic — unless genuinely stateless helpers are explicitly
  whitelisted (decision convenience).
- generated static accessor names cannot collide with the container's own
  members (diagnosed; arbitrary-name member generation).
- per-core subdirectory names derived from property names are path-safe by
  construction (Swift identifiers); anything unresolvable is diagnosed.
- a boundary method on the container referencing an unknown core still fails
  via the compiler at the generated `tx_<E>`/`self.<name>` splice (the
  boundary-macro member-invisibility wall) — the layout macro cannot be the
  boundary's eyes, but it CAN ensure the inventory it generates is exactly the
  attribute-reachable set.

### 3.7 landing sequence (post-ratification)

1. **`@MDB_table(name:flags:)` + `@MDB_environment` consumption — LANDED (2026-09-10).**
   - `MDB_db_flags` made fully public (the table macro's `flags:` was previously
     crippled — `reverseKey`/`dupSort`/`dupFixed`/`reverseDup` were
     private/internal, unusable from consumer modules).
   - derived-defaults rule byte-frozen: a bare `Database.X` property produces
     IDENTICAL output to pre-`@MDB_table` (`name: <property>`, `flags:
     [.create]`); the identity case is a frozen fixture.
   - name override + flag union: `@MDB_table(name: "x", flags: [.reverseKey])`
     emits `name: "x", flags: QuickLMDB.MDB_db_flags([.create]).union([...])`;
     raw `Database` tables accept dup flags (no type conflict).
   - validation surfaced: non-property / non-table targets, tables outside a
     core, empty/NUL table names, duplicate resolved names, dup-flags on a
     `Database.Strict` — all friendly messages, fixture-pinned.
   - port finding: the generated `Self(...)` init labels are the PROPERTY names
     (the on-disk override applies only to `name:`); comparing resolved vs
     property names was required.
   - harness note: schema fixtures use the seeded `file.expand(contextGenerator:)`
     path (the table macro gates on the enclosing core; `assertMacroExpansion`'s
     empty lexicalContext spuriously fails it).
   - real-engine pin: a renamed/flagged core opens with `dbName() == "event_log"`
     and round-trips through raw ops.
2. `@MDB_layout` + static core accessors (decision #3 mechanism — option A:
   compile-time base path) + `open(at:)` + fixtures; migrate the demo container
   (ClubApp) onto it; pin the single-env-owner resolution (one-core container)
   and the attribute-type-scope fix.
3. docs/docc + this document updated as the schema layer lands.
