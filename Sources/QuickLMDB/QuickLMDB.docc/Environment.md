#  ``QuickLMDB/Environment``

An LMDB environment: the memory-mapped, single-file (or single-directory) store that ``QuickLMDB/Transaction``s and ``QuickLMDB/Database``s are based on.

## Creating an Environment

An ``Environment`` is created with a system path, the open flags, the memory-map sizing, and the reader/database limits:

```
// an example environment with the noSubDir flag
let someEnvironment = try Environment(path: somePath, flags: [.noSubDir], maxDBs: 64)

// opening a transaction within the environment (mode lives in the type)
let someTransaction = try Transaction<Write>(env: someEnvironment)

// use someTransaction to manage data in the environment
try someTransaction.commit()
```

- ``QuickLMDB/Environment/init(path:flags:mapSize:maxReaders:maxDBs:mode:encrypt:checksum:)`` — the full initializer. when `encrypt:` is provided, the encryption callback + cipher key are registered with the engine before the environment opens (LMDB 1.0 authenticated per-page encryption), and the stored ``QuickLMDB/Environment/flags`` reflect the `.encrypt` / `.remapChunks` bit the registration sets. a checksum implementation may be registered alongside.
- ``QuickLMDB/Environment/flags`` — the flags the environment was opened with.
- ``QuickLMDB/Environment/sync(force:)`` — flush data buffers to disk (needed for `.writeMap` / `.noSync` environments).
- ``QuickLMDB/Environment/readerCheck()`` — reclaim stale reader slots left by dead processes.

## Databases live under transactions

An ``Environment`` does not open databases itself — a ``QuickLMDB/Database`` handle is opened inside a **write** transaction (`Database.init(env:name:flags:tx:)`, or by the `@MDB_environment` macro's generated `open(at:)`, which opens every declared table in one setup write-transaction). the environment is the parent of all transactions, and all databases, in a process.

## Topics

### Open an environment

- ``QuickLMDB/Environment/init(path:flags:mapSize:maxReaders:maxDBs:mode:encrypt:checksum:)``

### Environment state

- ``QuickLMDB/Environment/flags``
- ``QuickLMDB/Environment/sync(force:)``
- ``QuickLMDB/Environment/readerCheck()``

### Flags

- ``QuickLMDB/Environment/Flags``

### Encryption configuration

- ``QuickLMDB/Environment/EncryptionConfiguration``
