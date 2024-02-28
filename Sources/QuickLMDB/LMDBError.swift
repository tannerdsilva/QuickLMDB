import CLMDB
import Foundation

public enum LMDBError:Error {

	//LMDB specific errors
	
	/// The key/value pair already exists.
	case keyExists
	
	/// The key/value pair was not found (EOF)
	case notFound
	
	/// Requested page not found - this usually indicates corruption.
	case pageNotFound
	
	/// Located page was wrong type.
	case corrupted
	
	/// Update of meta page failed or the environment had a fatal error.
	case panic
	
	/// Environment version mismatch.
	case versionMismatch
	
	/// File is not a valid LMDB file.
	case invalid
	
	/// Environment mapsize has been reached.
	case mapFull
	
	/// Environment maximum database count has been reached.
	case dbsFull
	
	/// Environment maximum reader count has been reached.
	case readersFull
	case tlsFull
	
	/// Transaction has too many dirty
	case txFull
	
	/// Cursor stack too deep - internal error
	case cursorFull
	
	/// Page does not have enough space - internal error
	case pageFull
	
	/// Database contents grew beyond environment mapsize.
	case mapResized
	
	/// Operation and database incompatible, or database type changed. This can mean...
	/// - The operation expects an ``QuickLMDB/Database/Flags/dupSort``/``QuickLMDB/Database/Flags/dupFixed`` database.
	/// - Opening a named database when the unnamed database has ``QuickLMDB/Database/Flags/dupSort`` / ``QuickLMDB/Database/Flags/integerKey``
	/// - Accessing a data entry as a database, or vice versa.
	/// - The database was dropped and recreated with different flags.
	case incompatible
	
	/// Invalid reuse of reader locktable slot
	case badReaderSlot
	
	/// Transaction must abort, has a child, or is invalid
	case badTransaction
	
	/// Unsupported size of the key/db name/data, or wrong ``QuickLMDB/Database/Flags/dupFixed`` size
	case badValueSize
	
	/// The specified database was changed unexpectedly
	case badDBI

	// OS specific errors
	case invalidParameter
	case outOfDiskSpace
	case outOfMemory
	case ioError
	case accessViolation
	
	// Unknown errors
	case other(returnCode:Int32)

	public init(returnCode:Int32) {
		switch returnCode {
			case MDB_KEYEXIST: self = .keyExists
			case MDB_NOTFOUND: self = .notFound
			case MDB_PAGE_NOTFOUND: self = .pageNotFound
			case MDB_CORRUPTED: self = .corrupted
			case MDB_PANIC: self = .panic
			case MDB_VERSION_MISMATCH: self = .versionMismatch
			case MDB_INVALID: self = .invalid
			case MDB_MAP_FULL: self = .mapFull
			case MDB_DBS_FULL: self = .dbsFull
			case MDB_READERS_FULL: self = .readersFull
			case MDB_TLS_FULL: self = .tlsFull
			case MDB_TXN_FULL: self = .txFull
			case MDB_CURSOR_FULL: self = .cursorFull
			case MDB_PAGE_FULL:  self = .pageFull
			case MDB_MAP_RESIZED: self = .mapResized
			case MDB_INCOMPATIBLE: self = .incompatible
			case MDB_BAD_RSLOT: self = .badReaderSlot
			case MDB_BAD_TXN: self = .badTransaction
			case MDB_BAD_VALSIZE: self = .badValueSize
			case MDB_BAD_DBI: self = .badDBI
			case EINVAL: self = .invalidParameter
			case ENOSPC: self = .outOfDiskSpace
			case ENOMEM: self = .outOfMemory
			case EIO: self = .ioError
			case EACCES: self = .accessViolation
			
			default: self = .other(returnCode:returnCode)
		}
	}
	
	public var returnCode:Int32 {
		get {
			switch self {
			case .keyExists:
				return MDB_KEYEXIST
			case .notFound:
				return MDB_NOTFOUND
			case .pageNotFound:
				return MDB_PAGE_NOTFOUND
			case .corrupted:
				return MDB_CORRUPTED
			case .panic:
				return MDB_PANIC
			case .versionMismatch:
				return MDB_VERSION_MISMATCH
			case .invalid:
				return MDB_INVALID
			case .mapFull:
				return MDB_MAP_FULL
			case .dbsFull:
				return MDB_DBS_FULL
			case .readersFull:
				return MDB_READERS_FULL
			case .tlsFull:
				return MDB_TLS_FULL
			case .txFull:
				return MDB_TXN_FULL
			case .cursorFull:
				return MDB_CURSOR_FULL
			case .pageFull:
				return MDB_PAGE_FULL
			case .mapResized:
				return MDB_MAP_RESIZED
			case .incompatible:
				return MDB_INCOMPATIBLE
			case .badReaderSlot:
				return MDB_BAD_RSLOT
			case .badTransaction:
				return MDB_BAD_TXN
			case .badValueSize:
				return MDB_BAD_VALSIZE
			case .badDBI:
				return MDB_BAD_DBI
			case .invalidParameter:
				return EINVAL
			case .outOfDiskSpace:
				return ENOSPC
			case .outOfMemory:
				return ENOMEM
			case .ioError:
				return EIO
			case .accessViolation:
				return EACCES
			case let .other(returnCode:rc):
				return rc
			}
		}
	}
		
	public var description:String {
		get {
			let strPtr = mdb_strerror(self.returnCode)!
			return String(cString:strPtr)
		}
	}
}
