import RAW
import QuickLMDB
import struct CLMDB.MDB_val

extension MDB_cursor {
	public consuming func view(begin:consuming BeginStrategy, steps:Int) -> EnumeratedStepView<Self> {
		return EnumeratedStepView(cursor:self, begin:begin, steps:steps)
	}
}

/// a sequence that seeks to the first key that is greater or equal to the specified `begin` value and then returns `steps` number of values that proceed after seeking.
public struct EnumeratedStepView<C>:Sequence where C:MDB_cursor {
	
	/// the type of cursor that will be used to step through the represented view.
	internal let cursor:C
	
	/// the beginning value that the view will start with.
	internal let begin:BeginStrategy
	
	/// the number of steps beyond the starting value that will be included in this view.
	internal let steps:Int
	
	/// initialize an enumerated step view.
	internal init(cursor:consuming C, begin:consuming BeginStrategy, steps:consuming Int) {
		self.cursor = cursor
		self.begin = begin
		self.steps = steps
	}
	
	/// make the iterator for this sequence view.
	public consuming func makeIterator() -> Iterator {
		return Iterator(cursor:cursor, begin:begin, steps:steps)
	}
	
	/// the iterator type for this sequence view.
	public struct Iterator:IteratorProtocol {
		/// the internal stage of stepping that the iterator is operating with.
		internal enum Stage {
			/// the cursor needs to seek to the first value that is greater or equal to the first value, and return `totalSteps` number of values after seeking to this position.
			/// - NOTE: `totalSteps` may be zero
			case seek(first:BeginStrategy, totalSteps:Int)
			/// there are `n` number of steps remaining to return.
			/// - NOTE: `Int` value should never be `0` or anything less than.
			case stepsRemaining(Int)
			/// end of file. nothing shall be returned.
			case eof
		}
		
		/// the cursor that will be used for stepping and seeking.
		internal let cursor:C
		
		/// the internal stage of seek that this iterator instance is in.
		internal var stage:Stage
		
		/// initialize the iterator for the view.
		internal init(cursor:consuming C, begin:consuming BeginStrategy, steps:consuming Int) {
			self.cursor = cursor
			self.stage = .seek(first:begin, totalSteps:steps)
		}
		
		/// return the next step in the sequence.
		public mutating func next() -> (key:MDB_val, value:MDB_val)? {
			do {
				switch stage {
					case let .seek(first: seekStrategy, totalSteps: totalSteps):
						switch totalSteps {
							case 0:
								// no steps to take, eof immediately
								stage = .eof
								return nil
							case 1:
								// taking only step now, so all next calls will be eof
								stage = .eof
								switch seekStrategy {
									case let .opSetRange(mdbValToSeek):
										return try cursor.opSetRange(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).self, key:CLMDB.MDB_val(mutating:mdbValToSeek))
									case .opGetCurrent:
										return try cursor.opGetCurrent(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).self)
									case .opFirst:
										return try cursor.opFirst(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).self)
								}
							case 2...Int.max:
								// step ahead as usual
								stage = .stepsRemaining(totalSteps - 1)
								switch seekStrategy {
									case let .opSetRange(mdbValToSeek):
										return try cursor.opSetRange(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).self, key:CLMDB.MDB_val(mutating:mdbValToSeek))
									case .opGetCurrent:
										return try cursor.opGetCurrent(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).self)
									case .opFirst:
										return try cursor.opFirst(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).self)
								}
							default:
								fatalError("\(#file):\(#line)")
						}
					case let .stepsRemaining(remainingStepCount):
						switch remainingStepCount {
							case 0:
								fatalError("\(#file):\(#line)")
							case 1:
								stage = .eof
								return try cursor.opNext(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).self)
							case 2...Int.max:
								stage = .stepsRemaining(remainingStepCount - 1)
								return try cursor.opNext(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).self)
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
