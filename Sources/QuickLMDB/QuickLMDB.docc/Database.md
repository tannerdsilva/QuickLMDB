#  ``QuickLMDB/Database``

Structure that when placed in an ``QuickLMDB/Environment``, allows for storage of data.

## Creating a Database

A ``Database`` can be created by calling ``QuickLMDB/Environment/openDatabase(named:flags:tx:)`` on a given ``QuickLMDB/Environment`` object.

```
// Open a transaction from your environment, configured as apropriate.
try someEnvironment.transact(readOnly:false) { thisTransaction in

    // Open a database with the newly opened transaction.
    let myDatabase = try someEnvironment.openDatabase(named:nil, tx:thisTransaction)
                                                                                
    // Any interactions with the database should happen here.
}
```

## Considerations

- Due to its internal initializer, a database can only be initialized through an ``QuickLMDB/Environment``

- Once a database has been initialized, it is stuck in the environment it was created in

## Topics

### Structures

- ``Database/Flags``

- ``Database/Statistics``

### Instance Properties

- ``Database/db_handle``

- ``Database/env_handle``

- ``Database/name``

### Creating a cursor

- ``Database/cursor(tx:)``

### Retrieving Entries/Data

- ``Database/getEntry(type:forKey:tx:)``

- ``Database/getFlags(tx:)``

- ``Database/getStatistics(tx:)``

- ``Database/containsEntry(key:tx:)``

### Setting Entries

- ``Database/setEntry(value:forKey:flags:tx:)``

### Deleting Entries

- ``Database/deleteEntry(key:tx:)``

- ``Database/deleteEntry(key:value:tx:)``

- ``Database/deleteAllEntries(tx:)``

### Managing Database

- ``Database/closeDatabase()``

- ``Database/removeDatabase(tx:)``
