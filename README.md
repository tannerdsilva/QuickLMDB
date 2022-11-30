# QuickLMDB

QuickLMDB is designed to be a easy, efficient, and uncompromising integration of the LMDB library. QuickLMDB does not hide access to the underlying LMDB core, allowing you to directly utilize the core LMDB API at any time. Likewise, QuickLMDB makes it very easy to write high-level code that is simultaneously memory-safe and high-performance. 

- QuickLMDB is the only known Swift library to allow full transactional control over an Environment. This is crucial to achieving high performance.

- QuickLMDB allows direct access to the LMDB memorymap without overhead or copies. This is also a unique feature for Swift-based LMDB wrappers.

## Full Documentation

QuickLMDB is fully documented. This documentation is available [HERE](https://quicklmdb.com/documentation). Documentation may be generated from source using `swift-docc`.

## LMDB basics

The basic object relationship for QuickLMDB is as follows:

- Environments are the foundation of QuickLMDB, as they are in LMDB. Environments are created with a system path. 

	- Envrionments create Transactions
	
	- Environments can open Databases under the existence of a Transaction
	
		- Databases can store and retreive key/value pairs

	- Transactions may open child transactions, in certain contexts
	
	- Databases can open Cursors

## Notes on API

### MDB_convertible protocol

This is the native serialization and deserialization protocol for QuickLMDB.

- Required when using Database (for convenience). 

- Optional when using Cursor (allowing for zero-copy data access).

- Custom objects (classes and structs) can conform to this protocol with minimal code.

	- Objects that conform to `LosslessStringConvertible` can conform to `MDB_convertible` with ZERO additional lines of code.
	
	
### Lifecycle management

QuickLMDB has reasonable default behavior when managing the lifecycle of a ``QuickLMDB/Transaction`` and ``QuickLMDB/Cursor``.

- Transaction blocks that return normally will be committed

- Transaction blocks that throw an error will cause the transaction to abort

- At any time in a transaction block, a developer may call ``Transaction/

### Database struct

In the spirit of the core LMDB API, QuickLMDB's `Database` struct is designed to be approachable and convenient. 

- Handles serialization on your behalf with `MDB_convertible` protocol. Standardized serialization means less opportunity bugs in your code.

- Returns a specified `MDB_convertible` Type directly from database, rather than expecting you to deserialize data entries on your own.

### Cursor class

QuickLMDB's `Cursor` class also follows the spirit of the underlying LMDB API, by offering advanced access to a given database.

- No built in serialization or data copies.

- Returns the explicit `MDB_val` structs that the LMDB core is utilizing under the hood.

	- When reading entries, this allows the developer to chose when to deserialize a given data entry.

	- Serialization and deserialization of returned `MDB_val` can occur with a single line of code.
	
- Conforms to Swift's `Sequence` protocol, allowing a cursor to be used in a loop with a single line of code.