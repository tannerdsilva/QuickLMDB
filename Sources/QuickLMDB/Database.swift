import CLMDB
import RAW

public protocol MDB_db_static<MDB_db_key_type, MDB_db_val_type>:MDB_db_strict {

	/// the environment handle primitive that LMDB uses.
	init<E:MDB_env, T:MDB_tx>(MDB_env:E, MDB_tx:inout T) throws

	/// the name of the database.
	static var MDB_db_name:String? { get }
	/// the flags that will be used when opening the database.
	static var MDB_db_flags:Database.Flags { get }
}

extension MDB_db_static {
	public var MDB_db_name:String? { return Self.MDB_db_name }
	public var MDB_db_flags:Database.Flags { return Self.MDB_db_flags }

	public init<E:MDB_env, T:MDB_tx>(MDB_env env:E, MDB_tx tx:inout T) throws {
		try self.init(MDB_env:env, MDB_db_name:Self.MDB_db_name, MDB_db_flags:Self.MDB_db_flags, MDB_tx:&tx)
	}
}

/// a database whose keys and values are strictly typed
public protocol MDB_db_strict<MDB_db_key_type, MDB_db_val_type>:MDB_db where MDB_db_cursor_type:MDB_cursor_strict {

	/// the key type that will be used to access the database.
	associatedtype MDB_db_key_type:MDB_convertible
	/// the value type that will be used to access the database.
	associatedtype MDB_db_val_type:MDB_convertible

	// get an entry from the database.
	func MDB_db_get_entry<T:MDB_tx>(key:UnsafePointer<MDB_db_key_type>, MDB_tx:inout T) throws -> MDB_db_val_type
	
	// write an entry to the database.
	func MDB_db_set_entry<T:MDB_tx>(key:UnsafePointer<MDB_db_key_type>, value:UnsafePointer<MDB_db_val_type>, flags:Operation.Flags, MDB_tx:inout T) throws

	// remove an entry from the database.
	func MDB_db_delete_entry<T:MDB_tx>(key:UnsafePointer<MDB_db_key_type>, MDB_tx:inout T) throws
	func MDB_db_delete_entry<T:MDB_tx>(key:UnsafePointer<MDB_db_key_type>, value:UnsafePointer<MDB_db_val_type>, MDB_tx:inout T) throws
}

extension MDB_db_strict {
	public func MDB_db_get_entry<T:MDB_tx>(key:UnsafePointer<MDB_db_key_type>, MDB_tx:inout T) throws -> MDB_db_val_type {
		return try self.MDB_db_get_entry(key:key, as:MDB_db_val_type.self, MDB_tx:&MDB_tx)!
	}
}

public protocol MDB_db {

	associatedtype MDB_db_cursor_type:MDB_cursor

	/// the environment handle primitive that LMDB uses.
	var MDB_env_handle:OpaquePointer { get }
	/// the database name.
	var MDB_db_name:String? { get }
	/// the database handle primitive that LMDB uses.
	var MDB_db_handle:MDB_dbi { get }

	/// create a new database from the specified environment.
	init<E:MDB_env, T:MDB_tx>(MDB_env:E, MDB_db_name:String?, MDB_db_flags:Database.Flags, MDB_tx:inout T) throws

	func MDB_cursor<T:MDB_tx>(MDB_tx:inout T) throws -> MDB_db_cursor_type

	// reading entries in the database
	/// get an entry from the database.
	///	- parameters:
	///		- key: the key that will be searched in the database.
	///		- as: the type to decode from the database.
	///		- MDB_tx: the transaction to use for the entry search.
	/// - throws: a corresponding ``LMDBError.notFound`` if the key does not exist, or other errors for more obscure circumstances.
	/// - note: despite this function requiring an inout parameter, the passed value is not mutated. it is treated as a read-only value.
	///	- returns: the decoded value type, if it successfully decoded from the database. if the entry is found but it fails to decode, `nil` is returned.
	func MDB_db_get_entry<K:RAW_accessible, V:RAW_decodable, T:MDB_tx>(key:UnsafePointer<K>, as:V.Type, MDB_tx:inout T) throws -> V?
	/// search the database for the existence of a given entry key.
	/// - parameters:
	/// 	- key: the key that will be searched in the database.
	/// 	- MDB_tx: the transaction to use for the entry search.
	/// - note: despite this function requiring an inout parameter, the passed value is not mutated. it is treated as a read-only value.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be searched.
	/// - returns: `true` if the entry exists, `false` if it does not.
	func MDB_db_contains_entry<K:RAW_accessible, T:MDB_tx>(key:UnsafePointer<K>, MDB_tx:inout T) throws -> Bool

