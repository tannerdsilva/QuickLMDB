#  ``QuickLMDB/Environment``

Class that allows for ``QuickLMDB/Transaction``s to be made with ``QuickLMDB/Database``s and ``QuickLMDB/Cursor``s

## Creating an Environment

An ``Environment`` can be created by calling ``QuickLMDB/Environment/init(path:flags:mapSize:maxReaders:maxDBs:mode:)``

```
// An example environment with the noSubDir flag
let someEnvironment = try Environment(path: somePath, flags: [.noSubDir], maxDBs: 64)

//Opening a transaction within the environment
try someEnvironment.transact(readOnly: false) { thisTransaction in 

    //use thisTransaction to manage data in the environment

}
```
