import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

@MDB_cursor_basics()
/// a database cursor - allows for more complex navigation of entries.
public final class Cursor:MDB_cursor_basic {
	/// a basic cursor uses a basic database type
	public typealias MDB_cursor_dbtype = Database

	public func makeIterator() -> DatabaseIterator<Cursor> {
		return DatabaseIterator(self)
	}
}

/// a general purpose duplicate entry iterator for databases that is dupsort configured.
// public struct DatabaseDupIterator<CursorType:MDB_cursor_dupsort>:IteratorProtocol, Sequence {
// 	// the underlying cursor that we are using to iterate
// 	private let cursor:CursorType
// 	// will be true if the first entry has not been returned yet
// 	private let focusKey:CursorType.MDB_cursor_dbtype.MDB_db_key_type
// 	// does the cursor need to seek to the first key?
// 	private var needsSeek:Bool = true
	
// 	/// initialize a general purpose dupsort iterator based on the native key type for the database
// 	/// - parameters:
// 	/// 	- cursor: the cursor that this iterator will be representing
// 	/// 	- key: the key that the cursor will read duplicate value entries from
// 	internal init(_ cursor:consuming CursorType, key inputKey:consuming CursorType.MDB_cursor_dbtype.MDB_db_key_type) {
// 		self.cursor = cursor
// 		self.focusKey = inputKey
// 	}
	
// 	/// returns the next database entry to be consumed in the sequence.
// 	public mutating func next() -> (key:CursorType.MDB_cursor_dbtype.MDB_db_key_type, value:CursorType.MDB_cursor_dbtype.MDB_db_val_type)? {
// 		switch needsSeek {
// 			case false:
// 				do {
// 					return (key:focusKey, value:try cursor.opNextDup(returning:CursorType.MDB_cursor_dbtype.MDB_db_val_type.self))
// 				} catch {
// 					return nil
// 				}
// 			case true:
// 				defer {
// 					needsSeek = false
// 				}
// 				do {
// 					return try cursor.opSetKey(returning:(key:CursorType.MDB_cursor_dbtype.MDB_db_key_type, value:CursorType.MDB_cursor_dbtype.MDB_db_val_type).self, key:focusKey)
// 				} catch {
// 					return nil
// 				}
// 		}
// 	}
// }

/// a general purpose entry iterator for databases using their native type.
public struct DatabaseIterator<CursorType:MDB_cursor>:IteratorProtocol, Sequence {
	// the underlying cursor that we are using to iterate the database contents
	private let cursor:CursorType
	private var first:Bool
	internal init(_ cursor:consuming CursorType) {
		self.cursor = cursor
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

extension Cursor {
	
	@MDB_cursor_basics()
	@MDB_cursor_dupfixed()
	@MDB_cursor_RAW_access_members() // this is needed so that members that typically would be extended can be implemented as borrowing. when the same code is applied as an extension, the compiler does not allow the functions to be `borrowing`. hence, this macro.
	public final class DupFixed<D:MDB_db_dupfixed>:MDB_cursor_dupfixed {
		public typealias MDB_cursor_dbtype = D
		public func makeIterator() -> DatabaseIterator<DupFixed<D>> {
			return DatabaseIterator(self)
		}
	}
	
	@MDB_cursor_basics()
	@MDB_cursor_RAW_access_members() 
	public final class DupSort<D:MDB_db_dupsort>:MDB_cursor_dupsort {
		public func makeIterator() -> DatabaseIterator<DupSort<D>> {
			return DatabaseIterator(self)
		}
		public typealias MDB_cursor_dbtype = D
	}

	@MDB_cursor_basics()
	@MDB_cursor_RAW_access_members() // this is needed so that members that typically would be extended can be implemented as borrowing. when the same code is applied as an extension, the compiler does not allow the functions to be `borrowing`. hence, this macro.
	public final class Strict<D:MDB_db_strict>:MDB_cursor_strict {
		public typealias MDB_cursor_dbtype = D
				public func makeIterator() -> DatabaseIterator<Strict<D>> {
			return DatabaseIterator(self)
		}
	}
}
