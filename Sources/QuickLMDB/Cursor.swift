import CLMDB
import RAW

public protocol MDB_cursor {

	/// the cursor handle for the specific instance.
	var MDB_cursor_handle:OpaquePointer { get }
	/// the database handle for the specific instance.
	var MDB_db_handle:MDB_dbi { get }
	/// the transaction that this instance is operating within.
	var MDB_txn_handle:OpaquePointer { get }

	/// initialize a new cursor from a valid transaction and database handle.
	init<D:MDB_db, T:MDB_tx>(MDB_db:D, MDB_tx:T) throws

	// get entries
	/// get entries with a key and a value.
	/// - parameters:
	/// 	- operation: the operation to perform.
	/// 	- key: the key to search for.
	/// 	- value: the value to search for.
	/// - note: despite requiring inout parameters, the key and value buffers are not modified by this function.
	/// - returns: a tuple containing the key and value buffers as they are stored in the database.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	@discardableResult func MDB_get_entry<K:RAW_accessible, V:RAW_accessible>(_ operation:Cursor.Operation, key:inout K, value:inout V) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)
	/// get entries with a key.
	/// - parameters:
	/// 	- operation: the operation to perform.
	/// 	- key: the key to search for.
	/// - note: despite requiring an inout parameter, the key buffer is not modified by this function.
	/// - returns: a tuple containing the key and value buffers as they are stored in the database.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	@discardableResult func MDB_get_entry<K:RAW_accessible>(_ operation:Cursor.Operation, key:inout K) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)
	/// get entries based on an specified cursor operation.
	/// - parameters:
	/// 	- operation: the operation to perform.
	/// 	- value: the value to search for.
	/// - note: despite requiring an inout parameter, the value buffer is not modified by this function.
	/// - returns: a tuple containing the key and value buffers as they are stored in the database.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	@discardableResult func MDB_get_entry<V:RAW_accessible>(_ operation:Cursor.Operation, value:inout V) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)
	/// get entries based on an specified cursor operation.
	/// - parameters:
	/// 	- operation: the operation to perform.
	/// - returns: a tuple containing the key and value buffers as they are stored in the database.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	@discardableResult func MDB_get_entry(_ operation:Cursor.Operation) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)

	// set entries.
	/// set an entry in the database with a specified key and value. the operation will be committed with the specified flags.
	/// - parameters:
	/// 	- key: the key to set.
	/// 	- value: the value to set.
	/// 	- flags: the flags to use when setting the entry.
	/// - note: despite requiring inout parameters, the key and value buffers are not modified by this function.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_set_entry<K:RAW_accessible, V:RAW_accessible>(key:inout K, value:inout V, flags:Cursor.Operation.Flags) throws
	
	// check for entries.
	/// check for an existing entry containing a specified key.
	/// - parameters:
	/// 	- key: the key to search for.
	/// - note: despite requiring an inout parameter, the key buffer is not modified by this function.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_contains_entry<K:RAW_accessible>(key:inout K) throws -> Bool
	/// check for an existing entry containing a specified key and value.
	/// - parameters:
	/// 	- key: the key to search for.
	/// 	- value: the value to search for.
	/// - note: despite requiring inout parameters, the key and value buffers are not modified by this function.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_contains_entry<K:RAW_accessible, V:RAW_accessible>(key:inout K, value:inout V) throws -> Bool

	// delete entries.
	/// delete the presently-selected cursor entry from the database.
	/// - parameters:
	/// 	- flags: the flags to use when deleting the entry.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_delete_current_entry(flags:Cursor.Operation.Flags) throws

	// compare entries based on the native compare function of the database.
	/// compare entries based on the native compare function of the database.
	/// - parameters:
	/// 	- dataL: the left-hand side of the comparison.
	/// 	- dataR: the right-hand side of the comparison.
	/// - returns: the result of the comparison.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_compare_keys<L:RAW_accessible, R:RAW_accessible>(_ dataL:inout L, _ dataR:inout R) -> Int32
	// compare entries based on the native compare function of the database.
	/// compare entries based on the native compare function of the database.
	/// - parameters:
	/// 	- dataL: the left-hand side of the comparison.
	/// 	- dataR: the right-hand side of the comparison.
	/// - returns: the result of the comparison.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_compare_dupsort_values<L:RAW_accessible, R:RAW_accessible>(_ dataL:inout L, _ dataR:inout R) -> Int32

	// returns the number of duplicate entries in the database for this key.
	/// returns the number of duplicate entries in the database for this key.
	/// - returns: the number of duplicate entries in the database for this key.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_dup_count() throws -> size_t
}

