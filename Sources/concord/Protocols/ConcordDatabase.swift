import QuickLMDB
import RAW

/// a protocol used to express databases that can be automatically synced by way of a shared type of key.
public protocol ConcordDatabase:MDB_db_strict, Sendable where Self.MDB_db_key_type:IndexVector {}

extension Database.Strict where Self.MDB_db_key_type:IndexVector {}

extension MDB_cursor {
	internal func fingerprintShift<H>(begin:consuming MDB_val, bucketSize:Int, hasher:H.Type) throws -> H.RAW_hasher_outputtype where H:RAW_hasher {
		var hasher = try H()
		for (key, _) in countedStepView(begin:begin, steps:bucketSize) {
			try hasher.update(key.mv_data, count:key.mv_size)
		}
		var returnData = H.RAW_hasher_outputtype(RAW_staticbuff:H.RAW_hasher_outputtype.RAW_staticbuff_zeroed())
		try returnData.RAW_access_staticbuff_mutating { outputData in
			try hasher.finish(into:outputData)
		}
		return returnData
	}
}

extension MDB_cursor {
	public consuming func countedStepView(begin:consuming MDB_val, steps:Int) -> CountedStepView<Self> {
		return CountedStepView(cursor:self, begin:begin, steps:steps)
	}

	public consuming func openEndedView(begin:consuming MDB_val) -> OpenEndedView<Self> {
		return OpenEndedView(cursor:self, begin:begin)
	}
	
	public consuming func discreteRangeView(begin:consuming MDB_val, end:consuming MDB_val) -> DiscreteRangeView<Self> {
		return DiscreteRangeView(cursor:self, begin:begin, end:end)
	}
}

public struct CountedStepView<C>:Sequence where C:MDB_cursor {
	/// the type of cursor that will be used to step through the represented view.
	internal let cursor:C
	
	/// the beginning value that the view will start with.
	internal let begin:MDB_val
	
	/// the number of steps beyond the starting value that will be included in this view.
	internal let steps:Int
	
	internal init(cursor:consuming C, begin:consuming MDB_val, steps:Int) {
		self.cursor = cursor
		self.begin = begin
		self.steps = steps
	}
	
	public consuming func makeIterator() -> Iterator {
		return Iterator(cursor:cursor, begin:begin, steps:steps)
	}
	
	public struct Iterator:IteratorProtocol {
		/// the internal stage of stepping that the iterator is operating with
		internal enum Stage {
			case seek(first:MDB_val, totalSteps:Int)
			case stepsRemaining(Int)
			case eof
		}
		
		internal let cursor:C
		
		internal var stage:Stage
		
		internal init(cursor:consuming C, begin:consuming MDB_val, steps:Int) {
			self.cursor = cursor
			self.stage = .seek(first:begin, totalSteps:steps)
		}
		
		public mutating func next() -> (key:MDB_val, value:MDB_val)? {
			do {
				switch stage {
					case let .seek(first: firstVal, totalSteps: totalSteps):
						switch totalSteps {
							case 0:
								stage = .eof
								return nil
							case 1:
								stage = .eof
								return try cursor.opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:firstVal)
							case 2...Int.max:
								stage = .stepsRemaining(totalSteps - 1)
								return try cursor.opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:firstVal)
							default:
								fatalError("\(#file):\(#line)")
						}
					case let .stepsRemaining(remainingStepCount):
						switch remainingStepCount {
							case 0:
								fatalError("\(#file):\(#line)")
							case 1:
								stage = .eof
								return try cursor.opNext(returning:(key:MDB_val, value:MDB_val).self)
							case 2...Int.max:
								stage = .stepsRemaining(remainingStepCount - 1)
								return try cursor.opNext(returning:(key:MDB_val, value:MDB_val).self)
							default:
								fatalError("\(#file):\(#line)")
						}
					case .eof:
						return nil
				}
			} catch {
				stage = .eof
				return nil
			}
		}
	}
}

public struct OpenEndedView<C>:Sequence where C:MDB_cursor {
	/// the type of cursor that will be used to step through the represented view.
	internal let cursor:C
	
	/// the beginning value that the view will start with.
	internal let begin:MDB_val
	
	/// initialize an open ended cursor iterator with the specified cursor and beginning key
	internal init(cursor:consuming C, begin:consuming MDB_val) {
		self.cursor = cursor
		self.begin = begin
	}
	
	/// create a new iterator for the view.
	public consuming func makeIterator() -> Iterator {
		return Iterator(cursor:cursor, begin:begin)
	}
	
	/// an open ended iterator for seeking the contents of a database from a beginning value
	public struct Iterator:IteratorProtocol {
		/// the internal stage of stepping that the iterator is operating with
		internal enum Stage {
			case seekToFirst(MDB_val)
			case continueToEOF
			case eof
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
		public mutating func next() -> (key:MDB_val, value:MDB_val)? {
			do {
				switch stage {
					case .seekToFirst(let mdbValToSeek):
						stage = .continueToEOF
						return try cursor.opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:mdbValToSeek)
					case .continueToEOF:
						return try cursor.opNext(returning:(key:MDB_val, value:MDB_val).self)
					case .eof:
						return nil
				}
			} catch {
				stage = .eof
				return nil
			}
		}
	}
}


public struct DiscreteRangeView<C>:Sequence where C:MDB_cursor {
	/// the type of cursor that will be used to step through the represented view.
	internal let cursor:C
	
	/// the beginning value that the view will start with.
	internal let begin:MDB_val
	
	/// the end value that the view will terminate with.
	internal let end:MDB_val
	
	internal init(cursor:consuming C, begin:consuming MDB_val, end:consuming MDB_val) {
		self.cursor = cursor
		self.begin = begin
		self.end = end
	}
	
	public borrowing func makeIterator() -> Iterator {
		return Iterator(cursor:cursor, begin:begin, end:end)
	}
	
	public struct Iterator:IteratorProtocol {
		/// the internal stage of stepping that the iterator is operating with
		internal enum Stage {
			/// used to express the stage where the first item needs to be seek'd. the upper boundary is also stored on this stage
			case seekToFirst(MDB_val, MDB_val)
			/// used to express the stage where any n number of items are being stepped through until the upper boundary is crossed
			case seekUntilEnd(MDB_val)
			/// end of feed. nothing will ever be returned after this stage is set.
			case eof
		}
		
		internal let cursor:C
		
		internal var stage:Stage
		
		internal init(cursor:consuming C, begin:consuming MDB_val, end:consuming MDB_val) {
			self.cursor = cursor
			self.stage = .seekToFirst(begin, end)
		}
		
		public mutating func next() -> (key:MDB_val, value:MDB_val)? {
			do {
				let returnValue:(key:MDB_val, value:MDB_val)
				let upperBoundary:MDB_val
				switch stage {
					case .seekToFirst(let mdbValToSeek, let ub):
						stage = .seekUntilEnd(ub)
						upperBoundary = ub
						returnValue = try cursor.opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:mdbValToSeek)
					case .seekUntilEnd(let ub):
						upperBoundary = ub
						returnValue = try cursor.opNext(returning:(key:MDB_val, value:MDB_val).self)
					case .eof:
						return nil
				}
				guard cursor.compareEntryKeys(returnValue.key, upperBoundary) < 0 else {
					stage = .eof
					return nil
				}
				return returnValue
			} catch {
				stage = .eof
				return nil
			}
		}
	}
}