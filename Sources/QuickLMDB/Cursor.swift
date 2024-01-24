import CLMDB
import RAW

public protocol MDB_cursor_strict:MDB_cursor where MDB_cursor_dbtype:MDB_db_strict {
	// get entry with strict key and value types
	@discardableResult func MDB_cursor_get_entry(_ operation:Operation, key:inout MDB_cursor_dbtype.MDB_db_key_type, value:inout MDB_cursor_dbtype.MDB_db_val_type) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)
	// get entry with strict key type
	@discardableResult func MDB_cursor_get_entry(_ operation:Operation, key:inout MDB_cursor_dbtype.MDB_db_key_type) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)
	// get entry with strict value type
	@discardableResult func MDB_cursor_get_entry(_ operation:Operation, value:inout MDB_cursor_dbtype.MDB_db_val_type) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)

	// set entry with strict key and value types
	func MDB_cursor_set_entry(key:inout MDB_cursor_dbtype.MDB_db_key_type, value:inout MDB_cursor_dbtype.MDB_db_val_type, flags:Operation.Flags) throws

	// check for entries with strict key type
	func MDB_cursor_contains_entry(key:inout MDB_cursor_dbtype.MDB_db_key_type) throws -> Bool
	// check for entries with strict key and value types
	func MDB_cursor_contains_entry(key:inout MDB_cursor_dbtype.MDB_db_key_type, value:inout MDB_cursor_dbtype.MDB_db_val_type) throws -> Bool
}

public protocol MDB_cursor {
	
	/// the database type backing this cursor.
	associatedtype MDB_cursor_dbtype:MDB_db

	/// the cursor handle for the specific instance.
	var MDB_cursor_handle:OpaquePointer { get }
	/// the database handle for the specific instance.
	var MDB_db_handle:MDB_dbi { get }
	/// the transaction that this instance is operating within.
	var MDB_txn_handle:OpaquePointer { get }

	/// initialize a new cursor from a valid transaction and database handle.
	init<T:MDB_tx>(MDB_db:MDB_dbi, MDB_tx:inout T) throws

	// get entries
	/// get entries with a key and a value.
	/// - parameters:
	/// 	- operation: the operation to perform.
	/// 	- key: the key to search for.
	/// 	- value: the value to search for.
	/// - note: despite requiring inout parameters, the key and value buffers are not modified by this function.
	/// - returns: a tuple containing the key and value buffers as they are stored in the database.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	@discardableResult func MDB_cursor_get_entry<K:RAW_accessible, V:RAW_accessible>(_ operation:Operation, key:inout K, value:inout V) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)
	/// get entries with a key.
	/// - parameters:
	/// 	- operation: the operation to perform.
	/// 	- key: the key to search for.
	/// - note: despite requiring an inout parameter, the key buffer is not modified by this function.
	/// - returns: a tuple containing the key and value buffers as they are stored in the database.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	@discardableResult func MDB_cursor_get_entry<K:RAW_accessible>(_ operation:Operation, key:inout K) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)
	/// get entries based on an specified cursor operation.
	/// - parameters:
	/// 	- operation: the operation to perform.
	/// 	- value: the value to search for.
	/// - note: despite requiring an inout parameter, the value buffer is not modified by this function.
	/// - returns: a tuple containing the key and value buffers as they are stored in the database.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	@discardableResult func MDB_cursor_get_entry<V:RAW_accessible>(_ operation:Operation, value:inout V) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)
	/// get entries based on an specified cursor operation.
	/// - parameters:
	/// 	- operation: the operation to perform.
	/// - returns: a tuple containing the key and value buffers as they are stored in the database.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	@discardableResult func MDB_cursor_get_entry(_ operation:Operation) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>)

	// set entries.
	/// set an entry in the database with a specified key and value. the operation will be committed with the specified flags.
	/// - parameters:
	/// 	- key: the key to set.
	/// 	- value: the value to set.
	/// 	- flags: the flags to use when setting the entry.
	/// - note: despite requiring inout parameters, the key and value buffers are not modified by this function.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_cursor_set_entry<K:RAW_accessible, V:RAW_accessible>(key:inout K, value:inout V, flags:Operation.Flags) throws
	
