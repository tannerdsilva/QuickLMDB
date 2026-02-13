import RAW
import QuickLMDB

/// used to express the kind of strategy that a cursor view instance should use to initiate the sequence 
public enum BeginStrategy {
	/// seek to the first value that is greater or equal to the specified MDB_val
	case opSetRange(MDB_val)
	/// return the current cursor position as the first step of the sequence
	case opGetCurrent
	/// return the "seek to first" operation as the first step of the sequence
	case opFirst
}