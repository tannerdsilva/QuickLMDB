#  ``QuickLMDB/Cursor``

``QuickLMDB/Cursor`` enables complex navigation and traversal of ``QuickLMDB/Database`` contents.

## Creating a Cursor

A ``Cursor`` can be created by calling ``QuickLMDB/Database/cursor(tx:)`` on a given ``QuickLMDB/Database`` object.

```
// Open a transaction from your environment, configured as apropriate.
try someEnvironment.transact(readOnly:false) { thisTransaction in

	// Open a database with the newly opened transaction.
	let myDatabase = try someEnvironment.openDatabase(named:nil, tx:Transaction)

	// Create a cursor from the database and transaction.
	let myCursor = try myDatabase.cursor(tx:thisTransaction)
	
	// Any interactions with the cursor should happen here.
}
```

## Considerations

- Unlike ``QuickLMDB/Database``, ``QuickLMDB/Cursor`` does **NOT** integrate any decoding functionality.

	- Lack of binary decoding (and requisite copying of data through the decoding process) allows for much higher performance in traversing a database.

- ``QuickLMDB/Cursor`` faithfully returns `MDB_val` objects as provided from LMDB. No other types are returned.

	- You are responsible for safely handling these `MDB_val` objects within their transactions.

	- You are responsible for any deserialization that may need to be done with the returned values.

		- ``MDB_decodable`` has been implemented for many of the base Foundation types to make decoding from raw `MDB_val`'s straightforward (with a single line of code).

- QuickLMDB takes ``MDB_encodable`` objects as function arguments for keys and values.

	- Cursor will also accept unserialized, raw `MDB_val`'s as arguments for keys and values, since this type has been extended to conform to ``MDB_encodable``.

- ``QuickLMDB/Cursor`` conveniently conforms to the `Sequence` protocol.

	- Loops can be written with a single line of code.

## Topics

### Storing Entries

- ``Cursor/setEntry(value:forKey:flags:)``

### Retrieving Entries

- ``Cursor/getEntry(_:key:value:)``

- ``Cursor/getEntry(_:key:)``

- ``Cursor/getEntry(_:value:)``

- ``Cursor/getEntry(_:)``

### Checking for Existence of Entries

- ``Cursor/containsEntry(key:value:)``

- ``Cursor/containsEntry(key:)``

### Removing Entries

- ``Cursor/deleteEntry(flags:)``