	func MDB_db_contains_entry<K:RAW_accessible, V:RAW_accessible, T:MDB_tx>(key:UnsafePointer<K>, value:UnsafePointer<V>, MDB_tx:inout T) throws -> Bool

	// writing entries to the database.
	/// set an entry in the database.
	/// - parameters:
	/// 	- key: the key that will be set in the database.
	/// 	- value: the value that will be set in the database.
	/// 	- flags: the flags that will be used when setting the entry.
	/// 	- MDB_tx: the transaction to use for the entry set.
	/// - note: despite this function requiring inout parameters, the passed values are not mutated. they are treated as read-only values.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be set.
	func MDB_db_set_entry<K:RAW_accessible, V:RAW_encodable, T:MDB_tx>(key:UnsafePointer<K>, value:UnsafePointer<V>, flags:Operation.Flags, MDB_tx:inout T) throws

	// removing entries to the database
	/// remove an entry key (along with its corresponding value) from the database.
	/// - parameters:
	/// 	- key: the key that will be removed from the database.
	/// 	- MDB_tx: the transaction to use for the entry removal.
	/// - note: despite this function requiring an inout parameter, the passed value is not mutated. it is treated as a read-only value.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be removed.
	func MDB_db_delete_entry<K:RAW_accessible, T:MDB_tx>(key:UnsafePointer<K>, MDB_tx:inout T) throws
	/// remove a specific key and value pairing from the database.
	/// - parameters:
	/// 	- key: the key that will be removed from the database.
	/// 	- value: the value that will be removed from the database.
	/// 	- MDB_tx: the transaction to use for the entry removal.
	/// - note: despite this function requiring inout parameters, the passed values are not mutated. they are treated as read-only values.
	/// - throws: a corresponding ``LMDBError`` if the entry could not be removed.
	func MDB_db_delete_entry<K:RAW_accessible, V:RAW_accessible, T:MDB_tx>(key:UnsafePointer<K>, value:UnsafePointer<V>, MDB_tx:inout T) throws
	/// remove all entries from the database.
	/// - parameters:
	/// 	- MDB_tx: the transaction to use for the entry removal.
	/// - throws: a corresponding ``LMDBError`` if the entries could not be removed.
	func MDB_db_delete_all_entries<T:MDB_tx>(MDB_tx:inout T) throws

	/// returns the statistics for the database.
	func MDB_db_get_statistics<T:MDB_tx>(MDB_tx:inout T) throws -> MDB_stat

	/// returns the flags that were used when opening the database.
	func MDB_db_get_flags<T:MDB_tx>(MDB_tx:inout T) throws -> Database.Flags
}

extension MDB_db {

	public typealias MDB_db_cursor_type = Cursor<Self>

	public func MDB_cursor<T:MDB_tx>(MDB_tx tx:inout T) throws -> Cursor<Self> {
		return try Cursor<Self>(MDB_db:MDB_db_handle, MDB_tx:&tx)
	}

