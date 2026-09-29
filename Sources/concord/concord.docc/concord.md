# ``concord``

Concord is a typed, transport-agnostic negentropy reconciliation engine over QuickLMDB. A concord round brings two stores holding the same fixed-size-byte-key schema into agreement: fingerprints over key ranges skip matching regions, mismatches split and recurse, and the resulting have/need diff moves values **as bytes** — never decoded into their typed form, never re-encoded.

## The protocol trio

Concord is three small protocols and one engine. Everything else is derived types.

- ``ConcordIndex`` — the store contract. A sorted, fixed-size-key view over one strict database: streaming key walks, range fingerprints (24-byte blake2s over mmap key bytes), and the byte-passthrough pair ``ConcordIndex/loadBytes(_:)`` (a borrowed view out) / ``ConcordIndex/storeBytes(_:_:)`` (a verbatim write in). `Value` is a phantom type parameter that pins the schema; it is never instantiated.
- ``ConcordTransport`` — the networking contract. Typed ``ConcordMessage`` values in both directions. Concord ships no implementation: framing, serialization, and reliability are entirely the developer's.
- ``ConcordSession`` — the pure synchronous engine. `/initiate`, `/reconcileAux`, split, fingerprints, have/need diff, and data transfer; typed ``ConcordError`` for every malformed or inconsistent input, no traps.

## Values travel as their existing bytes

The typed `Value` is never materialized anywhere in concord. The reconcile phase touches keys only; the data phase moves value bytes through ``ConcordByteView``:

- **out of the store** — ``ConcordIndex/loadBytes(_:)`` returns a borrowed view over the value's own mmap page (zero copies).
- **into the store** — ``ConcordIndex/storeBytes(_:_:)`` writes the incoming bytes verbatim (one copy in).

The only copy in the system is a transport's own boundary copy, and only when a transport chooses to detach bytes (`ConcordOwnedBytes` is the Sendable escape hatch; messages and borrowed views are scoped to the synchronous round). The ``ConcordLMDBIndex`` driver pattern:

- the **driver** opens one long-lived `Transaction<Write>` for the whole round (the round is the writable snapshot), opens the database + cursor + ``ConcordLMDBIndex`` with it, runs ``ConcordSession/runRound()``, then commits (or aborts).
- the index — and the cursor it holds — must be **released before the transaction commits**: closing an LMDB cursor after its transaction closed reads freed memory and can trap. scope the index, then commit.
- a round holds the environment's writer lock for its duration; the driver schedules rounds (off-peak, spaced) to bound the writer stall.

## What concord does not ship

wire encoding/framing; any network implementation; basic or raw-table support; multi-database orchestration or a signature handshake; threading or concurrency policy (the engine is synchronous; callers thread it); reindex logic. No typed `Value` decode anywhere.

## Topics

### The protocol trio

- ``ConcordSession``
- ``ConcordIndex``
- ``ConcordTransport``

### The message surface

- ``ConcordMessage``
- ``ConcordSection``
- ``ConcordReconcile``

### The byte view

- ``ConcordByteView``
- ``ConcordBorrowedBytes``
- ``ConcordOwnedBytes``

### Keys, fingerprints, errors

- ``ConcordKey``
- ``Fingerprint``
- ``ConcordError``
- ``ConcordRole``

### The QuickLMDB driver

- ``ConcordLMDBIndex``
