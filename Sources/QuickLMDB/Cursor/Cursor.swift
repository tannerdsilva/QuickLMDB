import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif

// /// the protocol for type-strict cursors
// public protocol MDB_cursor_strict:MDB_cursor where MDB_cursor_dbtype:MDB_db_strict {
// 	// /// get entry with strict key and value types
// 	// func MDB_cursor_get_entry(_ operation:Operation, key:UnsafePointer<MDB_val>, value:UnsafePointer<MDB_val>) throws -> (MDB_val, MDB_val)
// 	// /// get entry with strict key type
// 	// func MDB_cursor_get_entry(_ operation:Operation, key:UnsafePointer<MDB_cursor_dbtype.MDB_db_key_type>) throws -> (MDB_val, MDB_val)
// 	// /// get entry with strict value type
// 	// func MDB_cursor_get_entry(_ operation:Operation, value:UnsafePointer<MDB_cursor_dbtype.MDB_db_val_type>) throws -> (MDB_val, MDB_val)

// 	// /// set entry with strict key and value types
// 	// func MDB_cursor_set_entry(key:UnsafePointer<MDB_cursor_dbtype.MDB_db_key_type>, value:UnsafePointer<MDB_cursor_dbtype.MDB_db_val_type>, flags:Operation.Flags) throws

// 	// /// check for entries with strict key type
// 	// func MDB_cursor_contains_entry(key:UnsafePointer<MDB_cursor_dbtype.MDB_db_key_type>) throws -> Bool
// 	// /// check for entries with strict key and value types
// 	// func MDB_cursor_contains_entry(key:UnsafePointer<MDB_cursor_dbtype.MDB_db_key_type>, value:UnsafePointer<MDB_cursor_dbtype.MDB_db_val_type>) throws -> Bool
	
// 	func MDB_cursor_compare_keys<L:RAW_accessible, R:RAW_accessible>(_ dataL:UnsafePointer<L>, _ dataR:UnsafePointer<R>) -> Int32
// 	func MDB_cursor_compare_values<L:RAW_accessible, R:RAW_accessible>(_ dataL:UnsafePointer<L>, _ dataR:UnsafePointer<R>) -> Int32
// }

