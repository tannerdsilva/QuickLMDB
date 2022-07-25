#  ``QuickLMDB/Cursor``

Enables complex navigation and traversal of ``QuickLMDB/Database`` contents.

## Creating a Cursor

A ``Cursor`` can be created by calling ``QuickLMDB/Database/cursor(tx:)`` on a given ``QuickLMDB/Database`` object. This must be done under the existence of an active Transaction.

```
// Open a transaction from your environment, configured as apropriate.
try someEnvironment.transact(readOnly:false) { thisTransaction in

	// Open a database with the newly opened transaction.
	let myDatabase = try someEnvironment.openDatabase(named:nil, tx:thisTransaction)

	// Create a cursor from the database and transaction.
	let myCursor = try myDatabase.cursor(tx:thisTransaction)
	
	// Any interactions with the cursor should happen here.
}
```

## Considerations

- Cursors have an exclusive relationship with the Transaction and Database in which they were created.

	- Cursors cannot exist outside of their associated Transaction.

- Unlike ``QuickLMDB/Database``, ``QuickLMDB/Cursor`` does **NOT** integrate any decoding functionality.

	- Lack of binary decoding (and requisite copying of data through the decoding process) allows for much higher performance in traversing a database.

- ``QuickLMDB/Cursor`` faithfully returns `MDB_val` objects as provided from LMDB. No other types are returned.

	- You are responsible for safely handling these `MDB_val` objects within their transactions. These values point to data directly in the memorymap.

	- You are responsible for any deserialization that may need to be done with the returned values.

		- ``MDB_decodable`` has been implemented for many of the base Foundation types to make decoding from raw `MDB_val`'s straightforward (with a single line of code).

- QuickLMDB takes ``MDB_encodable`` objects as function arguments for keys and values.

	- Cursor will also accept raw `MDB_val`'s as arguments for keys and values, since this type has been extended to conform to ``MDB_encodable``.

- ``QuickLMDB/Cursor`` conveniently conforms to the `Sequence` protocol.

	- Loops can be written with a single line of code.

## Looping Database Contents with Cursor

```
// define a cursor for the sake of demonstration
let thisCursor = try someDatabase.cursor(tx:currentTransaction)

// this is a database loop
for curKeyValueEntry in thisCursor {
	// process each entry in the database here
}
```

## Topics

### Storing Entries

- ``Cursor/setEntry(value:forKey:flags:)``

### Retrieving Entries

- ``Cursor/Operation``

- ``Cursor/getEntry(_:key:value:)``

- ``Cursor/getEntry(_:key:)``

- ``Cursor/getEntry(_:value:)``

- ``Cursor/getEntry(_:)``

### Checking for Existence of Entries

- ``Cursor/containsEntry(key:value:)``

- ``Cursor/containsEntry(key:)``

### Removing Entries

- ``Cursor/deleteEntry(flags:)``

### Comparing Values

- ``Cursor/compareKeys(_:_:)``

- ``Cursor/compareValues(_:_:)``

### CLMDB Interoperability

- ``Cursor/cursor_handle``

- ``Cursor/txn_handle``

- ``Cursor/db_handle``

### Sequence Protocol

- ``Cursor/makeIterator()``

- ``Cursor/CursorIterator``

- ``Cursor/Element``

- ``Cursor/Iterator``
