# DEBT — the open items after two consumer migrations (wiremand, pricedb)

status: live working list. this file is the factual settlement of a
software-skeptic audit (2026-09-12) over wiremand, pricedb, and this library.
each item records what is unproven or undisposed, why it matters, and what
"done" looks like. items are ordered by the damage they currently hedge.

---

## 1. multi-env atomic boundaries + multi-label joins are unexercised by any consumer

**the claim being hedged:** the typed-environment layer's flagship
capabilities — a boundary whose verbs address TWO environment types, and a
`#MDB_transacted` join of a MULTI-env sibling (the equal-env-set contract,
the shell's multi-transaction open/commit/abort, the write-under-write
deadlock doc) — are pinned by macro fixtures and library tests only.

**evidence:** neither consumer has one. wiremand's four cores are fully
independent; all 25 `#MDB_transacted` joins are single-env. pricedb's
`writePrices(spot: SpotCore)` carries a typed core parameter but verbs only
`PriceCore.self` — the spot write is a bare sibling call in its own
transaction (by design, matching the pre-migration behavior). `@MDB_layout`
has zero uses anywhere.

**why it matters:** C1's "the center is proven" claim only survives for the
exact shape classes consumers exercised. every new capability surface shipped
and unexercised has so far carried a latent defect (see item 3).

**done when:** a real consumer path (or a committed demo at production shape)
contains a boundary that joins across two environment types, verified on
macOS and Linux.

---

## 2. no concurrency test: a boundary read racing a concurrent writer on a MUTABLE key

**the claim being hedged:** joined reads see a consistent snapshot.

**evidence:** every runtime test writes immutable/append-only keys. pricedb
runs a 60s price-capture writer against an unsynchronized HTTP read path —
the facade even multiplexes several price-core snapshots where the
pre-migration code passed one transaction — and the audit judged this benign
ONLY because writes are append-only-per-date (a fixed historical key is
immutable). that write discipline is the daemon's, not the API's guarantee.

**why it matters:** for a mutating-key workload (the wiremand shape), the
same snapshot multiplexing would be a torn-read bug, and nothing in the
library proves it can't happen.

**done when:** a test with a concurrent writer mutating one key while a
boundary repeatedly reads the (key, value) composite, asserting no torn
observations across many iterations, green on macOS and Linux.

---

## 3. disposition `open(at:fileName:)` (1bc3fcc) and typed `deleteEntry` (807c2aa)

**the claim being hedged:** both were parent investments built for pricedb's
plan whose end-state did not use them.

**evidence:** `open(at:fileName:)` is invoked by no generated core — pricedb's
FiatCore/SpotCore ended up hand-rolled `MDB_environment` conformances with
their own `open(at:…)` signatures (for the UNNAMED main-DBI tables, an
orthogonal reason). typed `deleteEntry` is used by no consumer — MainCore's
metadata became a typed `Strict` table, so deletes go through `#delete`.
both have tests, but no real use.

**why it matters:** unverified API surface is a liability — it must be
maintained, documented, and trusted without evidence. (precedent: the one
unexercised macro surface already carried a dead-parameter bug, `@MDB_layout`
headroom, fixed 2026-09-12.)

**done when:** each surface either gains a real consumer use, or is removed
from `Macros.swift` / `DBRawTypedConvenience.swift` with its tests and any
fixtures.

---

## 4. the spurious-`try` before `#cursor` (5 warnings in pricedb) — decide, don't defer

**the facts:** pricedb's clean build emits 5
`no calls to throwing functions occur within 'try' expression` warnings at
`try #cursor(…)` sites whose closures don't throw. removing the `try` broke
expansion for closures containing `#if` blocks (statement-join trivia
corruption); keeping it warns. a body macro cannot decide try-ness when the
closure's throwing set is `#if`-dependent at expansion time.

**why it matters:** the warning bar both consumers hold (zero in own sources,
wiremand standard) is broken by a macro-behavior residual that is not
currently documented as accepted.

**done when:** either (a) the behavior is documented as accepted with the
recommended spelling (`try` retained for closure-verb sites), or (b) the
lowering is changed so the emitted call form never requires a conditional
`try`, with byte-frozen fixtures for both `#if` and non-`#if` closure bodies.

---

## 5. a cross-repo gate: parent changes must compile the consumers

**the claim being hedged:** "consumer friction → parent fix" is a working
iteration loop.

**evidence:** one team owns the parent and both children; nothing builds the
pair together. every consumer so far surfaced a NEW macro-generation bug the
previous consumer did not: wiremand (trailing-trivia parse), pricedb
(generic clause, inout `&`), the audit (`@MDB_layout` dead headroom). the
defect set is being discovered, not closing.

**why it matters:** a parent change can regress a consumer that built fine —
silently, until the next consumer hits it.

**done when:** a script/workflow pins each consumer to QuickLMDB HEAD, builds
it, and runs its suite (Linux for wiremand) on every parent change.
