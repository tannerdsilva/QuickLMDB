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
				let unmanagedExistingValue = Unmanaged<AnyObject>.fromOpaque(existingPointer)
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

	
	public func getObject<K: MDB_encodable, V: AnyObject>(type: V.Type, forKey key: K, tx: Transaction?) throws -> V? {
		return try key.asMDB_val { keyVal -> V? in
			var dataVal = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
			let valueResult: Int32
			if tx != nil {
				valueResult = mdb_get(tx!.txn_handle, db_handle, &keyVal, &dataVal)
			} else {
				valueResult = try Transaction.instantTransaction(environment: env_handle, readOnly: true, parent: nil) { someTrans in
					return mdb_get(someTrans.txn_handle, db_handle, &keyVal, &dataVal)
				}
			}
			guard valueResult == MDB_SUCCESS else {
				throw LMDBError(returnCode: valueResult)
			}

			guard dataVal.mv_size == MemoryLayout<UnsafeRawPointer>.stride else {
				return nil
			}

			let pointer = dataVal.mv_data.assumingMemoryBound(to: UnsafeRawPointer.self).pointee
			let unmanagedValue = Unmanaged<V>.fromOpaque(pointer)

			// Get the reference and increment the reference count
			let retainedValue = unmanagedValue.takeRetainedValue()
	
			// Retain the object again before returning it
			_ = Unmanaged.passUnretained(retainedValue).retain()
	
			return retainedValue
		}
	}

	public func deleteObject<K: MDB_encodable>(forKey key: K, tx: Transaction?) throws {
		return try key.asMDB_val { keyVal in
			var dataVal = MDB_val(mv_size: 0, mv_data: UnsafeMutableRawPointer(mutating: nil))
			let getResult: Int32

			if tx != nil {
				getResult = mdb_get(tx!.txn_handle, db_handle, &keyVal, &dataVal)
			} else {
				getResult = try Transaction.instantTransaction(environment: env_handle, readOnly: true, parent: nil) { someTrans in
					return mdb_get(someTrans.txn_handle, db_handle, &keyVal, &dataVal)
				}
			}

			guard getResult == MDB_SUCCESS else {
				throw LMDBError(returnCode: getResult)
			}

			guard dataVal.mv_size == MemoryLayout<UnsafeRawPointer>.stride else {
				return
			}

			let pointer = dataVal.mv_data.assumingMemoryBound(to: UnsafeRawPointer.self).pointee
			let unmanagedValue = Unmanaged<AnyObject>.fromOpaque(pointer)

			let deleteResult: Int32
			if tx != nil {
				deleteResult = mdb_del(tx!.txn_handle, db_handle, &keyVal, nil)
			} else {
				deleteResult = try Transaction.instantTransaction(environment: env_handle, readOnly: false, parent: nil) { someTrans in
					return mdb_del(someTrans.txn_handle, db_handle, &keyVal, nil)
				}
			}

			guard deleteResult == MDB_SUCCESS else {
				throw LMDBError(returnCode: deleteResult)
			}

			unmanagedValue.release()
		}
	}
}
