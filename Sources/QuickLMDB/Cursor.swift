import CLMDB
import RAW

public typealias MDB_val = CLMDB.MDB_val

public protocol MDB_cursor {
	/// the cursor handle for the specific instance.
	var MDB_cursor_handle:OpaquePointer { get }
	/// the database handle for the specific instance.
	var MDB_db_handle:MDB_dbi { get }
	/// the transaction that this instance is operating within.
	var MDB_txn_handle:OpaquePointer? { get }

	init(MDB_db_handle:MDB_dbi, tx:Transaction) throws

	// get entries
	/// get entries with a key and a value.
	@discardableResult func getEntry<K:RAW_accessible, V:RAW_accessible>(_ operation:Cursor.Operation, key:inout K, value:inout V) throws -> (key:UnsafeMutableRawBufferPointer, value:UnsafeMutableRawBufferPointer)
	/// get entries with a key.
	@discardableResult func getEntry<K:RAW_accessible>(_ operation:Cursor.Operation, key:inout K) throws -> (key:UnsafeMutableRawBufferPointer, value:UnsafeMutableRawBufferPointer)
	/// get entries with a value.
	@discardableResult func getEntry<V:RAW_accessible>(_ operation:Cursor.Operation, value:inout V) throws -> (key:UnsafeMutableRawBufferPointer, value:UnsafeMutableRawBufferPointer)
	/// get entries based on an operation only.
	@discardableResult func getEntry(_ operation:Cursor.Operation) throws -> (key:UnsafeMutableRawBufferPointer, value:UnsafeMutableRawBufferPointer)

	// set entries.
	func setEntry<K:RAW_accessible, V:RAW_encodable>(key:inout K, value:inout V, flags:Cursor.Operation.Flags) throws
	
	// checking for existing entries.
	func containsEntry<K:RAW_accessible>(key:inout K) throws -> Bool
	// checking for existing entries.
	func containsEntry<K:RAW_accessible, V:RAW_accessible>(key:inout K, value:inout V) throws -> Bool

	// delete entries.
	func deleteCurrentEntry(flags:Cursor.Operation.Flags) throws

	// compare entries based on the native compare function of the database.
	func compareKeys<L:RAW_accessible, R:RAW_accessible>(_ dataL:inout L, _ dataR:inout R) -> Int32

	// compare entries based on the native compare function of the database.
	func compareValues<L:RAW_accessible, R:RAW_accessible>(_ dataL:inout L, _ dataR:inout R) -> Int32
}

extension MDB_cursor {
	/// execute an entry retrieval operation with a specified operation, key and value.
	@discardableResult public func getEntry<K:RAW_accessible, V:RAW_accessible>(_ operation:Cursor.Operation, key:inout K, value:inout V) throws -> (key:UnsafeMutableRawBufferPointer, value:UnsafeMutableRawBufferPointer) {
		return try key.RAW_access_mutating { keyBuff in
			return try value.RAW_access_mutating { valueBuff in
				var keyVal = MDB_val(keyBuff)
				var valueVal = MDB_val(valueBuff)
				let cursorResult = mdb_cursor_get(MDB_cursor_handle, &keyVal, &valueVal, operation.mdbValue)
				guard cursorResult == MDB_SUCCESS else {
					throw LMDBError(returnCode:cursorResult)
				}
				return (key:UnsafeMutableRawBufferPointer(keyVal), value:UnsafeMutableRawBufferPointer(valueVal))
			}
		}
	}

