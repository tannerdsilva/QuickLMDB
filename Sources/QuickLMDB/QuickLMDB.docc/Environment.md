#  ``QuickLMDB/Environment``

Class that allows for ``QuickLMDB/Transaction``s to be made with ``QuickLMDB/Database``s and ``QuickLMDB/Cursor``s

## Creating an Environment

An ``Environment`` can be created by calling ``QuickLMDB/Environment/init(path:flags:mapSize:maxReaders:maxDBs:mode:)``

```
// an example environment with the noSubDir flag
let someEnvironment = try Environment(path: somePath, flags: [.noSubDir], maxDBs: 64)

// opening a transaction within the environment (mode lives in the type)
let someTransaction = try Transaction<Write>(env: someEnvironment)

// use someTransaction to manage data in the environment
try someTransaction.commit()
