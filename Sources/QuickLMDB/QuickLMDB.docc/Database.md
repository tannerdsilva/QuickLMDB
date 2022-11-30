# ``QuickLMDB/Database``

Enables quick and convenient access to database entries.

## Creating a Database

A ``Database`` can be created (or retrieved) by calling ``QuickLMDB/Environment/openDatabase(named:flags:tx:)``. This must be done under the existence of an active Transaction.

Example:

```
// Assuming an environment variable exists named "someEnvironment". See Environment documentation for details.
let someEnvironment = Environment(...)

// Open a transaction for your environment, configured as apropriate
try someEnvironment.transact(readOnly:false) { someTransaction in
	
	// Open a database named "my database". Specify flags as needed.
	let database = try someEnvironment.openDatabase(named:"my database", flags:[.create], tx:someTransaction)
	
	// Any interactions with the database should happen here.
}
```

## Considerations

- Databases can (and **should**) exist outside of the transactions in which they are first created.

- QuickLMDB is best used when all databases are opened in a single transaction and stored for later use.

- Database structures have a non-exclusive relationship with transactions within their environment.

- Database is optimized for **quick and convenient** access to entries, rather than offering complete access to LMDB's complex features.

	- Database delivers entries in strictly deserialized form. This means that Database will use the `MDB_convertible` protocol to translate the raw memory from `MDB_val` structures into the specified Swift Type before they are returned.

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

### Retrieving Entries & Info

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

- ``Database/deleteDatabase(tx:)``
