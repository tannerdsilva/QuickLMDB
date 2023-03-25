import Foundation
import CLMDB

extension Cursor:Sequence {
	/// Procuces an object that is conformant to `IteratorProtocol`. You usually wont need to call this function directly.
	public func makeIterator() -> CursorIterator {
		var statObject = MDB_stat()
		guard mdb_stat(txn_handle, db_handle, &statObject) == MDB_SUCCESS else {
			fatalError("[ERROR] QuickLMDB.Cursor.makeIterator() - unable to retrieve entry count")
		}
		return CursorIterator(count:Int(statObject.ms_entries), cursor_handle:cursor_handle)
	}

	/// The element that the cursor iterator will be returning to represent each entry in the database.
	public typealias Element = (key:MDB_val, value:MDB_val)
	
	/// The iterator type.
	public typealias Iterator = CursorIterator

	/// CursorIterator is the `IteratorProtocol` conformant object that is used execute the complete iteration of database contents.
	public struct CursorIterator:IteratorProtocol, Sequence {
		internal let cursor_handle:OpaquePointer?
		internal var first:Bool = true
		private let isRev:Bool
		
		/// The number of entries in the database
		public let count:Int
		
		fileprivate init(count:Int, cursor_handle:OpaquePointer?, reversed:Bool = false) {
			self.cursor_handle = cursor_handle
			self.count = count
			self.isRev = false
		}
		
		/// Returns the next entry in the database, or `nil` when iteration has been completed.
		public mutating func next() -> (key:MDB_val, value:MDB_val)? {
			let cursorOp:MDB_cursor_op
			if (first == true) {
				switch isRev {
					case true:
						cursorOp = MDB_LAST
					case false:
						cursorOp = MDB_FIRST
				}
			} else {
				switch isRev {
					case true:
						cursorOp = MDB_PREV
					case false:
						cursorOp = MDB_NEXT
				}
			}
			
			var captureKey = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			var captureVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			let cursorResult = mdb_cursor_get(cursor_handle, &captureKey, &captureVal, cursorOp)
			guard cursorResult == MDB_SUCCESS else {
				return nil
			}
			
			return (key:captureKey, value:captureVal)
		}

		public func reversed() -> CursorIterator {
			return CursorIterator(count:count, cursor_handle:cursor_handle, reversed:true)
		}
	}
	
	/// Procuces an object that is conformant to `IteratorProtocol`. This object will only iterate over the duplicate items of the current key
	public func makeDupIterator<K:MDB_encodable>(key:K) throws -> CursorDupIterator {
		let getKey = try self.getEntry(.setKey, key:key).key
		let dupCount = try self.dupCount()
		return CursorDupIterator(key:getKey, count:dupCount, cursor_handle:cursor_handle)
	}

	
	/// CursorDupIterator is the `IteratorProtocol` conformant object that is used execute the complete iteration of duplicate key entries of a given database.
	public struct CursorDupIterator:IteratorProtocol, Sequence {
		internal let cursor_handle:OpaquePointer?
		internal var first:Bool = true
		private let isRev:Bool
		
		/// The key that this DupIterator is iterating through
		internal let key:MDB_val
		
		/// The number of entries for the current key
		public let count:Int
		
		fileprivate init(key:MDB_val, count:Int, cursor_handle:OpaquePointer?, reversed:Bool = false) {
			self.cursor_handle = cursor_handle
			self.count = count
			self.key = key
			self.isRev = false
		}
		
		/// Returns the next entry in the database, or `nil` when iteration has been completed.
		public mutating func next() -> (key:MDB_val, value:MDB_val)? {
			let cursorOp:MDB_cursor_op
			if (first == true) {
				switch isRev {
					case true:
						cursorOp = MDB_LAST_DUP
					case false:
						cursorOp = MDB_FIRST_DUP
				}
				first = false
			} else {
				switch isRev {
					case true:
						cursorOp = MDB_PREV_DUP
					case false:
						cursorOp = MDB_NEXT_DUP
				}
			}
			
			var captureKey = key
			var captureVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			let cursorResult = mdb_cursor_get(cursor_handle, &captureKey, &captureVal, cursorOp)
			guard cursorResult == MDB_SUCCESS else {
				return nil
			}
			
			return (key:captureKey, value:captureVal)
		}
	}
}
