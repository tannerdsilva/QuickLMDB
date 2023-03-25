import CLMDB

extension Database {
	public func setObject<K: MDB_encodable, V: AnyObject>(value: V, forKey key: K, flags: Cursor.Operation.Flags = [], tx txn: Transaction?) throws {
		try key.asMDB_val { keyVal in
			let tx:Transaction
			if (txn == nil) {
				tx = try Transaction(environment:env_handle, readOnly:false, parent:nil)
			} else {
				tx = txn!
			}
			// Check if there is an existing entry for the given key
			var existingEntry = MDB_val()
			let getResult = mdb_get(tx.txn_handle, db_handle, &keyVal, &existingEntry)
			if getResult == MDB_SUCCESS && existingEntry.mv_size == MemoryLayout<UnsafeRawPointer>.stride {
				// Properly release the existing entry
				let existingPointer = existingEntry.mv_data.assumingMemoryBound(to: UnsafeRawPointer.self).pointee
				let unmanagedExistingValue = Unmanaged<V>.fromOpaque(existingPointer)
				unmanagedExistingValue.release()
			}

			// Store the new object
			let unmanagedValue = Unmanaged.passRetained(value)
			let pointer = unmanagedValue.toOpaque()
			var valueVal = MDB_val(mv_size: MemoryLayout<UnsafeRawPointer>.stride, mv_data: UnsafeMutableRawPointer(mutating: pointer))

			let valueResult: Int32
			valueResult = mdb_put(tx.txn_handle, db_handle, &keyVal, &valueVal, flags.rawValue)

			guard valueResult == MDB_SUCCESS else {
				unmanagedValue.release()
				throw LMDBError(returnCode: valueResult)
			}
			if (txn == nil) {
				try tx.commit()
			}
		}
	}

	
	public func getObject<K: MDB_encodable, T: AnyObject>(type:T.Type, forKey key: K, tx txn: Transaction?) throws -> T? {
		return try key.asMDB_val { keyVal in
			let tx: Transaction
			if txn == nil {
				tx = try Transaction(environment: env_handle, readOnly: true, parent: nil)
			} else {
				tx = txn!
			}

			var valueVal = MDB_val()
			let getResult = mdb_get(tx.txn_handle, db_handle, &keyVal, &valueVal)

			guard getResult == MDB_SUCCESS else {
				throw LMDBError(returnCode: getResult)
			}

			guard valueVal.mv_size == MemoryLayout<UnsafeRawPointer>.stride else {
				throw LMDBError.corrupted
			}

			let storedPointer = valueVal.mv_data.assumingMemoryBound(to: UnsafeRawPointer.self).pointee
			let unmanagedObject = Unmanaged<T>.fromOpaque(storedPointer)

			// Retain the object to return an additionally retained object for the user
			let retainedObject = unmanagedObject.takeRetainedValue()

			if txn == nil {
				try tx.commit()
			}

			return retainedObject
		}
	}


	public func deleteObject<K: MDB_encodable, T:AnyObject>(type:T.Type, forKey key: K, tx txn: Transaction?) throws {
		try key.asMDB_val { keyVal in
			let tx: Transaction
			if txn == nil {
				tx = try Transaction(environment: env_handle, readOnly: false, parent: nil)
			} else {
				tx = txn!
			}

			// Check if there is an existing entry for the given key
			var existingEntry = MDB_val()
			let getResult = mdb_get(tx.txn_handle, db_handle, &keyVal, &existingEntry)
			
			guard getResult == MDB_SUCCESS else {
				if getResult == MDB_NOTFOUND {
					return
				} else {
					throw LMDBError(returnCode: getResult)
				}
			}

			guard existingEntry.mv_size == MemoryLayout<UnsafeRawPointer>.stride else {
				throw LMDBError.corrupted
			}

			// Properly release the existing entry
			let existingPointer = existingEntry.mv_data.assumingMemoryBound(to: UnsafeRawPointer.self).pointee
			let unmanagedExistingValue = Unmanaged<T>.fromOpaque(existingPointer)

			// Delete the object from the database
			let deleteResult = mdb_del(tx.txn_handle, db_handle, &keyVal, nil)

			guard deleteResult == MDB_SUCCESS else {
				throw LMDBError(returnCode: deleteResult)
			}

			if txn == nil {
				try tx.commit()
			}

			// Return the deleted object
			unmanagedExistingValue.release()
		}
	}
}