	/// execute an entry retrieval operation with a specified operation and key.
	@discardableResult public func getEntry<K:RAW_accessible>(_ operation:Cursor.Operation, key:inout K) throws -> (key:UnsafeMutableRawBufferPointer, value:UnsafeMutableRawBufferPointer) {
		return try key.RAW_access_mutating { keyBuff in
			var keyVal = MDB_val(keyBuff)
			var valueVal = MDB_val.nullValue()
			let cursorResult = mdb_cursor_get(MDB_cursor_handle, &keyVal, &valueVal, operation.mdbValue)
			guard cursorResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:cursorResult)
			}
			return (key:UnsafeMutableRawBufferPointer(keyVal), value:UnsafeMutableRawBufferPointer(valueVal))
		}
	}

	/// execute an entry retrieval operation with a specified operation and value.
	@discardableResult public func getEntry<V:RAW_accessible>(_ operation:Cursor.Operation, value:inout V) throws -> (key:UnsafeMutableRawBufferPointer, value:UnsafeMutableRawBufferPointer) {
		return try value.RAW_access_mutating { valueBuff in
			var keyVal = MDB_val.nullValue()
			var valueVal = MDB_val(valueBuff)
			let cursorResult = mdb_cursor_get(MDB_cursor_handle, &keyVal, &valueVal, operation.mdbValue)
			guard cursorResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:cursorResult)
			}
			return (key:UnsafeMutableRawBufferPointer(keyVal), value:UnsafeMutableRawBufferPointer(valueVal))
		}
	}

	/// execute an entry retrieval operation with a specified operation only.
	@discardableResult public func getEntry(_ operation:Cursor.Operation) throws -> (key:UnsafeMutableRawBufferPointer, value:UnsafeMutableRawBufferPointer) {
		var keyVal = MDB_val.nullValue()
		var valueVal = MDB_val.nullValue()
		let cursorResult = mdb_cursor_get(MDB_cursor_handle, &keyVal, &valueVal, operation.mdbValue)
		guard cursorResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:cursorResult)
		}
		return (key:UnsafeMutableRawBufferPointer(keyVal), value:UnsafeMutableRawBufferPointer(valueVal))
	}

	/// set the current entry with a specified key and value.
	public func setEntry<K:RAW_accessible, V:RAW_encodable>(key:inout K, value:inout V, flags:Cursor.Operation.Flags) throws {
		try key.RAW_access_mutating { keyBuff in
			var keyVal = MDB_val(keyBuff)
			var valueVal = MDB_val.nullValue()
			value.RAW_encode(count:&valueVal.mv_size)
			let putResult = mdb_cursor_put(MDB_cursor_handle, &keyVal, &valueVal, flags.union(.reserve).rawValue)
			guard putResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:putResult)
			}
			#if DEBUG
			assert(valueVal.mv_data != nil)
			#endif
			value.RAW_encode(dest:valueVal.mv_data.assumingMemoryBound(to:UInt8.self))
		}
	}

	public func containsEntry<K:RAW_accessible>(key:inout K) throws -> Bool {
		return try key.RAW_access_mutating { keyBuff in
			var keyVal = MDB_val(keyBuff)
			let searchKey = mdb_cursor_get(MDB_cursor_handle, &keyVal, nil, MDB_SET)
			switch searchKey {
				case MDB_SUCCESS:
					return true;
				case MDB_NOTFOUND:
					return false;
				default:
					throw LMDBError(returnCode:searchKey)
			}
		}
	}

	public func containsEntry<K:RAW_accessible, V:RAW_accessible>(key:inout K, value:inout V) throws -> Bool {
		return try key.RAW_access_mutating { keyBuff in
			return try value.RAW_access_mutating { valueBuff in
				var keyVal = MDB_val(keyBuff)
				var valueVal = MDB_val(valueBuff)
				let searchKey = mdb_cursor_get(MDB_cursor_handle, &keyVal, &valueVal, MDB_SET)
				switch searchKey {
					case MDB_SUCCESS:
						return true;
					case MDB_NOTFOUND:
						return false;
					default:
						throw LMDBError(returnCode:searchKey)
				}
			}
		}
	}

	public func deleteCurrentEntry(flags:Cursor.Operation.Flags) throws {
		let deleteResult = mdb_cursor_del(MDB_cursor_handle, flags.rawValue)
		guard deleteResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:deleteResult)
		}
	}

	public func compareKeys<L:RAW_accessible, R:RAW_accessible>(_ dataL:inout L, _ dataR:inout R) -> Int32 {
		return dataL.RAW_access_mutating { lBuff in
			return dataR.RAW_access_mutating { rBuff in
				var lVal = MDB_val(lBuff)
				var rVal = MDB_val(rBuff)
				return mdb_cmp(MDB_txn_handle, MDB_db_handle, &lVal, &rVal)
			}
		}
	}

	public func compareValues<L:RAW_accessible, R:RAW_accessible>(_ dataL:inout L, _ dataR:inout R) -> Int32 {
		return dataL.RAW_access_mutating { lBuff in
			return dataR.RAW_access_mutating { rBuff in
				var lVal = MDB_val(lBuff)
				var rVal = MDB_val(rBuff)
				return mdb_dcmp(MDB_txn_handle, MDB_db_handle, &lVal, &rVal)
			}
		}
	}

	public func dupCount() throws -> size_t {
		var dupCount = size_t()
		let countResult = mdb_cursor_count(self.MDB_cursor_handle, &dupCount)
		switch countResult { 
			case MDB_SUCCESS:
				return dupCount
			default:
				throw LMDBError(returnCode:countResult)
		}
	}
}