	public func MDB_db_get_entry<K:RAW_accessible, V:RAW_decodable, T:MDB_tx>(key:UnsafePointer<K>, as:V.Type, MDB_tx tx:inout T) throws -> V? {
		return V(RAW_decode:try key.pointee.RAW_access { ptr in
			var keyVal = MDB_val(ptr)
			var dbValue = MDB_val.nullValue()
			let valueResult = mdb_get(tx.MDB_tx_handle, MDB_db_handle, &keyVal, &dbValue)
			guard valueResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:valueResult)
			}
			return dbValue
		})
	}

	public func MDB_db_contains_entry<K:RAW_accessible, T:MDB_tx>(key:UnsafePointer<K>, MDB_tx tx:inout T) throws -> Bool {
		return try key.pointee.RAW_access { ptr in
			var keyVal = MDB_val(ptr)
			let valueResult = mdb_get(tx.MDB_tx_handle, MDB_db_handle, &keyVal, nil)
			switch valueResult {
				case MDB_SUCCESS:
					return true
				case MDB_NOTFOUND:
					return false
				default:
					throw LMDBError(returnCode:valueResult)
			}
		}
	}

	public func MDB_db_contains_entry<K:RAW_accessible, V:RAW_accessible, T:MDB_tx>(key:UnsafePointer<K>, value:UnsafePointer<V>, MDB_tx tx:inout T) throws -> Bool {
		return try key.pointee.RAW_access { keyPtr in
			return try value.pointee.RAW_access { valPtr in
				var keyVal = MDB_val(keyPtr)
				var valVal = MDB_val(valPtr)
				let valueResult = mdb_get(tx.MDB_tx_handle, MDB_db_handle, &keyVal, &valVal)
				switch valueResult {
					case MDB_SUCCESS:
						return true
					case MDB_NOTFOUND:
						return false
					default:
						throw LMDBError(returnCode:valueResult)
				}
			}
		}
	}

	public func MDB_db_set_entry<K:RAW_accessible, V:RAW_encodable, T:MDB_tx>(key:UnsafePointer<K>, value:UnsafePointer<V>, flags:Operation.Flags, MDB_tx tx:inout T) throws {
		try key.pointee.RAW_access { ptr in
			var keyVal = MDB_val(ptr)
			switch flags.contains(.reserve) {
				case true:
					var mdbValVal = MDB_val.reserved(forRAW_encodable:value)
					let dbResult = mdb_put(tx.MDB_tx_handle, MDB_db_handle, &keyVal, &mdbValVal, flags.rawValue)
					guard dbResult == MDB_SUCCESS else {
						throw LMDBError(returnCode:dbResult)
					}
					value.pointee.RAW_encode(dest:mdbValVal.mv_data.assumingMemoryBound(to:UInt8.self))
				case false:
					try value.pointee.RAW_access({ valBuff in
						var mdbValVal = MDB_val(valBuff)
						let dbResult = mdb_put(tx.MDB_tx_handle, MDB_db_handle, &keyVal, &mdbValVal, flags.rawValue)
						guard dbResult == MDB_SUCCESS else {
							throw LMDBError(returnCode:dbResult)
						}
					})
			}
		}
	}

	public func MDB_db_delete_entry<K:RAW_accessible, T:MDB_tx>(key:UnsafePointer<K>, MDB_tx tx:inout T) throws {
		try key.pointee.RAW_access { ptr in
			var keyVal = MDB_val(ptr)
			let dbResult = mdb_del(tx.MDB_tx_handle, MDB_db_handle, &keyVal, nil)
			guard dbResult == MDB_SUCCESS else {
				throw LMDBError(returnCode:dbResult)
			}
		}
	}

	public func MDB_db_delete_entry<K:RAW_accessible, V:RAW_accessible, T:MDB_tx>(key:UnsafePointer<K>, value:UnsafePointer<V>, MDB_tx tx:inout T) throws {
		return try key.pointee.RAW_access({ keyBuff in
			return try value.pointee.RAW_access({ valBuff in
				var keyV = MDB_val(keyBuff)
				var valV = MDB_val(valBuff)
				let dbResult = mdb_del(tx.MDB_tx_handle, MDB_db_handle, &keyV, &valV)
				guard dbResult == MDB_SUCCESS else {
					throw LMDBError(returnCode:dbResult)
				}
			})
		})
	}

	public func MDB_db_delete_all_entries<T:MDB_tx>(MDB_tx tx:inout T) throws {
		let dbResult = mdb_drop(tx.MDB_tx_handle, MDB_db_handle, 0)
		guard dbResult == MDB_SUCCESS else {
			throw LMDBError(returnCode:dbResult)
		}
	}

	public func MDB_db_get_statistics<T:MDB_tx>(MDB_tx tx:inout T) throws -> MDB_stat {
		var statObj = MDB_stat()
		let getStatTry = mdb_stat(tx.MDB_tx_handle, MDB_db_handle, &statObj)
		guard getStatTry == 0 else {
			throw LMDBError(returnCode:getStatTry)
		}
		return statObj
	}

	public func MDB_db_get_flags<T:MDB_tx>(MDB_tx tx:inout T) throws -> Database.Flags {
		var captureFlags = UInt32()
		let getFlagsTry = mdb_dbi_flags(tx.MDB_tx_handle, MDB_db_handle, &captureFlags)
		guard getFlagsTry == 0 else {
			throw LMDBError(returnCode:getFlagsTry)
		}
		return Database.Flags(rawValue:captureFlags)
	}
}