	// check for entries.
	/// check for an existing entry containing a specified key.
	/// - parameters:
	/// 	- key: the key to search for.
	/// - note: despite requiring an inout parameter, the key buffer is not modified by this function.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_cursor_contains_entry<K:RAW_accessible>(key:inout K) throws -> Bool
	/// check for an existing entry containing a specified key and value.
	/// - parameters:
	/// 	- key: the key to search for.
	/// 	- value: the value to search for.
	/// - note: despite requiring inout parameters, the key and value buffers are not modified by this function.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_cursor_contains_entry<V:RAW_accessible, K:RAW_accessible>(key:inout K, value:inout V) throws -> Bool

	// delete entries.
	/// delete the presently-selected cursor entry from the database.
	/// - parameters:
	/// 	- flags: the flags to use when deleting the entry.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_cursor_delete_current_entry(flags:Operation.Flags) throws

	// compare entries based on the native compare function of the database.
	/// compare entries based on the native compare function of the database.
	/// - parameters:
	/// 	- dataL: the left-hand side of the comparison.
	/// 	- dataR: the right-hand side of the comparison.
	/// - returns: the result of the comparison.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_cursor_compare_keys<L:RAW_accessible, R:RAW_accessible>(_ dataL:inout L, _ dataR:inout R) -> Int32
	// compare entries based on the native compare function of the database.
	/// compare entries based on the native compare function of the database.
	/// - parameters:
	/// 	- dataL: the left-hand side of the comparison.
	/// 	- dataR: the right-hand side of the comparison.
	/// - returns: the result of the comparison.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_cursor_compare_values<L:RAW_accessible, R:RAW_accessible>(_ dataL:inout L, _ dataR:inout R) -> Int32

	// returns the number of duplicate entries in the database for this key.
	/// returns the number of duplicate entries in the database for this key.
	/// - returns: the number of duplicate entries in the database for this key.
	/// - throws: a corresponding ``LMDBError`` if the operation fails.
	func MDB_cursor_dup_count() throws -> size_t
}