/// LMDB Cursor. This is defined as a class so that the cursor can be auto-closed when references to this instances are free'd from memory.
public class Cursor {
	
	/// This is the complete toolset of operations that can be utilized to retrieve and navigate entries in the database.
	public enum Operation {
		
		/// Operation flags modify the way that entries are stored in the database. In LMDB documentation, these are known as "write flags".
		public struct Flags:OptionSet {
			
			/// The raw integer value for this flag. Can be passed directly into 
			public let rawValue:UInt32
			
			/// Create a flag with its integer value.
			public init(rawValue:UInt32) {
				self.rawValue = rawValue
			}

			/// Do not write the entry if the key already exists in the database. In this case, ``LMDBError/keyExists`` is thrown.
			public static let noOverwrite = Flags(rawValue:UInt32(MDB_NOOVERWRITE))
			
			/// Only for use with ``Database/Flags/dupSort``
			/// - For ``Cursor/setEntry(value:forKey:flags:)``: don't write if the key and data pair already exist.
			/// - For ``Cursor/deleteEntry(flags:)``: Remove all duplicate data items from the database.
			public static let noDupData = Flags(rawValue:UInt32(MDB_NODUPDATA))
			
			/// For ``Cursor/setEntry(value:forKey:flags:)``: overwrite the current key/value pair.
			public static let current = Flags(rawValue:UInt32(MDB_CURRENT))
			
			/// For ``Cursor/setEntry(value:forKey:flags:)``: just reserve space for the value, don't copy it. Return a pointer to the reserved space.
			public static let reserve = Flags(rawValue:UInt32(MDB_RESERVE))
			
			/// Pre-sorted keys are being stored in the database. Don't split full pages.
			public static let append = Flags(rawValue:UInt32(MDB_APPEND))
			
			/// Pre-sorted key/value entires are being stored in the database. Don't split full pages.
			public static let appendDup = Flags(rawValue:UInt32(MDB_APPENDDUP))
			
			/// Store multiple data items in one call. Only for ``Database/Flags/dupFixed``.
			public static let multiple = Flags(rawValue:UInt32(MDB_MULTIPLE))
		}
		
		/// Position at first key/data item.
		case first
		
		/// Position at first data item of current key. Only use with ``Database/Flags/dupSort`` enabled.
		case firstDup
		
		/// Position at key/data pair. Only use with ``Database/Flags/dupSort`` enabled.
		case getBoth
		
		/// Position at key, nearest data. Only use with ``Database/Flags/dupSort`` enabled.
		case getBothRange
		
		/// Return the key/value entry at the cursor's current position.
		case getCurrent
		
		/// Return key and up to a page of duplicate data items from the current cursor position. Move cursor to prepare for ``Cursor/Operation/nextMultiple``.
		case getMultiple
		
		/// Position at the last key/value item.
		case last
		
		/// Position at the last data item of the current key.
		case lastDup
		
		/// Position at the next data item.
		case next
		
		/// Position at the next data item of the current key.
		case nextDup
		
		/// Return key and up to a page of duplicate data items from next cursor position. Move cursor to prepare for the next ``Cursor/Operation/nextMultiple``.
		case nextMultiple
		
		/// Position at first data item of the next key.
		case nextNoDup
		
