extension MDB_cursor where MDB_cursor_dbtype:MDB_db_strict {
	public func compareEntryValues(_ dataL:borrowing MDB_cursor_dbtype.MDB_db_key_type, _ dataR:consuming MDB_cursor_dbtype.MDB_db_val_type) -> Int32 {
		return dataL.MDB_access { lhsVal in
			return dataR.MDB_access { rhsVal in
				return compareEntryValues(lhsVal, rhsVal)
			}
		}
	}

	public func compareEntryKeys(_ dataL:borrowing MDB_cursor_dbtype.MDB_db_key_type, _ dataR:consuming MDB_cursor_dbtype.MDB_db_val_type) -> Int32 {
		return dataL.MDB_access { lhsVal in
			return dataR.MDB_access { rhsVal in
				return compareEntryKeys(lhsVal, rhsVal)
			}
		}
	}

	public func containsEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws -> Bool {
		return try key.MDB_access { keyVal in
			try containsEntry(key:keyVal)
		}
	}

	public func containsEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> Bool {
		return try key.MDB_access { keyVal in
			return try value.MDB_access { valueVal in
				try containsEntry(key:keyVal, value:valueVal)
			}
		}
	}

	public func setEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type, flags:Operation.Flags) throws {
		return try key.MDB_access { keyVal in
			try value.MDB_access { valueVal in
				try setEntry(key:keyVal, value:valueVal, flags:flags)
			}
		}
	}

	public func opSetRange(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		return try key.MDB_access { keyVal in
			let getVals = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:keyVal)
			return (key:MDB_cursor_dbtype.MDB_db_key_type(getVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(getVals.value)!)
		}
	}

	public func opSet(returning:MDB_cursor_dbtype.MDB_db_val_type.Type, key: MDB_cursor_dbtype.MDB_db_key_type) throws -> MDB_cursor_dbtype.MDB_db_val_type {
		return try key.MDB_access({ mdbKey in
			return MDB_cursor_dbtype.MDB_db_val_type(try opSet(returning:MDB_val.self, key:mdbKey))!
		})
	}

	public func opGetCurrent(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		let getVals = try opGetCurrent(returning:(key:MDB_val, value:MDB_val).self)
		return (key:MDB_cursor_dbtype.MDB_db_key_type(getVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(getVals.value)!)
	}

	public func opGetBoth(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		return try key.MDB_access { (mdbKey:consuming MDB_val) in
			return try value.MDB_access { (mdbVal:consuming MDB_val) in
				let rawVals = try opGetBoth(returning:(key:MDB_val, value:MDB_val).self, key:mdbKey, value:mdbVal)
				return (key:MDB_cursor_dbtype.MDB_db_key_type(rawVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(rawVals.value)!)
			}
		}
	}
	public func opPreviousNoDup(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		let getVals = try opPreviousNoDup(returning:(key:MDB_val, value:MDB_val).self)
		return (key:MDB_cursor_dbtype.MDB_db_key_type(getVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(getVals.value)!)
	}

	public func opPreviousDup(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		let getVals = try opPreviousDup(returning:(key:MDB_val, value:MDB_val).self)
		return (key:MDB_cursor_dbtype.MDB_db_key_type(getVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(getVals.value)!)
	}

	public func opPrevious(returning: (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		let getVals = try opPrevious(returning:(key:MDB_val, value:MDB_val).self)
		return (key:MDB_cursor_dbtype.MDB_db_key_type(getVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(getVals.value)!)
	}

	public func opNextNoDup(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		let getVals = try opNextNoDup(returning:(key:MDB_val, value:MDB_val).self)
		return (key:MDB_cursor_dbtype.MDB_db_key_type(getVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(getVals.value)!)
	}

	public func opGetBothRange(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		return try key.MDB_access { mdbKey in
			return try value.MDB_access { mdbVal in
				let rawVals = try opGetBothRange(returning:(key:MDB_val, value:MDB_val).self, key:mdbKey, value:mdbVal)
				return (key:MDB_cursor_dbtype.MDB_db_key_type(rawVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(rawVals.value)!)
			}
		}
	}

	public func opNextDup(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		let getVals = try opNextDup(returning:(key:MDB_val, value:MDB_val).self)
		return (key:MDB_cursor_dbtype.MDB_db_key_type(getVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(getVals.value)!)
	}

	public func opNext(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		let getVals = try opNext(returning:(key:MDB_val, value:MDB_val).self)
		return (key:MDB_cursor_dbtype.MDB_db_key_type(getVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(getVals.value)!)
	}

	public func opLastDup(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		let getVals = try opLastDup(returning:(key:MDB_val, value:MDB_val).self)
		return (key:MDB_cursor_dbtype.MDB_db_key_type(getVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(getVals.value)!)
	}

	public func opLast(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		let getVals = try opLast(returning:(key:MDB_val, value:MDB_val).self)
		return (key:MDB_cursor_dbtype.MDB_db_key_type(getVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(getVals.value)!)
	}


	public func opFirstDup(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		let getVals = try opFirstDup(returning:(key:MDB_val, value:MDB_val).self)
		return (key:MDB_cursor_dbtype.MDB_db_key_type(getVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(getVals.value)!)
	}

	public func opFirst(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
		let getVals = try opFirst(returning:(key:MDB_val, value:MDB_val).self)
		return (key:MDB_cursor_dbtype.MDB_db_key_type(getVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(getVals.value)!)
	}

	
	public func opSetKey(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:consuming MDB_cursor_dbtype.MDB_db_key_type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
		return try key.MDB_access({ mdbKey in
			let rawVals = try opSetKey(returning:(key:MDB_val, value:MDB_val).self, key:mdbKey)
			return (key:MDB_cursor_dbtype.MDB_db_key_type(rawVals.key)!, value:MDB_cursor_dbtype.MDB_db_val_type(rawVals.value)!)
		})
	}
}