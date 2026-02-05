import QuickLMDB

/// a protocol used to express databases that can be automatically synced by way of a shared type of key.
public protocol ConcordDatabase:MDB_db_strict, Sendable where Self.MDB_db_key_type:IndexVector {}

extension Database.Strict where Self.MDB_db_key_type:IndexVector {}

/// an open ended iterator for seeking the contents of a database from a beginning value
public struct OpenEndedIterator<C>:IteratorProtocol where C:MDB_cursor {
	/// the internal stage of stepping that the iterator is operating with
	internal enum Stage {
		case seekToFirst(MDB_val)
		case continueToEOF
	}
	
	/// the underlying cursor that will be used to step through 
	internal let cursor:C

	internal var stage:Stage

	/// initialize an open ended cursor iterator with the specified cursor and beginning key
	internal init(cursor:consuming C, begin:consuming MDB_val) {
		self.cursor = cursor
		self.stage = .seekToFirst(begin)
	}

	/// get the next item from the iterator
	public mutating func next() -> MDB_val? {
		do {
			switch stage {
				case .seekToFirst(let mdbValToSeek):
					stage = .continueToEOF
					return try cursor.opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:mdbValToSeek).key
				case .continueToEOF:
					return try cursor.opNext(returning:(key:MDB_val, value:MDB_val).self).key
			}
		} catch {
			return nil
		}
	}
}

public struct DiscreteRangeIterator<C>:IteratorProtocol where C:MDB_cursor {
	/// the internal stage of stepping that the iterator is operating with
	internal enum Stage {
		/// used to express the stage where the first item needs to be seek'd. the upper boundary is also stored on this stage
		case seekToFirst(MDB_val, MDB_val)
		/// used to express the stage where any n number of items are being stepped through until the upper boundary is crossed
		case seekUntilEnd(MDB_val)
	}
	
	internal let cursor:C
	
	internal var stage:Stage
	
	internal init(cursor:consuming C, begin:consuming MDB_val, end:consuming MDB_val) {
		self.cursor = cursor
		self.stage = .seekToFirst(begin, end)
	}
	
	public mutating func next() -> MDB_val? {
		do {
			let returnValue:MDB_val
			let upperBoundary:MDB_val
			switch stage {
				case .seekToFirst(let mdbValToSeek, let ub):
					stage = .seekUntilEnd(ub)
					upperBoundary = ub
					returnValue = try cursor.opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:mdbValToSeek).key
				case .seekUntilEnd(let ub):
					upperBoundary = ub
					returnValue = try cursor.opNext(returning:(key:MDB_val, value:MDB_val).self).key
			}
			guard cursor.compareEntryKeys(returnValue, upperBoundary) < 0 else {
				return nil
			}
			return returnValue
		} catch {
			return nil
		}
	}
}