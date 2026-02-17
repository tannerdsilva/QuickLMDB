import RAW
import QuickLMDB
import struct CLMDB.MDB_val

extension MDB_cursor {
	public consuming func view(begin:consuming BeginStrategy, end:consuming UnsafeRawBufferPointer) -> DiscreteRangeView<Self> {
		return DiscreteRangeView(cursor:self, begin:begin, end:end)
	}
}

public struct DiscreteRangeView<C>:Sequence where C:MDB_cursor {
	/// the type of cursor that will be used to step through the represented view.
	internal let cursor:C
	
	/// the beginning value that the view will start with.
	internal let begin:BeginStrategy
	
	/// the end value that the view will terminate with.
	internal let end:UnsafeRawBufferPointer
	
	internal init(cursor:consuming C, begin:consuming BeginStrategy, end:consuming UnsafeRawBufferPointer) {
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
			case seekToFirst(BeginStrategy, UnsafeRawBufferPointer)
			/// used to express the stage where any n number of items are being stepped through until the upper boundary is crossed
			case seekUntilEnd(UnsafeRawBufferPointer)
			/// end of feed. nothing will ever be returned after this stage is set.
			case eof
		}
		
		internal let cursor:C
		
		internal var stage:Stage
		
		internal init(cursor:consuming C, begin:consuming BeginStrategy, end:consuming UnsafeRawBufferPointer) {
			self.cursor = cursor
			self.stage = .seekToFirst(begin, end)
		}
		
		public mutating func next() -> (key:MDB_val, value:MDB_val)? {
			do {
				let returnValue:(key:MDB_val, value:MDB_val)
				let upperBoundary:MDB_val
				switch stage {
					case let .seekToFirst(seekStrategy, ub):
						stage = .seekUntilEnd(ub)
						upperBoundary = ub.MDB_val()
						switch seekStrategy {
							case let .opSetRange(mdbValToSeek):
								returnValue = try cursor.opSetRange(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).self, key:mdbValToSeek.MDB_val())
							case .opGetCurrent:
								returnValue = try cursor.opGetCurrent(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).self)
							case .opFirst:
								returnValue = try cursor.opFirst(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).self)
						}
					case .seekUntilEnd(let ub):
						upperBoundary = ub.MDB_val()
						returnValue = try cursor.opNext(returning:(key:CLMDB.MDB_val, value:CLMDB.MDB_val).self)
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