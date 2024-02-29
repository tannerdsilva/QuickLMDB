import CLMDB
import RAW

#if QUICKLMDB_SHOULDLOG
import Logging
#endif


public final class Cursor:MDB_cursor_basic {
    
	public typealias MDB_cursor_dbtype = Database

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

extension Cursor {
	public final class DupFixed<D:MDB_db_dupfixed>:MDB_cursor_dupfixed {
		public borrowing func compareEntryValues(_ dataL:borrowing MDB_cursor_dbtype.MDB_db_key_type, _ dataR:consuming MDB_cursor_dbtype.MDB_db_val_type) -> Int32 {
			return dataL.MDB_access { (lhsVal:consuming MDB_val) in
				return dataR.MDB_access { (rhsVal:consuming MDB_val) in
					return compareEntryValues(lhsVal, rhsVal)
				}
			}
		}

		public borrowing func compareEntryKeys(_ dataL:borrowing MDB_cursor_dbtype.MDB_db_key_type, _ dataR:consuming MDB_cursor_dbtype.MDB_db_val_type) -> Int32 {
			return dataL.MDB_access { (lhsVal:consuming MDB_val) in
				return dataR.MDB_access { (rhsVal:consuming MDB_val) in
					return compareEntryKeys(lhsVal, rhsVal)
				}
			}
		}

		public borrowing func containsEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws -> Bool {
			return try key.MDB_access { (keyVal:consuming MDB_val) in
				try containsEntry(key:keyVal)
			}
		}

		public borrowing func opSetRange(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
			return try key.MDB_access { (keyVal:consuming MDB_val) in
				return try opSetRange(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:keyVal)
			}
		}

		public borrowing func opSet(returning:MDB_cursor_dbtype.MDB_db_val_type.Type, key: MDB_cursor_dbtype.MDB_db_key_type) throws -> MDB_cursor_dbtype.MDB_db_val_type {
			return try key.MDB_access({ (mdbKey:consuming MDB_val) in
				return MDB_cursor_dbtype.MDB_db_val_type(try opSet(returning:MDB_val.self, key:mdbKey))!
			})
		}

		public borrowing func opGetCurrent(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
			return try opGetCurrent(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! })
		}
		public borrowing func opGetBoth(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
			return try key.MDB_access { (mdbKey:consuming MDB_val) in
				return try value.MDB_access { (mdbVal:consuming MDB_val) in
					return try opGetBoth(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:mdbKey, value:mdbVal)
				}
			}
		}
		public borrowing func opGetBothRange(returning: (key:MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
			return try key.MDB_access { (mdbKey:consuming MDB_val) in
				return try value.MDB_access { (mdbVal:consuming MDB_val) in
					return try opGetBothRange(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:mdbKey, value:mdbVal)
				}
			}
		}
		public borrowing func opSetKey(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
			return try key.MDB_access({ (mdbKey:consuming MDB_val) in
				return try opSetKey(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:mdbKey)
			})
		}

		public borrowing func setEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type, flags:Operation.Flags) throws {
			return try key.MDB_access { (keyVal:consuming MDB_val) in
				try value.MDB_access { (valueVal:consuming MDB_val) in
					try setEntry(key:keyVal, value:valueVal, flags:flags)
				}
			}
		}
		public borrowing func containsEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> Bool {
			return try key.MDB_access { (keyVal:consuming MDB_val) in
				return try value.MDB_access { (valueVal:consuming MDB_val) in
					try containsEntry(key:keyVal, value:valueVal)
				}
			}
		}

