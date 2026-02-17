import RAW
import QuickLMDB
import struct CLMDB.MDB_val

extension MDB_cursor {
	public consuming func view(begin:consuming BeginStrategy) -> OpenEndedView<Self> {
		return OpenEndedView(cursor:self, begin:begin)
	}
}

public struct OpenEndedView<C>:Sequence where C:MDB_cursor {
	/// the type of cursor that will be used to step through the represented view.
	internal let cursor:C
	
	/// the beginning value that the view will start with.
	internal let begin:BeginStrategy
	
	/// initialize an open ended cursor iterator with the specified cursor and beginning key
	internal init(cursor:consuming C, begin:consuming BeginStrategy) {
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
			case seekToFirst(BeginStrategy)
			case continueToEOF
			case eof
		}
		
		/// the underlying cursor that will be used to step through 
		internal let cursor:C
	
		internal var stage:Stage
	
		/// initialize an open ended cursor iterator with the specified cursor and beginning key
		internal init(cursor:consuming C, begin:consuming BeginStrategy) {
			self.cursor = cursor
			self.stage = .seekToFirst(begin)
		}
	
		/// get the next item from the iterator
		public mutating func next() -> (key:MDB_val, value:MDB_val)? {
			do {
				switch stage {
					case .seekToFirst(let seekStrategy):
						stage = .continueToEOF
						switch seekStrategy {
							case let .opSetRange(mdbValToSeek):
								return try cursor.opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:CLMDB.MDB_val(mutating:mdbValToSeek))
							case .opGetCurrent:
								return try cursor.opGetCurrent(returning:(key:MDB_val, value:MDB_val).self)
							case .opFirst:
								return try cursor.opFirst(returning:(key:MDB_val, value:MDB_val).self)
						}
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