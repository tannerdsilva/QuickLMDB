# QuickLMDB

QuickLMDB is designed to be a quick and efficient wrapper to the LMDB library (while being open enough to allow perfect interoperability with the core LMDB functions).

QuickLMDB is the successor project to the RapidLMDB project. QuickLMDB strives towards the same goals as RapidLMDB, and offers many improvements over the previous project.

The basic object relationship for QuickLMDB is as follows

- Environments are the foundation of QuickLMDB, as they are in LMDB. Environments are created with a system path. 

	- Envrionments create Transactions
	
	- Environments can open Databases under the existence of a Transaction
	
	- Databases can store and retreive key/value pairs

	- Transactions can open subtransactions
	
	- Databases can open Cursors

QuickLMDB implements two protocols for storing and retrieving data from the database.
