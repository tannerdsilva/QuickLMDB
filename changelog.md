# 16.1.0

- **Marker-gated verb vocabulary inside `@MDB_transact` boundaries.** the verb macros `#store`, `#load`, `#delete`, `#contains`, `#cursor`, `#clear`, `#stats`, `#drop` are now the only auto-`tx:` surface inside a boundary. the body macro lowers exactly the freestanding verb calls (matched by macro name, nothing else) to their tx-bearing operation form and emits every other line byte-identical — the name-list `tx:` injection is deleted, so a plain `setEntry`/`loadEntry`/`cursor(...)` call inside a boundary must carry `tx:` explicitly or it fails to compile. this is a **breaking change** for the v16.0.0 preview shape: boundary bodies written with omit-`tx:` method calls must migrate to verbs (or pass `tx: tx`).
  - verb use OUTSIDE a boundary is a compile-time diagnostic (`must only appear inside an @MDB_transact body`).
  - the pair form `#contains(db, key:, value:)` lowers to the cursor's real `MDB_GET_BOTH` path (a database-level pair check is a silent no-op by key).
  - `#load(db, key:, as:)` remains for raw `MDB_val` handles; typed handles need no `as:`.
  - `#stats(db)` lowers to `dbStatistics(tx:)` (metadata read — never marks a span member write); `#drop(db)` lowers to `deleteDatabase(tx:)` (destructive — the handle is consumed, so the receiver must be a locally-owned raw `Database`, not a stored `self.X` table).
- Added typed-handle companions the verbs lower to: `load(key:tx:)`, `store(key:value:flags:tx:)`, `delete(key:tx:)`, `contains(key:tx:)` on `MDB_db` (one copy inherited by every handle), plus the dupsort pair `delete(key:value:tx:)` on `MDB_db_dupsort`.
- **Cross-environment span boundaries: `@MDB_app` + `@MDB_transact_span`.** `@MDB_app` marks a struct as an environment container (its stored `@MDB_environment` cores become the routing inventory) AND generates a container-level `open(at:mapHeadroom:)` that creates the base + per-core subdirectories and opens every core in one call. `@MDB_transact_span` coordinates ALL of them behind one method: one top-level transaction per core, opened up front; a body throw aborts ALL of them (nothing lands — impossible with two isolated boundaries, the prior shape); write members commit back-to-back in first-touch/declaration order, read members close. bare form infers environments/modes/order from the body's verb calls; the override form (`@MDB_transact_span([.readWrite("calendar")])`) forces them explicitly. honest ceiling (documented): cross-environment commits remain best-effort — a crash between the adjacent commit calls can still split the pair; cross-env atomicity is impossible.
- **`@MDB_environment`'s generated `open(at:)` now creates the base directory as needed** (previously required it to pre-exist).
- **Self-scoped committed reads** on `MDB_db` (protocol-extension members, every handle): `readCommitted(key:)`, `containsCommitted(key:)` and (dupsort) `readCommittedDups(key:)` — each opens its own read-only transaction, reads, and closes it. deliberately NOT boundary verbs: a verb's contract is boundary participation, the opposite of a self-scoped verification read. the suite-level `readViaRawTX`/`loadEntryDirect`-style helpers (open txn manually → read → abort) are replaced by these members.
- Updated docs: the transaction-boundary README + DocC sections now describe the verb contract and the span boundary; examples migrated to verbs/spans.

# 16.0.0

- Added the `@MDB_transact` and `@MDB_environment` macros.
  - `@MDB_transact(.readWrite | .readOnly | .readWriteChild)` is an attached **body macro**: it rewrites the annotated method's body in place so the method itself owns its transaction scope. There is no ambient storage of any kind (no task-local, no thread-local, no registry). Operation call sites inside the body may omit the `tx:` argument — the expansion appends `tx: tx`, where `tx` is the boundary transaction, and commits once on success / aborts exactly once on error.
  - `@MDB_environment(file:flags:maxReaders:maxDBs:mode:)` is schema assembly only: it generates a `static func open(at:mapHeadroom:)` that sizes the memory map, opens the environment, and opens every `Database.X` table in one setup write-transaction.
  - `@MDB_environment` forces `.noTLS` onto the environment unconditionally: reader slots are bound to the transaction object instead of the thread, which is what makes Swift's task-based concurrency safe and what permits sibling read transactions inside boundaries.
- Transaction relationship management: boundaries open TOP-LEVEL transactions of their mode, and every parent/child + sibling relationship is the engine's own default, pinned by regression tests (sibling writes under reads, sibling reads under writes/reads, write-child merges, EINVAL/badReaderSlot engine errors). Composition inside a write boundary is explicitly `.readWriteChild(parent:)`; a raw `.readWrite` nested inside another without `parent:` deadlocks on LMDB's non-recursive writer mutex and is a documented forbidden pattern.
- Removed the internal `_MDBTransactionScope` transaction registry (superseded by the body macro architecture).
- Dropped all `MDB_RESERVE` support: removed `reserveEntry`, the returning `MDB_db_set_entry` overload (and its internal static), the `Operation.Flags.reserve` case, and the reserve value helpers. reserve-based write-without-initialize is unsupported for now.
- Removed the `value:` parameter from the DB-level `containsEntry` — the argument was a silent no-op (`mdb_get` resolves by key only), making pair-existence checks answer false-TRUE for any existing key. pair checks now live on cursors only (`cursor.containsEntry(key:value:)`, implemented with `MDB_GET_BOTH`).
- Fixed `Transaction` so its deinit no longer aborts an already-committed transaction.
- The transaction-bearing protocol API (`Transaction`, `MDB_db`, `MDB_cursor`, the `Database.X` handles) is unchanged.
- The database + cursor `MDB_*_static` functions and `LMDBError` moved into a new standalone target `QuickLMDBFunctionalInterop` — a handle-level C bridge with no QuickLMDB types. its public api surface is the `consuming MDB_val` functional layer (`MDB_db_get_entry`/`MDB_db_set_entry`/`MDB_cursor_get_entry`/…); the raw handle functions are module-internal. QuickLMDB bridges through the public surface via `@_exported import`; public behavior is unchanged. covered by a new `QuickLMDBFunctionalInteropTests` target (27 tests driven by raw CLMDB).

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