// normal database
/// an LMDB database that operates with arbitrary key and value types. keys and values are specified uniquely for each function call.
public struct Database:MDB_db, Sendable {

    public let MDB_env_handle:OpaquePointer
    public let MDB_db_name:String?
    public let MDB_db_handle:MDB_dbi

    public init<E:MDB_env, T:MDB_tx>(MDB_env env:E, MDB_db_name:String?, MDB_db_flags:Database.Flags, MDB_tx tx:inout T) throws {
        var captureHandle = MDB_dbi()
		let openDatabaseResult = mdb_dbi_open(tx.MDB_tx_handle, MDB_db_name, UInt32(MDB_db_flags.rawValue), &captureHandle)
		guard openDatabaseResult == 0 else {
			throw LMDBError(returnCode:openDatabaseResult)
		}
		self.MDB_db_handle = captureHandle
		self.MDB_env_handle = env.MDB_env_handle
		self.MDB_db_name = MDB_db_name
    }
}


// strict database
extension Database {

	/// an LMDB database that operates strictly with a known key and value type. this protocol assumes that RAW_decodable types will NEVER initialize to nil if an entry exists in the database.
	/// - automatically (and unconditionally) applies the sorting algorithm of the key type to the database.
	/// - automatically applies the sorting algorithm of the value type to the database ONLY IF the database is used with ``Database.Flags.dupSort``.
	public struct Strict<K:MDB_convertible, V:MDB_convertible>:MDB_db_strict, Sendable {

	    public let MDB_env_handle:OpaquePointer
	    public let MDB_db_name:String?
	    public let MDB_db_handle:MDB_dbi

	    public init<E, T>(MDB_env env:E, MDB_db_name name:String?, MDB_db_flags flags:Database.Flags, MDB_tx tx:inout T) throws where E:MDB_env, T:MDB_tx {
			var captureHandle = MDB_dbi()
			var dbResponse = mdb_dbi_open(tx.MDB_tx_handle, name, UInt32(flags.rawValue), &captureHandle)
			guard dbResponse == 0 else {
				throw LMDBError(returnCode:dbResponse)
			}
			// set the key compare
			dbResponse = mdb_set_compare(tx.MDB_tx_handle, captureHandle, K.MDB_compare_f)
			guard dbResponse == 0 else {
				throw LMDBError(returnCode:dbResponse)
			}
			if flags.contains(.dupSort) {
				// set the value compare
				dbResponse = mdb_set_dupsort(tx.MDB_tx_handle, captureHandle, V.MDB_compare_f)
				guard dbResponse == 0 else {
					throw LMDBError(returnCode:dbResponse)
				}
			}
			self.MDB_db_handle = captureHandle
			self.MDB_env_handle = env.MDB_env_handle
			self.MDB_db_name = name
	    }

		public typealias MDB_db_key_type = K
		public typealias MDB_db_val_type = V
	}
}