		/// Position at previous data item.
		case previous
		
		/// Position at previous data item of current key. Only for ``Database/Flags/dupSort``.
		case previousDup
		
		/// Position at lsat data item of previous key.
		case previousNoDup
		
		/// Position at the specified key.
		/// - Returned key will point to the same buffer that was passed into the cursor.
		case set
		
		/// Position at the specified key.
		/// - Returned key will point to the buffer that is stored in the memory map.
		case setKey
		
		/// Position at the first key greater than or equal to specified key.
		case setRange
		
		/// Initialize an operation with a specified `MDB_cursor_op`.
		public init(mdbValue:MDB_cursor_op) {
			switch mdbValue {
				case MDB_FIRST:
					self = .first
				case MDB_FIRST_DUP:
					self = .firstDup
				case MDB_GET_BOTH:
					self = .getBoth
				case MDB_GET_BOTH_RANGE:
					self = .getBothRange
				case MDB_GET_CURRENT:
					self = .getCurrent
				case MDB_GET_MULTIPLE:
					self = .getMultiple
				case MDB_LAST:
					self = .last
				case MDB_LAST_DUP:
					self = .lastDup
				case MDB_NEXT:
					self = .next
				case MDB_NEXT_DUP:
					self = .nextDup
				case MDB_NEXT_MULTIPLE:
					self = .nextMultiple
				case MDB_NEXT_NODUP:
					self = .nextNoDup
				case MDB_PREV:
					self = .previous
				case MDB_PREV_DUP:
					self = .previousDup
				case MDB_PREV_NODUP:
					self = .previousNoDup
				case MDB_SET:
					self = .set
				case MDB_SET_KEY:
					self = .setKey
				case MDB_SET_RANGE:
					self = .setRange
				default:
					self = .next
			}
		}
		
		///Retrieve the `MDB_cursor_op` value for this Operation.
		public var mdbValue:MDB_cursor_op {
			get {
				switch self {
					case .first:
						return MDB_FIRST
					case .firstDup:
						return MDB_FIRST_DUP
					case .getBoth:
						return MDB_GET_BOTH
					case .getBothRange:
						return MDB_GET_BOTH_RANGE
					case .getCurrent:
						return MDB_GET_CURRENT
					case .getMultiple:
						return MDB_GET_MULTIPLE
					case .last:
						return MDB_LAST
					case .lastDup:
						return MDB_LAST_DUP
					case .next:
						return MDB_NEXT
					case .nextDup:
						return MDB_NEXT_DUP
					case .nextMultiple:
						return MDB_NEXT_MULTIPLE
					case .nextNoDup:
						return MDB_NEXT_NODUP
					case .previous:
						return MDB_PREV
					case .previousDup:
						return MDB_PREV_DUP
					case .previousNoDup:
						return MDB_PREV_NODUP
					case .set:
						return MDB_SET
					case .setKey:
						return MDB_SET_KEY
					case .setRange:
						return MDB_SET_RANGE
				}
			}
		}
	}
	
	/// This is the pointer to the `MDB_cursor` struct associated with a given instance.
	public let cursor_handle:OpaquePointer?
	
	/// This is the database that this cursor is associated with.
	public let db_handle:MDB_dbi
	
	/// Pointer to the `MDB_txn` struct associated with a given instance.
	public let txn_handle:OpaquePointer?