extension MDB_cursor {
	/// execute an entry retrieval operation with a specified operation, key and value.
	@discardableResult public func MDB_get_entry<K:RAW_accessible, V:RAW_accessible>(_ operation:Cursor.Operation, key:inout K, value:inout V) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>) {
		return try key.RAW_access_mutating { keyBuff in
			return try value.RAW_access_mutating { valueBuff in
				var keyVal = MDB_val(keyBuff)
				var valueVal = MDB_val(valueBuff)
				let cursorResult = mdb_cursor_get(MDB_cursor_handle, &keyVal, &valueVal, operation.mdbValue)
				guard cursorResult == MDB_SUCCESS else {
					throw LMDBError(returnCode:cursorResult)
				}
				return (key:UnsafeMutableBufferPointer<UInt8>(keyVal), value:UnsafeMutableBufferPointer<UInt8>(valueVal))
			}
		}
	}

	/// execute an entry retrieval operation with a specified operation and key.
	@discardableResult public func MDB_get_entry<K:RAW_accessible>(_ operation:Cursor.Operation, key:inout K) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>) {
		return try key.RAW_access_mutating { keyBuff in
			var keyVal = MDB_val(keyBuff)
			var valueVal = MDB_val.nullValue()
			let cursorResult = mdb_cursor_get(MDB_cursor_handle, &keyVal, &valueVal, operation.mdbValue)
			guard cursorResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:cursorResult)
			}
			return (key:UnsafeMutableBufferPointer<UInt8>(keyVal), value:UnsafeMutableBufferPointer<UInt8>(valueVal))
		}
	}

	/// execute an entry retrieval operation with a specified operation and value.
	@discardableResult public func MDB_get_entry<V:RAW_accessible>(_ operation:Cursor.Operation, value:inout V) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>) {
		return try value.RAW_access_mutating { valueBuff in
			var keyVal = MDB_val.nullValue()
			var valueVal = MDB_val(valueBuff)
			let cursorResult = mdb_cursor_get(MDB_cursor_handle, &keyVal, &valueVal, operation.mdbValue)
			guard cursorResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:cursorResult)
			}
			return (key:UnsafeMutableBufferPointer<UInt8>(keyVal), value:UnsafeMutableBufferPointer<UInt8>(valueVal))
		}
	}

	/// execute an entry retrieval operation with a specified operation only.
	@discardableResult public func MDB_get_entry(_ operation:Cursor.Operation) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>) {
		var keyVal = MDB_val.nullValue()
		var valueVal = MDB_val.nullValue()
		let cursorResult = mdb_cursor_get(MDB_cursor_handle, &keyVal, &valueVal, operation.mdbValue)
		guard cursorResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:cursorResult)
		}
		return (key:UnsafeMutableBufferPointer<UInt8>(keyVal), value:UnsafeMutableBufferPointer<UInt8>(valueVal))
	}

	/// set the current entry with a specified key and value.
	public func MDB_set_entry<K:RAW_accessible, V:RAW_accessible>(key: inout K, value:inout V, flags:Cursor.Operation.Flags) throws {
		try key.RAW_access_mutating { keyBuff in
			try value.RAW_access_mutating { valueBuff in
				var keyVal = MDB_val(keyBuff)
				switch flags.contains(.reserve) {
					case true:
						var valueVal = MDB_val.nullValue()
						valueVal.mv_size = valueBuff.count
						let result = mdb_cursor_put(MDB_cursor_handle, &keyVal, &valueVal, flags.rawValue)
						guard result == MDB_SUCCESS else {
							throw LMDBError(returnCode:result)
						}
						#if DEBUG
						assert(valueVal.mv_data != nil)
						#endif
						_ = RAW_memcpy(valueVal.mv_data, valueBuff.baseAddress!, valueBuff.count)
					case false:
						var valueVal = MDB_val(valueBuff)
						let result = mdb_cursor_put(MDB_cursor_handle, &keyVal, &valueVal, flags.rawValue)
						guard result == MDB_SUCCESS else {
							throw LMDBError(returnCode:result)
						}
				}
			}
		}
	}

	public func MDB_contains_entry<K:RAW_accessible>(key:inout K) throws -> Bool {
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

	public func MDB_contains_entry<K:RAW_accessible, V:RAW_accessible>(key:inout K, value:inout V) throws -> Bool {
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

	public func MDB_delete_current_entry(flags:Cursor.Operation.Flags) throws {
		let deleteResult = mdb_cursor_del(MDB_cursor_handle, flags.rawValue)
		guard deleteResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:deleteResult)
		}
	}

	public func MDB_compare_keys<L:RAW_accessible, R:RAW_accessible>(_ dataL:inout L, _ dataR:inout R) -> Int32 {
		return dataL.RAW_access_mutating { lBuff in
			return dataR.RAW_access_mutating { rBuff in
				var lVal = MDB_val(lBuff)
				var rVal = MDB_val(rBuff)
				return mdb_cmp(MDB_txn_handle, MDB_db_handle, &lVal, &rVal)
			}
		}
	}

	public func MDB_compare_dupsort_values<L:RAW_accessible, R:RAW_accessible>(_ dataL:inout L, _ dataR:inout R) -> Int32 {
		return dataL.RAW_access_mutating { lBuff in
			return dataR.RAW_access_mutating { rBuff in
				var lVal = MDB_val(lBuff)
				var rVal = MDB_val(rBuff)
				return mdb_dcmp(MDB_txn_handle, MDB_db_handle, &lVal, &rVal)
			}
		}
	}

	public func MDB_dup_count() throws -> size_t {
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

/// LMDB cursor. this is defined as a class so that the cursor can be auto-closed when references to this instances are free'd from memory.
public final class Cursor:MDB_cursor {
	
	/// this is the complete toolset of operations that can be utilized to retrieve and navigate entries in the database.
	public enum Operation {
		
		/// operation flags modify the way that entries are stored in the database. In LMDB documentation, these are known as "write flags".
		public struct Flags:OptionSet {
			
			/// the raw integer value for this flag. Can be passed directly into 
			public let rawValue:UInt32
			
			/// create a flag with its integer value.
			public init(rawValue:UInt32) {
				self.rawValue = rawValue
			}

			/// do not write the entry if the key already exists in the database. In this case, ``LMDBError/keyExists`` is thrown.
			public static let noOverwrite = Flags(rawValue:UInt32(MDB_NOOVERWRITE))
			
			/// only for use with ``Database/Flags/dupSort``
			/// - for ``Cursor/setEntry(value:forKey:flags:)``: don't write if the key and data pair already exist.
			/// - for ``Cursor/deleteEntry(flags:)``: remove all duplicate data items from the database.
			public static let noDupData = Flags(rawValue:UInt32(MDB_NODUPDATA))
			
			/// for ``Cursor/setEntry(value:forKey:flags:)``: overwrite the current key/value pair.
			public static let current = Flags(rawValue:UInt32(MDB_CURRENT))
			
			/// for ``Cursor/setEntry(value:forKey:flags:)``: just reserve space for the value, don't copy it. return a pointer to the reserved space.
			public static let reserve = Flags(rawValue:UInt32(MDB_RESERVE))
			
			/// pre-sorted keys are being stored in the database. don't split full pages.
			public static let append = Flags(rawValue:UInt32(MDB_APPEND))
			
			/// pre-sorted key/value entires are being stored in the database. don't split full pages.
			public static let appendDup = Flags(rawValue:UInt32(MDB_APPENDDUP))
			
			/// store multiple data items in one call. only for ``Database/Flags/dupFixed``.
			public static let multiple = Flags(rawValue:UInt32(MDB_MULTIPLE))
		}
		
		/// position at first key/data item.
		case first
		
		/// position at first data item of current key. Only use with ``Database/Flags/dupSort`` enabled.
		case firstDup
		
		/// position at key/data pair. Only use with ``Database/Flags/dupSort`` enabled.
		case getBoth
		
		/// position at key, nearest data. Only use with ``Database/Flags/dupSort`` enabled.
		case getBothRange
		
		/// return the key/value entry at the cursor's current position.
		case getCurrent
		
		/// return key and up to a page of duplicate data items from the current cursor position. Move cursor to prepare for ``Cursor/Operation/nextMultiple``.
		case getMultiple
		
		/// position at the last key/value item.
		case last
		
		/// position at the last data item of the current key.
		case lastDup
		
		/// position at the next data item.
		case next
		
		/// position at the next data item of the current key.
		case nextDup
		
		/// return key and up to a page of duplicate data items from next cursor position. Move cursor to prepare for the next ``Cursor/Operation/nextMultiple``.
		case nextMultiple
		
		/// position at first data item of the next key.
		case nextNoDup
		
		/// position at previous data item.
		case previous
		
		/// position at previous data item of current key. Only for ``Database/Flags/dupSort``.
		case previousDup
		
		/// position at lsat data item of previous key.
		case previousNoDup
		
		/// position at the specified key.
		/// - returned key will point to the same buffer that was passed into the cursor.
		case set
		
		/// position at the specified key.
		/// - returned key will point to the buffer that is stored in the memory map.
		case setKey
		
		/// position at the first key greater than or equal to specified key.
		case setRange
	}
	
	/// this is the pointer to the `MDB_cursor` struct associated with a given instance.
	public let MDB_cursor_handle:OpaquePointer
	
	/// this is the database that this cursor is associated with.
	public let MDB_db_handle:MDB_dbi
	
	/// pointer to the `MDB_txn` struct associated with a given instance.
	public let MDB_txn_handle:OpaquePointer

	/// stores the readonly state of the attached transaction.
	private let MDB_txn_readonly:Bool

	/// opens a new cursor instance from a given database and transaction pairing.
	public init<D:MDB_db, T:MDB_tx>(MDB_db dbh:D, MDB_tx:T) throws {
		var buildCursor:OpaquePointer? = nil
		let openCursorResult = mdb_cursor_open(MDB_tx.MDB_tx_handle, dbh.MDB_db_handle, &buildCursor)
		guard openCursorResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openCursorResult)
		}
		MDB_cursor_handle = buildCursor!
		MDB_db_handle = dbh.MDB_db_handle
		MDB_txn_handle = MDB_tx.MDB_env_handle
		MDB_txn_readonly = MDB_tx.MDB_tx_readOnly
	}
	
	deinit {
		// LMDB documentation specifies that cursors must be closed in read transactions.
		if (MDB_txn_readonly) {
			mdb_cursor_close(MDB_cursor_handle)
		}
	}
}


extension Cursor.Operation {
	/// initialize an operation with a specified ``MDB_cursor_op``.
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
	
	/// retrieve the `MDB_cursor_op` value for this Operation.
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