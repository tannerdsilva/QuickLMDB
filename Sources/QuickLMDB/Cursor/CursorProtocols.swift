import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

/// the protocol for type-strict cursors
public protocol MDB_cursor_strict:MDB_cursor where MDB_cursor_dbtype:MDB_db_strict {}

/// the primary protocol for dupfixed cursors
public protocol MDB_cursor_dupfixed:MDB_cursor_dupsort where MDB_cursor_dbtype:MDB_db_dupfixed {
	// multiple variants - theres more than meets the eye
	borrowing func opGetMultiple(returning:[MDB_cursor_dbtype.MDB_db_val_type].Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws(LMDBError) -> [MDB_cursor_dbtype.MDB_db_val_type]
	borrowing func opNextMultiple(returning:[MDB_cursor_dbtype.MDB_db_val_type].Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws(LMDBError) -> [MDB_cursor_dbtype.MDB_db_val_type]
}

/// the primary protocol for dupsort cursors
public protocol MDB_cursor_dupsort:MDB_cursor where MDB_cursor_dbtype:MDB_db_dupsort {

	/// returns the number of duplicate entries in the database for this key.
	borrowing func dupCount() throws(LMDBError) -> size_t
	borrowing func opFirstDup(returning:MDB_cursor_dbtype.MDB_db_val_type.Type) throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type
	borrowing func opLastDup(returning:MDB_cursor_dbtype.MDB_db_val_type.Type) throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type
	
	borrowing func opNextDup(returning:MDB_cursor_dbtype.MDB_db_val_type.Type) throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type
	borrowing func opNextNoDup(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	
	borrowing func opPreviousDup(returning:MDB_cursor_dbtype.MDB_db_val_type.Type) throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type
	borrowing func opPreviousNoDup(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)

	borrowing func opGetBoth(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	borrowing func opGetBothRange(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
}

public protocol MDB_cursor_basic:MDB_cursor where MDB_cursor_dbtype:MDB_db_basic {}

/// the core protocol for LMDB cursors, encompassing the most primitive types (MDB_val based - known as MDB_cursor_basic) all the way up to the highest level abstractions (MDB_cursor_dupfixed)
public protocol MDB_cursor<MDB_cursor_dbtype>:Sequence where MDB_cursor_dbtype:MDB_db {

	associatedtype Element = (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)

	/// the database type backing this cursor
	associatedtype MDB_cursor_dbtype:MDB_db
	
	/// the transaction type that is backing this cursor

	/// initialize a new cursor from a valid transaction and database handle
	#if QUICKLMDB_SHOULDLOG
	borrowing func logger() -> Logger?
	#endif
	
	/// primary initializer for a cursor. must be based on a valid database and transaction
	init(db:borrowing MDB_cursor_dbtype, tx:borrowing Transaction) throws(LMDBError)
	
	/// returns the cursor handle primitive that LMDB uses to represent the cursor
	borrowing func cursorHandle() -> OpaquePointer
	
	/// returns the database handle primitive that LMDB uses to represent the database this cursor is associated with
	borrowing func dbHandle() -> MDB_dbi
	
	/// returns the transaction handle primitive that LMDB uses to represent the transaction this cursor is associated with
	borrowing func txHandle() -> OpaquePointer

	// cursor operator functions
	// first variants - are you looking for the first? you're in the right place
	borrowing func opFirst(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	// last variants - skip the line and go straight to the end
	borrowing func opLast(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	// next variants - move forward
	borrowing func opNext(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	// previous variants - take it back
	borrowing func opPrevious(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	// get variants - find your footing
	borrowing func opGetCurrent(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	// set variants - make your mark
	borrowing func opSet(returning:MDB_cursor_dbtype.MDB_db_val_type.Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type
	borrowing func opSetKey(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	borrowing func opSetRange(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)
	
	// write entry function
	/// set an entry in the database with a specified key and value. the operation will be committed with the specified flags.
	borrowing func setEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type, flags:Operation.Flags) throws(LMDBError)
	
	// checking for entries
	borrowing func containsEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws(LMDBError) -> Bool
	borrowing func containsEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws(LMDBError) -> Bool
	
	// delete the current entry
	borrowing func deleteCurrentEntry(flags:consuming Operation.Flags) throws(LMDBError)
	
	// comparing
	borrowing func compareEntryKeys(_ dataL:MDB_cursor_dbtype.MDB_db_key_type, _ dataR:MDB_cursor_dbtype.MDB_db_val_type) -> Int32
	borrowing func compareEntryValues(_ dataL:MDB_cursor_dbtype.MDB_db_key_type, _ dataR:MDB_cursor_dbtype.MDB_db_val_type) -> Int32
	
}