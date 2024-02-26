import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

// /// the protocol for type-strict cursors
public protocol MDB_cursor_strict:MDB_cursor where MDB_cursor_dbtype:MDB_db_strict {}

public protocol MDB_cursor_dupfixed:MDB_cursor where MDB_cursor_dbtype:MDB_db_dupfixed {
	// multiple variants - theres more than meets the eye
	borrowing func opGetMultiple(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> [MDB_cursor_dbtype.MDB_db_val_type]
	borrowing func opNextMultiple(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> [MDB_cursor_dbtype.MDB_db_val_type]
}

public protocol MDB_cursor_basic:MDB_cursor where MDB_cursor_dbtype.MDB_db_key_type == MDB_val, MDB_cursor_dbtype.MDB_db_val_type == MDB_val {}

/// the protocol for open ended data storage type
public protocol MDB_cursor<MDB_cursor_dbtype>:Sequence where MDB_cursor_dbtype:MDB_db {

	associatedtype Element = (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	
	associatedtype Iterator = DatabaseIterator<Self>

	/// the database type backing this cursor
	associatedtype MDB_cursor_dbtype:MDB_db
	/// the transaction type that is backing this cursor

	/// initialize a new cursor from a valid transaction and database handle
	#if QUICKLMDB_SHOULDLOG
	borrowing func logger() -> Logger?
	init(db:borrowing MDB_cursor_dbtype, tx:borrowing Transaction) throws
	#else
	init(db:borrowing MDB_cursor_dbtype, tx:borrowing Transaction) throws
	#endif
	
	/// returns the cursor handle primitive that LMDB uses to represent the cursor
	borrowing func cursorHandle() -> OpaquePointer
	
	borrowing func dbHandle() -> MDB_dbi
	
	borrowing func txHandle() -> OpaquePointer
	
	// cursor operator functions
	// first variants - are you looking for the first? you're in the right place
	borrowing func opFirst(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	borrowing func opFirstDup(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	// last variants - skip the line and go straight to the end
	borrowing func opLast(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	borrowing func opLastDup(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	// next variants - move forward
	borrowing func opNext(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	borrowing func opNextDup(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	borrowing func opNextNoDup(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	// previous variants - take it back
	borrowing func opPrevious(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	borrowing func opPreviousDup(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	borrowing func opPreviousNoDup(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	// get variants - find your footing
	borrowing func opGetBoth(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	borrowing func opGetBothRange(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	borrowing func opGetCurrent(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	// set variants - make your mark
	// (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	borrowing func opSet(returning:MDB_cursor_dbtype.MDB_db_val_type.Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> MDB_cursor_dbtype.MDB_db_val_type
	borrowing func opSetKey(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	borrowing func opSetRange(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	
	// write entry function
	/// set an entry in the database with a specified key and value. the operation will be committed with the specified flags.
	borrowing func setEntry(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type, flags:Operation.Flags) throws

	// checking for entries
	borrowing func containsEntry(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) throws -> Bool
	borrowing func containsEntry(key:MDB_cursor_dbtype.MDB_db_key_type) throws -> Bool

	// delete the current entry
	borrowing func deleteCurrentEntry(flags:Operation.Flags) throws

	// comparing
	borrowing func compareEntryKeys(_ dataL:MDB_cursor_dbtype.MDB_db_key_type, _ dataR:MDB_cursor_dbtype.MDB_db_val_type) -> Int32
	borrowing func compareEntryValues(_ dataL:MDB_cursor_dbtype.MDB_db_key_type, _ dataR:MDB_cursor_dbtype.MDB_db_val_type) -> Int32
	
	// returns the number of duplicate entries in the database for this key.
	borrowing func dupCount() throws -> size_t
}

public final class Cursor<D:MDB_db_basic>:MDB_cursor_basic {
    
	public typealias MDB_cursor_dbtype = D

	/// this is the pointer to the `MDB_cursor` struct associated with a given instance.
	private let _cursor_handle:OpaquePointer
	public borrowing func cursorHandle() -> OpaquePointer {
		return _cursor_handle
	}
	
	/// this is the database that this cursor is associated with.
	private let _db_handle:MDB_dbi
	public borrowing func dbHandle() -> MDB_dbi {
		return _db_handle
	}
	
	/// pointer to the `MDB_txn` struct associated with a given instance.
	private let _tx_handle:OpaquePointer
	public borrowing func txHandle() -> OpaquePointer {
		return _tx_handle
	}
	
	#if QUICKLMDB_SHOULDLOG
	private let _logger:Logger?
	public borrowing func logger() -> Logger? {
		return _logger
	}
	#endif
	/// opens a new cursor instance from a given database and transaction pairing.
	public init(db:borrowing MDB_cursor_dbtype, tx:borrowing Transaction) throws {
		var buildCursor:OpaquePointer? = nil
		let openCursorResult = mdb_cursor_open(tx.txHandle(), db.dbHandle(), &buildCursor)
		guard openCursorResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openCursorResult)
		}
		self._cursor_handle = buildCursor!
		self._db_handle = db.dbHandle()
		self._tx_handle = tx.txHandle()
		#if QUICKLMDB_SHOULDLOG
		self._logger = db.logger()
		#endif
	}
	
	deinit {
		// close the cursor
		mdb_cursor_close(_cursor_handle)
	}
}

public struct DatabaseIterator<CursorType:MDB_cursor>:IteratorProtocol, Sequence {
	private let cursor:CursorType
	private var first:Bool
	internal init(_ cursor:borrowing CursorType) {
		self.cursor = copy cursor
		self.first = true
	}

	public mutating func next() -> (key:CursorType.MDB_cursor_dbtype.MDB_db_key_type, value:CursorType.MDB_cursor_dbtype.MDB_db_val_type)? {
		switch first {
			case true:
				first = false
				return try? cursor.opFirst(returning:(key:CursorType.MDB_cursor_dbtype.MDB_db_key_type, value:CursorType.MDB_cursor_dbtype.MDB_db_val_type).self)
			case false:
				return try? cursor.opNext(returning:(key:CursorType.MDB_cursor_dbtype.MDB_db_key_type, value:CursorType.MDB_cursor_dbtype.MDB_db_val_type).self)
		}
	}
}


public final class Strict<D:MDB_db_strict>:MDB_cursor_strict {

	public typealias MDB_cursor_dbtype = D

	/// this is the pointer to the `MDB_cursor` struct associated with a given instance.
	private let _cursor_handle:OpaquePointer
	public borrowing func cursorHandle() -> OpaquePointer {
		return _cursor_handle
	}
	
	/// this is the database that this cursor is associated with.
	private let _db_handle:MDB_dbi
	public borrowing func dbHandle() -> MDB_dbi {
		return _db_handle
	}
	
	/// pointer to the `MDB_txn` struct associated with a given instance.
	private let _tx_handle:OpaquePointer
	public borrowing func txHandle() -> OpaquePointer {
		return _tx_handle
	}
	
	#if QUICKLMDB_SHOULDLOG
	private let _logger:Logger?
	public borrowing func logger() -> Logger? {
		return _logger
	}
	/// opens a new cursor instance from a given database and transaction pairing.
	public init(db:borrowing MDB_cursor_dbtype, tx:borrowing Transaction) throws {
		var buildCursor:OpaquePointer? = nil
		let openCursorResult = mdb_cursor_open(tx.txHandle(), db.dbHandle(), &buildCursor)
		guard openCursorResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openCursorResult)
		}
		self._cursor_handle = buildCursor!
		self._db_handle = db.dbHandle()
		self._tx_handle = tx.txHandle()
		self._logger = db.logger()
	}
	#else
	public init(db:borrowing MDB_cursor_dbtype, tx:borrowing Transaction) throws {
		var buildCursor:OpaquePointer? = nil
		let openCursorResult = mdb_cursor_open(tx.txHandle(), db.dbHandle(), &buildCursor)
		guard openCursorResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openCursorResult)
		}
		self._cursor_handle = buildCursor!
		self._db_handle = db.dbHandle()
		self._tx_handle = tx.txHandle()
	}
	#endif
	
	deinit {
		// close the cursor
		mdb_cursor_close(_cursor_handle)
	}
}
