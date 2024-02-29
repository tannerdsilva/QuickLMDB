import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

@MDB_cursor_basics()
public final class Cursor:MDB_cursor_basic {
    
	public typealias MDB_cursor_dbtype = Database

}

public struct DatabaseDupIterator<CursorType:MDB_cursor>:IteratorProtocol, Sequence {
	private let cursor:CursorType
	private let initialKey:CursorType.MDB_cursor_dbtype.MDB_db_key_type
	private var first:Bool
	
	internal init(_ cursor:consuming CursorType, opSet:consuming CursorType.MDB_cursor_dbtype.MDB_db_key_type) {
		self.cursor = cursor
		self.initialKey = opSet
		self.first = true
	}
	public mutating func next() -> (key:CursorType.MDB_cursor_dbtype.MDB_db_key_type, value:CursorType.MDB_cursor_dbtype.MDB_db_val_type)? {
		switch first {
			case true:
				self.first = false
				return try? cursor.opSetKey(returning:(key:CursorType.MDB_cursor_dbtype.MDB_db_key_type, value:CursorType.MDB_cursor_dbtype.MDB_db_val_type).self, key:initialKey)
			case false:
				return try? cursor.opNextDup(returning:(key:CursorType.MDB_cursor_dbtype.MDB_db_key_type, value:CursorType.MDB_cursor_dbtype.MDB_db_val_type).self)
		}
	}
}

public struct DatabaseIterator<CursorType:MDB_cursor>:IteratorProtocol, Sequence {
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
	@MDB_cursor_RAW_access_members() // this is needed so that members that typically would be extended can be implemented as borrowing
	public final class DupFixed<D:MDB_db_dupfixed>:MDB_cursor_dupfixed {

		public typealias MDB_cursor_dbtype = D
		
	}

	@MDB_cursor_basics()
	@MDB_cursor_RAW_access_members() // this is needed so that members that typically would be extended can be implemented as borrowing
	public final class Strict<D:MDB_db_strict>:MDB_cursor_strict {

		public typealias MDB_cursor_dbtype = D
	
	}
}