/// the protocol for open ended data storage type
public protocol MDB_cursor<MDB_cursor_dbtype>:Sequence {
	/// the native pair type that the cursor operates with. reflects the underlying key/value types of the backing database type
	typealias MDB_cursor_pairtype = (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type)

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
	borrowing func opFirst(returning:MDB_cursor_pairtype.Type) throws -> MDB_cursor_pairtype
	borrowing func opFirstDup(returning:MDB_cursor_pairtype.Type) throws -> MDB_cursor_pairtype
	// last variants - skip the line and go straight to the end
	borrowing func opLast(returning:MDB_cursor_pairtype.Type) throws -> MDB_cursor_pairtype
	borrowing func opLastDup(returning:MDB_cursor_pairtype.Type) throws -> MDB_cursor_pairtype
	// next variants - move forward
	borrowing func opNext(returning:MDB_cursor_pairtype.Type) throws -> MDB_cursor_pairtype
	borrowing func opNextDup(returning:MDB_cursor_pairtype.Type) throws -> MDB_cursor_pairtype
	borrowing func opNextNoDup(returning:MDB_cursor_pairtype.Type) throws -> MDB_cursor_pairtype
	// previous variants - take it back
	borrowing func opPrevious(returning:MDB_cursor_pairtype.Type) throws -> MDB_cursor_pairtype
	borrowing func opPreviousDup(returning:MDB_cursor_pairtype.Type) throws -> MDB_cursor_pairtype
	borrowing func opPreviousNoDup(returning:MDB_cursor_pairtype.Type) throws -> MDB_cursor_pairtype
	// get variants - find your footing
	borrowing func opGetBoth(returning:MDB_cursor_pairtype.Type, key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) throws -> MDB_cursor_pairtype
	borrowing func opGetBothRange(returning:MDB_cursor_pairtype.Type, key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) throws -> MDB_cursor_pairtype
	borrowing func opGetCurrent(returning:MDB_cursor_pairtype.Type) throws -> MDB_cursor_pairtype
	// set variants - make your mark
	borrowing func opSet(returning:MDB_cursor_dbtype.MDB_db_val_type.Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> MDB_cursor_dbtype.MDB_db_val_type
	borrowing func opSetKey(returning:MDB_cursor_pairtype.Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> MDB_cursor_pairtype
	borrowing func opSetRange(returning:MDB_cursor_pairtype.Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> MDB_cursor_pairtype
	// multiple variants - theres more than meets the eye
	borrowing func opGetMultiple(returning:MDB_cursor_pairtype.Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> MDB_cursor_pairtype
	borrowing func opNextMultiple(returning:MDB_cursor_pairtype.Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> MDB_cursor_pairtype
	
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


// extension MDB_cursor {
// 	/// set the current entry with a specified key and value.
// 	public mutating func setEntry<K:MDB_encodable, V:MDB_encodable>(key keyVal:UnsafePointer<K>, value valuePtr:UnsafePointer<V>, flags:Operation.Flags) throws {
// 		switch flags.contains(.reserve) {
// 			case true:
// 				try keyVal.pointee.MDB_encodable_access { keyVal in
// 					var valueVal = valuePtr.pointee.MDB_encodable_reserved_val()
					
// 					#if DEBUG
// 					let trashPointer = valueVal.mv_data
// 					#endif

// 					#if QUICKLMDB_SHOULDLOG
// 					try MDB_cursor_set_entry_static(&self, key:keyVal, value:&valueVal, flags:flags, logger:logger)
// 					#else
// 					try MDB_cursor_set_entry_static(&self, key:keyVal, value:&valueVal, flags:flags)
// 					#endif

// 					#if DEBUG
// 					assert(trashPointer != valueVal.mv_data, "database failed to return a unique buffer pointer for reserved value")
// 					#endif

// 					valuePtr.pointee.MDB_encodable_write(reserved:&valueVal)
// 				}
// 			case false:
// 				try keyVal.pointee.MDB_encodable_access { keyVal in
// 					try valuePtr.pointee.MDB_encodable_access { valueVal in
// 						#if QUICKLMDB_SHOULDLOG
// 						try MDB_cursor_set_entry_static(&self, key:keyVal, value:valueVal, flags:flags, logger:logger)
// 						#else
// 						try MDB_cursor_set_entry_static(&self, key:keyVal, value:valueVal, flags:flags)
// 						#endif
// 					}
// 				}
// 		}
// 	}

// 	public mutating func containsEntry<K:MDB_encodable, V:MDB_encodable>(key:UnsafePointer<K>, value:UnsafePointer<V>) throws -> Bool {
// 		return try key.pointee.MDB_encodable_access { keyVal in
// 			return try value.pointee.MDB_encodable_access { valueVal in
// 				let searchKey = mdb_cursor_get(MDB_cursor_handle, keyVal, valueVal, MDB_GET_BOTH)
// 				switch searchKey {
// 					case MDB_SUCCESS:
// 						return true;
// 					case MDB_NOTFOUND:
// 						return false;
// 					default:
// 						throw LMDBError(returnCode:searchKey)
// 				}
// 			}
// 		}
// 	}

// 	public func containsEntry<K:MDB_encodable>(key:UnsafePointer<K>) throws -> Bool {
// 		return try key.pointee.MDB_encodable_access { keyVal in
// 			let searchKey = mdb_cursor_get(MDB_cursor_handle, keyVal, nil, MDB_SET)
// 			switch searchKey {
// 				case MDB_SUCCESS:
// 					return true;
// 				case MDB_NOTFOUND:
// 					return false;
// 				default:
// 					throw LMDBError(returnCode:searchKey)
// 			}
// 		}
// 	}

// 	public func deleteCurrentEntry(flags:Operation.Flags) throws {
// 		let deleteResult = mdb_cursor_del(MDB_cursor_handle, flags.rawValue)
// 		guard deleteResult == MDB_SUCCESS else {
// 			throw LMDBError(returnCode:deleteResult)
// 		}
// 	}

// 	public mutating func compareEntryKeys(_ dataL:UnsafePointer<MDB_val>, _ dataR:UnsafePointer<MDB_val>) -> Int32 {
// 		return dataL.pointee.RAW_access { lBuff in
// 			return dataR.pointee.RAW_access { rBuff in
// 				var lVal = MDB_val(lBuff)
// 				var rVal = MDB_val(rBuff)
// 				return mdb_cmp(MDB_txn_handle, MDB_db_handle, &lVal, &rVal)
// 			}
// 		}
// 	}

// 	public func MDB_cursor_compare_values<L:RAW_accessible, R:RAW_accessible>(_ dataL:UnsafePointer<L>, _ dataR:UnsafePointer<R>) -> Int32 {
// 		return dataL.pointee.RAW_access { lBuff in
// 			return dataR.pointee.RAW_access { rBuff in
// 				var lVal = MDB_val(lBuff)
// 				var rVal = MDB_val(rBuff)
// 				return mdb_dcmp(MDB_txn_handle, MDB_db_handle, &lVal, &rVal)
// 			}
// 		}
// 	}

// 	public func MDB_cursor_dup_count() throws -> size_t {
// 		var dupCount = size_t()
// 		let countResult = mdb_cursor_count(self.MDB_cursor_handle, &dupCount)
// 		switch countResult { 
// 			case MDB_SUCCESS:
// 				return dupCount
// 			default:
// 				throw LMDBError(returnCode:countResult)
// 		}
// 	}
// }

// extension Cursor:MDB_cursor_strict where MDB_cursor_dbtype:MDB_db_strict {}

// extension Cursor:MDB_cursor where MDB_cursor_dbtype:MDB_db {}

/// LMDB cursor. this is defined as a class so that the cursor can be auto-closed when references to this instances are free'd from memory.
/// - conforms to the ``MDB_cursor`` protocol with any database (unconditional)
/// - conforms to the ``MDB_cursor_strict`` protocol with any database that conforms to the ``MDB_db_strict`` protocol.
//ic final class Cursor<D:MDB_db>:Sequence {
//	/// returns a dup iterator for a specified key. if the key does not exist, an error is thrown.
//	public func makeDupIterator<A:RAW_accessible>(key:inout A) throws -> DupIterator {
//		try MDB_cursor_get_entry(.setKey, key:&key)
//		return DupIterator(self)
//	}
//	
//	/// traditional 'makeiterator' that allows a cursor to conform to Sequence
//	public func makeIterator() -> Iterator {
//		return Iterator(self)
//	}
//	
//	/// primary dup iterator implementation
//	public struct DupIterator:IteratorProtocol, Sequence {
//		private var cursor:Cursor<D>
//		private var op:Operation
//
//		fileprivate init(_ cursor:Cursor<D>) {
//			self.cursor = cursor
//			self.op = .firstDup
//		}
//
//		public mutating func next() -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)? {
//			defer {
//				switch op {
//					case .firstDup:
//						op = .nextDup
//					default:
//						break;
//				}
//			}
//			do {
//				return try cursor.MDB_cursor_get_entry(op)
//			} catch {
//				return nil
//			}
//		}
//	}
//
//	public struct Iterator:IteratorProtocol, Sequence {
//		private var cursor:Cursor<D>
//		private var op:Operation
//
//		public init(_ cursor:Cursor<D>) {
//			self.cursor = cursor
//			self.op = .first
//		}
//
//		public mutating func next() -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)? {
//			defer {
//				switch op {
//					case .first:
//						op = .next
//					default:
//						break;
//				}
//			}
//			do {
//				return try cursor.MDB_cursor_get_entry(op)
//			} catch {
//				return nil
//			}
//		}
//	}
//
//	public typealias MDB_cursor_dbtype = D
//
//	/// this is the pointer to the `MDB_cursor` struct associated with a given instance.
//	private let _cursor_handle:OpaquePointer
//	public borrowing func cursorHandle() -> OpaquePointer {
//		return _cursor_handle
//	}
//	
//	/// this is the database that this cursor is associated with.
//	private let _db_handle:MDB_dbi
//	public borrowing func dbHandle() -> MDB_dbi {
//		return _db_handle
//	}
//	
//	/// pointer to the `MDB_txn` struct associated with a given instance.
//	private let _tx_handle:OpaquePointer
//	public borrowing func txHandle() -> OpaquePointer {
//		return _tx_handle
//	}
//	
//	/// opens a new cursor instance from a given database and transaction pairing.
//	public init<D:MDB_db>(db:borrowing D, tx:borrowing Transaction) throws {
//		var buildCursor:OpaquePointer? = nil
//		let openCursorResult = mdb_cursor_open(tx.txHandle(), db.dbHandle(), &buildCursor)
//		guard openCursorResult == MDB_SUCCESS else {
//			throw LMDBError(returnCode:openCursorResult)
//		}
//		self._cursor_handle = buildCursor!
//		self._db_handle = db.dbHandle()
//		self._tx_handle = db.txHandle()
//		MDB_txn_readonly = MDB_tx.MDB_tx_readOnly
//	}
//
//	deinit {
//		// close the cursor
//		mdb_cursor_close(MDB_cursor_handle)
//	}
//}