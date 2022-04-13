import Foundation
import CLMDB

extension Cursor:Sequence {
	///Procuces an object that is conformant to `IteratorProtocol`. You usually wont need to call this function directly.
	public func makeIterator() -> CursorIterator {
		var statObject = MDB_stat()
		guard mdb_stat(txn_handle, db_handle, &statObject) == MDB_SUCCESS else {
			fatalError("[ERROR] QuickLMDB.Cursor.makeIterator() - unable to retrieve entry count")
		}
		return CursorIterator(count:Int(statObject.ms_entries), cursor_handle:cursor_handle)
	}

	public typealias Element = (key:MDB_val, value:MDB_val)
	public typealias Iterator = CursorIterator

	public struct CursorIterator:IteratorProtocol {
		internal let cursor_handle:OpaquePointer?
		var first:Bool = true
		public var count:Int
		
		fileprivate init(count:Int, cursor_handle:OpaquePointer?) {
			self.cursor_handle = cursor_handle
			self.count = count
		}
		
		public mutating func next() -> (key:MDB_val, value:MDB_val)? {
			let cursorOp:MDB_cursor_op
			if (first == true) {
				cursorOp = MDB_FIRST
				first = false
			} else {
				cursorOp = MDB_NEXT
			}
			
			var captureKey = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			var captureVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			let cursorResult = mdb_cursor_get(cursor_handle, &captureKey, &captureVal, cursorOp)
			guard cursorResult == 0 else {
				return nil
			}
			
			return (key:captureKey, value:captureVal)
		}
	}
}