	internal init(txn_handle:OpaquePointer?, db:MDB_dbi) throws {
		var buildCursor:OpaquePointer? = nil
		let openCursorResult = mdb_cursor_open(txn_handle, db, &buildCursor)
		guard openCursorResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openCursorResult)
		}
		self.cursor_handle = buildCursor
		self.db_handle = db
		self.txn_handle = txn_handle
	}
	
	/// Retrieve an entry with a provided key and value.
	/// - Parameters:
	///   - operation: The operation to use when retrieving this entry.
	///   - inputKey: The key to retrieve from the database.
	///   - inputValue: The value to retrieve from the database.
	/// - Throws: This function will throw an ``LMDBError`` if the cursor operation does not return `MDB_SUCCESS`.
	/// - Returns: The key/value pairing that was retrieved from the database as `MDB_val`'s.
	@discardableResult public func getEntry<K:MDB_encodable, V:MDB_encodable>(_ operation:Operation, key inputKey:K, value inputValue:V) throws -> (key:MDB_val, value:MDB_val) {
		return try inputKey.asMDB_val({ keyVal in
			return try inputValue.asMDB_val({ valueVal in
				let cursorResult = mdb_cursor_get(cursor_handle, &keyVal, &valueVal, operation.mdbValue)
				guard cursorResult == MDB_SUCCESS else {
					throw LMDBError(returnCode:cursorResult)
				}
				return (key:keyVal, value:valueVal)
			})
		})
	}
	
	/// Retrieve an entry with a provided key.
	/// - Parameters:
	///   - operation: The operation to use when retrieving this entry.
	///   - inputKey: The key to retrieve from the database.
	/// - Throws: This function will throw an ``LMDBError`` if the cursor operation does not return `MDB_SUCCESS`.
	/// - Returns: The key/value pairing that was retrieved from the database as `MDB_val`'s.
	@discardableResult public func getEntry<K:MDB_encodable>(_ operation:Operation, key inputKey:K) throws -> (key:MDB_val, value:MDB_val) {
		return try inputKey.asMDB_val({ keyVal in
			var valueVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			let cursorResult = mdb_cursor_get(cursor_handle, &keyVal, &valueVal, operation.mdbValue)
			guard cursorResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:cursorResult)
			}
			return (key:keyVal, value:valueVal)
		})
	}

	/// Retrieve an entry with a provided value.
	/// - Parameters:
	///   - operation: The operation to use when retrieving this entry.
	///   - inputValue: The value to retrieve from the database.
	/// - Throws: This function will throw an ``LMDBError`` if the cursor operation does not return `MDB_SUCCESS`.
	/// - Returns: The key/value pairing that was retrieved from the database as `MDB_val`'s.
	@discardableResult public func getEntry<V:MDB_encodable>(_ operation:Operation, value inputValue:V) throws -> (key:MDB_val, value:MDB_val) {
		return try inputValue.asMDB_val({ valueVal in
			var keyVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			let cursorResult = mdb_cursor_get(cursor_handle, &keyVal, &valueVal, operation.mdbValue)
			guard cursorResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:cursorResult)
			}
			return (key:keyVal, value:valueVal)
		})
	}

	/// Retrieve an entry from the database.
	/// - Parameter operation: The operation to use when retrieving this entry.
	/// - Throws: This function will throw an ``LMDBError`` if the cursor operation does not return `MDB_SUCCESS`.
	/// - Returns: The key/value pairing that was retrieved from the database as `MDB_val`'s.
	@discardableResult public func getEntry(_ operation:Operation) throws -> (key:MDB_val, value:MDB_val) {
		var keyVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
		var valueVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
		let cursorResult = mdb_cursor_get(cursor_handle, &keyVal, &valueVal, operation.mdbValue)
		guard cursorResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:cursorResult)
		}
		return (key:keyVal, value:valueVal)
	}
	
	/// Store a key and value in the database.
	/// - Parameters:
	///   - value: The value (or data) to be stored in the database.
	///   - key: The key to associate with the specified value.
	///   - flags: Options for this operation.
	/// - Throws: This function will throw an ``LMDBError`` if the cursor operation does not return `MDB_SUCCESS`.
	public func setEntry<K:MDB_encodable, V:MDB_encodable>(value:V, forKey key:K, flags:Operation.Flags = []) throws {
		try key.asMDB_val({ keyVal in
			try value.asMDB_val({ valueVal in
				let putResult = mdb_cursor_put(cursor_handle, &keyVal, &valueVal, flags.rawValue)
				guard putResult == MDB_SUCCESS else {
					throw LMDBError(returnCode:putResult)
				}
			})
		})
	}

	
	/// Check the database for the existence of a key.
	/// - Parameter key: The key to search for in the database.
	/// - Returns: Returns `true` if `MDB_SUCCESS` is returned during the search. Returns `false` if `MDB_NOTFOUND` was returned during the search.
	/// - Throws: This function will throw an ``LMDBError`` if any value other than `MDB_SUCCESS` or `MDB_NOTFOUND` are returned.
	public func containsEntry<K:MDB_encodable>(key:K) throws -> Bool {
		try key.asMDB_val({ keyVal in
			let searchKey = mdb_cursor_get(cursor_handle, &keyVal, nil, MDB_SET)
			switch searchKey {
				case MDB_SUCCESS:
					return true;
				case MDB_NOTFOUND:
					return false;
				default:
					throw LMDBError(returnCode:searchKey)
			}
		})
	}
	
	/// Check the database for the existence of a key/value entry.
	/// - Parameters:
	///   - key: The key to search for in the database.
	///   - value: The value to search for in the database.
	/// - Returns: Returns `true` if `MDB_SUCCESS` is returned during the search. Returns `false` if `MDB_NOTFOUND` was returned during the search.
	/// - Throws: This function will throw an ``LMDBError`` if any value other than `MDB_SUCCESS` or `MDB_NOTFOUND` are returned.
	public func containsEntry<K:MDB_encodable, V:MDB_encodable>(key:K, value:V) throws -> Bool {
		try key.asMDB_val({ keyVal in
			try value.asMDB_val({ valueVal in
				let searchKey = mdb_cursor_get(cursor_handle, &keyVal, nil, MDB_SET)
				switch searchKey {
					case MDB_SUCCESS:
						return true;
					case MDB_NOTFOUND:
						return false;
					default:
						throw LMDBError(returnCode:searchKey)
				}
			})
		})
	}
	
	/// Delete the cursors current key/value entry from the database.
	/// - Parameter flags: Pass ``Operation/Flags/noDupData`` to delete all of the data items for the current key. This flag may only be specified if the database was opened with ``Database/Flags/dupSort``.
	public func deleteEntry(flags:Operation.Flags = Operation.Flags(rawValue:0)) throws {
		let deleteResult = mdb_cursor_del(cursor_handle, flags.rawValue)
		guard deleteResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:deleteResult)
		}
	}
	
	/// Compare two data items according to the database compare function.
	/// - Parameters:
	///   - dataL: Data to compare from the left hand side.
	///   - dataR: Data to compare from the right hand side.
	/// - Returns: A 32 bit integer value `< 0` if the left value is less than the right value, `> 0` if the left value is greater than the right value, and  exactly `0` if the left and right values are identical.
	public func compareKeys<L:MDB_encodable, R:MDB_encodable>(_ dataL:L, _ dataR:R) -> Int32 {
		return dataL.asMDB_val({ lVal in
			return dataR.asMDB_val({ rVal in
				return mdb_cmp(self.txn_handle, self.db_handle, &lVal, &rVal)
			})
		})
	}
	
	///Compare two data items according to the database that this cursor is assigned.
	/// - Parameters:
	///   - dataL: Data to compare from the left hand side.
	///   - dataR: Data to compare from the right hand side.
	/// - Returns: A 32 bit integer value `< 0` if the left value is less than the right value, `> 0` if the left value is greater than the right value, and  exactly `0` if the left and right values are identical.
	public func compareValues<L:MDB_encodable, R:MDB_encodable>(_ dataL:L, _ dataR:R) -> Int32 {
		return dataL.asMDB_val({ lVal in
			return dataR.asMDB_val({ rVal in
				return mdb_dcmp(self.txn_handle, self.db_handle, &lVal, &rVal)
			})
		})
	}
	
	
	/// Counts the number of duplicate entries that exist for the current key.
	/// - Returns: The number of duplicate entries that exist
	public func dupCount() throws -> size_t {
		var dupCount = size_t()
		let countResult = mdb_cursor_count(self.cursor_handle, &dupCount)
		switch countResult { 
			case MDB_SUCCESS:
				return dupCount
			default:
				throw LMDBError(returnCode:countResult)
		}
	}
	
	deinit {
		// LMDB documentation specifies that cursors must be closed in read transactions.
		if (readOnly) {
			mdb_cursor_close(cursor_handle)
		}
	}
}
