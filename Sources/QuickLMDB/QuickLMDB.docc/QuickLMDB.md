# ``QuickLMDB``

QuickLMDB is designed to be a easy, efficient, and uncompromising integration of the LMDB library. QuickLMDB does not hide access to the underlying LMDB core, allowing you to directly utilize the core LMDB API at any time. Likewise, QuickLMDB makes it very easy to write high-level code that is simultaneously memory-safe and high-performance. 

### Why QuickLMDB?

- QuickLMDB is the only known Swift library to allow full transactional control over an Environment. This is crucial to achieving high performance.

- QuickLMDB allows direct access to the LMDB memorymap without overhead or copies. This is also a unique feature for Swift-based LMDB wrappers.

## LMDB basics

The basic object relationship for QuickLMDB is as follows:

- ``QuickLMDB/Environment`` is the foundation of QuickLMDB, as it is in the LMDB core. Environments are created with a system path. 

	- ``QuickLMDB/Environment``s create ``QuickLMDB/Transaction``s
	
	- ``QuickLMDB/Environment`` can open ``QuickLMDB/Database``s under the existence of a ``QuickLMDB/Transaction``
	
		- ``QuickLMDB/Database`` can store and retreive key/value pairs

	- A ``QuickLMDB/Transaction`` may open child transactions, in certain contexts
	
	- ``QuickLMDB/Database`` can open ``QuickLMDB/Cursor`` under the existence of a ``QuickLMDB/Transaction``

## Notes on API

Here are a few notes about the QuickLMDB API design. Keeping these notes in mind will help you use the API as efficiently as possible.

### MDB_convertible protocol

This is the native serialization and deserialization protocol for QuickLMDB.

- Required when using ``QuickLMDB/Database`` (for convenience). 

- Optional when using ``QuickLMDB/Cursor`` (allowing for zero-copy access to your data).

- Custom objects (classes and structs) can conform to this protocol with minimal code.

	- Objects that conform to `LosslessStringConvertible` can conform to ``QuickLMDB/MDB_convertible`` with ZERO additional lines of code.

### Database struct

In the spirit of the core LMDB API, QuickLMDB's ``QuickLMDB/Database`` struct is designed to be approachable and convenient. 

- Handles serialization on your behalf with `QuickLMDB/MDB_convertible` protocol. Standardized serialization eliminates the need for redundant code, and as a result, reduces the risk of bugs.

- Returns a specified `MDB_convertible` Type directly from database, rather than expecting you to deserialize data entries on your own.

### Cursor class

QuickLMDB's ``QuickLMDB/Cursor`` class also follows the spirit of the underlying LMDB API, by offering advanced access to a given database.

- No built in serialization or data copies.

- Returns the explicit `MDB_val` structs that the LMDB core is utilizing under the hood.

	- When reading entries, this allows the developer to chose when to deserialize a given data entry.

	- Serialization and deserialization of returned `MDB_val` can occur with a single line of code.
	
- Conforms to Swift's `Sequence` protocol, allowing a cursor to be used in a loop with a single line of code.

### Lifecycle management

QuickLMDB has reasonable default behavior when managing the lifecycle of ``QuickLMDB/Transaction``s and ``QuickLMDB/Cursor``s.

- Transaction blocks that return normally will be committed.

- Transaction blocks that throw an error will cause the transaction to abort.

- At any time within a transaction block, a developer may call ``QuickLMDB/Transaction/commit()``, ``QuickLMDB/Transaction/abort()``, ``QuickLMDB/Transaction/reset()``, or ``QuickLMDB/Transaction/renew()`` to force their own behavior on a transaction.