		public borrowing func opGetMultiple(returning:[MDB_cursor_dbtype.MDB_db_val_type].Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws -> [MDB_cursor_dbtype.MDB_db_val_type] {
			try key.MDB_access { (keyVal:consuming MDB_val) in
				var valueVal = MDB_val.uninitialized()

				#if DEBUG
				let keyPtr = keyVal.mv_data
				let valuePtr = valueVal.mv_data
				#endif

				try MDB_cursor_get_entry_static(cursor:self, .getMultiple, key:&keyVal, value:&valueVal)

				#if DEBUG
				assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
				assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
				assert(valueVal.mv_size % MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_staticbuff_storetype>.size == 0, "value buffer must be evenly divisible by the expected size of the value type")
				assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
				#endif

				return [MDB_cursor_dbtype.MDB_db_val_type](unsafeUninitializedCapacity:(valueVal.mv_size / MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_staticbuff_storetype>.size), initializingWith: { buff, count in
					var dataSeeker = UnsafeRawPointer(valueVal.mv_data)!
					while valueVal.mv_size > 0 {
						buff[count] = MDB_cursor_dbtype.MDB_db_val_type(RAW_staticbuff_seeking:&dataSeeker)
						valueVal.mv_size -= MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_staticbuff_storetype>.size
						count += 1
					}
				})
			}
		}
		public borrowing func opNextMultiple(returning:[MDB_cursor_dbtype.MDB_db_val_type].Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws -> [MDB_cursor_dbtype.MDB_db_val_type] {
			try key.MDB_access { (keyVal:consuming MDB_val) in
				var valueVal = MDB_val.uninitialized()

				#if DEBUG
				let keyPtr = keyVal.mv_data
				let valuePtr = valueVal.mv_data
				#endif

				try MDB_cursor_get_entry_static(cursor:self, .nextMultiple, key:&keyVal, value:&valueVal)

				#if DEBUG
				assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
				assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
				assert(valueVal.mv_size % MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_staticbuff_storetype>.size == 0, "value buffer must be evenly divisible by the expected size of the value type")
				assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
				#endif

				var dataSeeker = UnsafeRawPointer(valueVal.mv_data)!
				return [MDB_cursor_dbtype.MDB_db_val_type](unsafeUninitializedCapacity:(valueVal.mv_size / MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_staticbuff_storetype>.size), initializingWith: { buff, count in
					while valueVal.mv_size > 0 {
						buff[count] = MDB_cursor_dbtype.MDB_db_val_type(RAW_staticbuff_seeking:&dataSeeker)
						valueVal.mv_size -= MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_staticbuff_storetype>.size
						count += 1
					}
				})
			}
		}

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
	public final class Strict<D:MDB_db_strict>:MDB_cursor_strict {
		public borrowing func compareEntryValues(_ dataL:borrowing MDB_cursor_dbtype.MDB_db_key_type, _ dataR:consuming MDB_cursor_dbtype.MDB_db_val_type) -> Int32 {
			return dataL.MDB_access { (lhsVal:consuming MDB_val) in
				return dataR.MDB_access { (rhsVal:consuming MDB_val) in
					return compareEntryValues(lhsVal, rhsVal)
				}
			}
		}

		public borrowing func compareEntryKeys(_ dataL:borrowing MDB_cursor_dbtype.MDB_db_key_type, _ dataR:consuming MDB_cursor_dbtype.MDB_db_val_type) -> Int32 {
			return dataL.MDB_access { (lhsVal:consuming MDB_val) in
				return dataR.MDB_access { (rhsVal:consuming MDB_val) in
					return compareEntryKeys(lhsVal, rhsVal)
				}
			}
		}

		public borrowing func containsEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws -> Bool {
			return try key.MDB_access { (keyVal:consuming MDB_val) in
				try containsEntry(key:keyVal)
			}
		}
		public borrowing func opSetRange(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
			return try key.MDB_access { (keyVal:consuming MDB_val) in
				return try opSetRange(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:keyVal)
			}
		}

		public borrowing func opSet(returning:MDB_cursor_dbtype.MDB_db_val_type.Type, key: MDB_cursor_dbtype.MDB_db_key_type) throws -> MDB_cursor_dbtype.MDB_db_val_type {
			return try key.MDB_access({ (mdbKey:consuming MDB_val) in
				return MDB_cursor_dbtype.MDB_db_val_type(try opSet(returning:MDB_val.self, key:mdbKey))!
			})
		}

		public borrowing func opGetCurrent(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
			return try opGetCurrent(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! })
		}
		public borrowing func opGetBoth(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
			return try key.MDB_access { (mdbKey:consuming MDB_val) in
				return try value.MDB_access { (mdbVal:consuming MDB_val) in
					return try opGetBoth(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:mdbKey, value:mdbVal)
				}
			}
		}
		public borrowing func opGetBothRange(returning: (key:MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
			return try key.MDB_access { (mdbKey:consuming MDB_val) in
				return try value.MDB_access { (mdbVal:consuming MDB_val) in
					return try opGetBothRange(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:mdbKey, value:mdbVal)
				}
			}
		}

		public borrowing func opSetKey(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
			return try key.MDB_access({ (mdbKey:consuming MDB_val) in
				return try opSetKey(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:mdbKey)
			})
		}

		public borrowing func containsEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> Bool {
			return try key.MDB_access { (keyVal:consuming MDB_val) in
				return try value.MDB_access { (valueVal:consuming MDB_val) in
					try containsEntry(key:keyVal, value:valueVal)
				}
			}
		}

		public borrowing func setEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type, flags:Operation.Flags) throws {
			return try key.MDB_access { (keyVal:consuming MDB_val) in
				try value.MDB_access { (valueVal:consuming MDB_val) in
					try setEntry(key:keyVal, value:valueVal, flags:flags)
				}
			}
		}

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


}