extension MDB_cursor {
	/// execute an entry retrieval operation with a specified operation, key and value.
	@discardableResult public func MDB_cursor_get_entry<K:RAW_accessible, V:RAW_accessible>(_ operation:Operation, key:inout K, value:inout V) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>) {
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
	@discardableResult public func MDB_cursor_get_entry<K:RAW_accessible>(_ operation:Operation, key:inout K) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>) {
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
	@discardableResult public func MDB_cursor_get_entry<V:RAW_accessible>(_ operation:Operation, value:inout V) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>) {
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
	@discardableResult public func MDB_cursor_get_entry(_ operation:Operation) throws -> (key:UnsafeMutableBufferPointer<UInt8>, value:UnsafeMutableBufferPointer<UInt8>) {
		var keyVal = MDB_val.nullValue()
		var valueVal = MDB_val.nullValue()
		let cursorResult = mdb_cursor_get(MDB_cursor_handle, &keyVal, &valueVal, operation.mdbValue)
		guard cursorResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:cursorResult)
		}
		return (key:UnsafeMutableBufferPointer<UInt8>(keyVal), value:UnsafeMutableBufferPointer<UInt8>(valueVal))
	}

	/// set the current entry with a specified key and value.
	public func MDB_cursor_set_entry<K:RAW_accessible, V:RAW_accessible>(key: inout K, value:inout V, flags:Operation.Flags) throws {
		try key.RAW_access_mutating { keyBuff in
			var keyVal = MDB_val(keyBuff)
			switch flags.contains(.reserve) {
				
				case true:

					// deploy the encoable functions here, since it will be *technically* more efficient than the accessed method for certain types.
					var valueVal = MDB_val.reserved(forRAW_encodable: &value)
					let result = mdb_cursor_put(MDB_cursor_handle, &keyVal, &valueVal, flags.rawValue)
					guard result == MDB_SUCCESS else {
						throw LMDBError(returnCode:result)
					}
					#if DEBUG
					assert(valueVal.mv_data != nil)
					#endif
					value.RAW_encode(dest:valueVal.mv_data.assumingMemoryBound(to:UInt8.self))
				
				
				case false:

					// deploy accessable functions.
					try value.RAW_access_mutating { valueBuff in
						var valueVal = MDB_val(valueBuff)
						let result = mdb_cursor_put(MDB_cursor_handle, &keyVal, &valueVal, flags.rawValue)
						guard result == MDB_SUCCESS else {
							throw LMDBError(returnCode:result)
						}
					}
			}
		}
	}

	public func MDB_cursor_contains_entry<K:RAW_accessible>(key:inout K) throws -> Bool {
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

	public func MDB_cursor_contains_entry<K:RAW_accessible, V:RAW_accessible>(key:inout K, value:inout V) throws -> Bool {
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

	public func MDB_cursor_delete_current_entry(flags:Operation.Flags) throws {
		let deleteResult = mdb_cursor_del(MDB_cursor_handle, flags.rawValue)
		guard deleteResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:deleteResult)
		}
	}

	public func MDB_cursor_compare_keys<L:RAW_accessible, R:RAW_accessible>(_ dataL:inout L, _ dataR:inout R) -> Int32 {
		return dataL.RAW_access_mutating { lBuff in
			return dataR.RAW_access_mutating { rBuff in
				var lVal = MDB_val(lBuff)
				var rVal = MDB_val(rBuff)
				return mdb_cmp(MDB_txn_handle, MDB_db_handle, &lVal, &rVal)
			}
		}
	}

	public func MDB_cursor_compare_values<L:RAW_accessible, R:RAW_accessible>(_ dataL:inout L, _ dataR:inout R) -> Int32 {
		return dataL.RAW_access_mutating { lBuff in
			return dataR.RAW_access_mutating { rBuff in
				var lVal = MDB_val(lBuff)
				var rVal = MDB_val(rBuff)
				return mdb_dcmp(MDB_txn_handle, MDB_db_handle, &lVal, &rVal)
			}
		}
	}

	public func MDB_cursor_dup_count() throws -> size_t {
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

extension Cursor:MDB_cursor_strict where MDB_cursor_dbtype:MDB_db_strict {}

extension Cursor:MDB_cursor where MDB_cursor_dbtype:MDB_db {}

/// LMDB cursor. this is defined as a class so that the cursor can be auto-closed when references to this instances are free'd from memory.
/// - conforms to the ``MDB_cursor`` protocol with any database (unconditional)
/// - conforms to the ``MDB_cursor_strict`` protocol with any database that conforms to the ``MDB_db_strict`` protocol.
public final class Cursor<D:MDB_db> {
    public typealias MDB_cursor_dbtype = D

	/// this is the pointer to the `MDB_cursor` struct associated with a given instance.
	public let MDB_cursor_handle:OpaquePointer
	
	/// this is the database that this cursor is associated with.
	public let MDB_db_handle:MDB_dbi
	
	/// pointer to the `MDB_txn` struct associated with a given instance.
	public let MDB_txn_handle:OpaquePointer

	/// stores the readonly state of the attached transaction.
	private let MDB_txn_readonly:Bool
	
	/// opens a new cursor instance from a given database and transaction pairing.
	public init<T:MDB_tx>(MDB_db dbh:MDB_dbi, MDB_tx:inout T) throws {
		var buildCursor:OpaquePointer? = nil
		let openCursorResult = mdb_cursor_open(MDB_tx.MDB_tx_handle, dbh, &buildCursor)
		guard openCursorResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:openCursorResult)
		}
		MDB_cursor_handle = buildCursor!
		MDB_db_handle = dbh
		MDB_txn_handle = MDB_tx.MDB_env_handle
		MDB_txn_readonly = MDB_tx.MDB_tx_readOnly
	}

	deinit {
		mdb_cursor_close(MDB_cursor_handle)
	}
}
