<<<<<<< HEAD
# ``QuickLMDB/Database``

Enables quick, convenient assignment and retrieval of database entries.

## Creating a Database

A ``Database`` can be created (or retrieved) by calling ``Environment/openDatabase(named:flags:tx:)`` on your Environment. This must be done under the existence of an active Transaction.

```
/// Open a transaction for your environment, configured as apropriate.
try someEnvironment.transact(readOnly:false) { someTransaction in
	
	/// Open a database named "my database"
	let database = try someEnvironment.openDatabase(named:"my database", flags:[.create], tx:someTransaction)
=======
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
>>>>>>> documentation
}
```

## Considerations

<<<<<<< HEAD
- Databases can (and **should**) exist outside of the transactions in which they are first created.

- QuickLMDB is best used when all databases are opened in a single transaction and stored for later use.  

- Database structures have a non-exclusive relationship with transactions within their environment.

- Database is optimized for **quick and convenient** access to entries, rather than offering complete access to LMDB's complex features.

	- Database delivers entries in strictly deserialized form. This means that Database will use the `MDB_convertible` protocol to translate the raw memory from `MDB_val` structures into the specified Swift Type before they are returned.

## Topics

### CLMDB Interoperability
=======
- Due to its internal initializer, a database can only be initialized through an ``QuickLMDB/Environment``

- Once a database has been initialized, it is stuck in the environment it was created in

## Topics

### Structures

- ``Database/Flags``

- ``Database/Statistics``

### Instance Properties
>>>>>>> documentation

- ``Database/db_handle``

- ``Database/env_handle``

<<<<<<< HEAD
### Storing and Retrieving Entries

- ``Database/setEntry(value:forKey:flags:tx:)``

- ``Database/getEntry(type:forKey:tx:)``

### Retrieving Metadata

- ``Database/get``

- ``Database/getStatistics(tx:)``
=======
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
>>>>>>> documentation
