import CLMDB

public typealias MDB_val = CLMDB.MDB_val
extension MDB_val:@unchecked Sendable {}

/// special options for this database. These flags are specified
extension Database {
	public struct Flags:OptionSet {
		public let rawValue:UInt32
		public init(rawValue:UInt32) { self.rawValue = rawValue }

		/// use reverse string keys
		public static let reverseKey = Flags(rawValue:UInt32(MDB_REVERSEKEY))
		
		/// use sorted duplicates
		public static let dupSort = Flags(rawValue:UInt32(MDB_DUPSORT))
		
		/// numeric keys in native byte order. The keys must all be of the same size.
		public static let integerKey = Flags(rawValue:UInt32(MDB_INTEGERKEY))
		
		/// duplicate items have a fixed size
		/// - use with ``dupSort``
		public static let dupFixed = Flags(rawValue:UInt32(MDB_DUPFIXED))
		
		/// duplicate item are integers (``integerKey`` for duplicate items)
		public static let integerDup = Flags(rawValue:UInt32(MDB_INTEGERDUP))
		
		/// use reverse string duplicate keys
		/// - use with ``QuickLMDB/Database``
		public static let reverseDup = Flags(rawValue:UInt32(MDB_REVERSEDUP))
		
		/// create the database if it does not already exist
		public static let create = Flags(rawValue:UInt32(MDB_CREATE))
	}
}


/// this is the complete toolset of operations that can be utilized to retrieve and navigate entries in the database.
public enum Operation {
	
	/// operation flags modify the way that entries are stored in the database. In LMDB documentation, these are known as "write flags".
	public struct Flags:OptionSet {
		
		/// the raw integer value for this flag. Can be passed directly into 
		public let rawValue:UInt32
		
		/// create a flag with its integer value.
		public init(rawValue:UInt32) {
			self.rawValue = rawValue
		}

		/// do not write the entry if the key already exists in the database. In this case, ``LMDBError/keyExists`` is thrown.
		public static let noOverwrite = Flags(rawValue:UInt32(MDB_NOOVERWRITE))
		
		/// only for use with ``Database/Flags/dupSort``
		/// - for ``Cursor/setEntry(value:forKey:flags:)``: don't write if the key and data pair already exist.
		/// - for ``Cursor/deleteEntry(flags:)``: remove all duplicate data items from the database.
		public static let noDupData = Flags(rawValue:UInt32(MDB_NODUPDATA))
		
		/// for ``Cursor/setEntry(value:forKey:flags:)``: overwrite the current key/value pair.
		public static let current = Flags(rawValue:UInt32(MDB_CURRENT))
		
		/// for ``Cursor/setEntry(value:forKey:flags:)``: just reserve space for the value, don't copy it. return a pointer to the reserved space.
		public static let reserve = Flags(rawValue:UInt32(MDB_RESERVE))
		
		/// pre-sorted keys are being stored in the database. don't split full pages.
		public static let append = Flags(rawValue:UInt32(MDB_APPEND))
		
		/// pre-sorted key/value entires are being stored in the database. don't split full pages.
		public static let appendDup = Flags(rawValue:UInt32(MDB_APPENDDUP))
		
		/// store multiple data items in one call. only for ``Database/Flags/dupFixed``.
		public static let multiple = Flags(rawValue:UInt32(MDB_MULTIPLE))
	}
	
	/// position at first key/data item.
	case first
	
	/// position at first data item of current key. Only use with ``Database/Flags/dupSort`` enabled.
	case firstDup
	
	/// position at key/data pair. Only use with ``Database/Flags/dupSort`` enabled.
	case getBoth
	
	/// position at key, nearest data. Only use with ``Database/Flags/dupSort`` enabled.
	case getBothRange
	
	/// return the key/value entry at the cursor's current position.
	case getCurrent
	
	/// return key and up to a page of duplicate data items from the current cursor position. Move cursor to prepare for ``Cursor/Operation/nextMultiple``.
	case getMultiple
	
	/// position at the last key/value item.
	case last
	
	/// position at the last data item of the current key.
	case lastDup
	
	/// position at the next data item.
	case next
	
	/// position at the next data item of the current key.
	case nextDup
	
	/// return key and up to a page of duplicate data items from next cursor position. Move cursor to prepare for the next ``Cursor/Operation/nextMultiple``.
	case nextMultiple
	
	/// position at first data item of the next key.
	case nextNoDup
	
	/// position at previous data item.
	case previous
	
	/// position at previous data item of current key. Only for ``Database/Flags/dupSort``.
	case previousDup
	
	/// position at lsat data item of previous key.
	case previousNoDup
	
	/// position at the specified key.
	/// - returned key will point to the same buffer that was passed into the cursor.
	case set
	
	/// position at the specified key.
	/// - returned key will point to the buffer that is stored in the memory map.
	case setKey
	
	/// position at the first key greater than or equal to specified key.
	case setRange
}

extension Operation {
	/// initialize an operation with a specified ``MDB_cursor_op``.
	public init(mdbValue:MDB_cursor_op) {
		switch mdbValue {
			case MDB_FIRST:
				self = .first
			case MDB_FIRST_DUP:
				self = .firstDup
			case MDB_GET_BOTH:
				self = .getBoth
			case MDB_GET_BOTH_RANGE:
				self = .getBothRange
			case MDB_GET_CURRENT:
				self = .getCurrent
			case MDB_GET_MULTIPLE:
				self = .getMultiple
			case MDB_LAST:
				self = .last
			case MDB_LAST_DUP:
				self = .lastDup
			case MDB_NEXT:
				self = .next
			case MDB_NEXT_DUP:
				self = .nextDup
			case MDB_NEXT_MULTIPLE:
				self = .nextMultiple
			case MDB_NEXT_NODUP:
				self = .nextNoDup
			case MDB_PREV:
				self = .previous
			case MDB_PREV_DUP:
				self = .previousDup
			case MDB_PREV_NODUP:
				self = .previousNoDup
			case MDB_SET:
				self = .set
			case MDB_SET_KEY:
				self = .setKey
			case MDB_SET_RANGE:
				self = .setRange
			default:
				self = .next
		}
	}
	
	/// retrieve the `MDB_cursor_op` value for this Operation.
	public var mdbValue:MDB_cursor_op {
		get {
			switch self {
				case .first:
					return MDB_FIRST
				case .firstDup:
					return MDB_FIRST_DUP
				case .getBoth:
					return MDB_GET_BOTH
				case .getBothRange:
					return MDB_GET_BOTH_RANGE
				case .getCurrent:
					return MDB_GET_CURRENT
				case .getMultiple:
					return MDB_GET_MULTIPLE
				case .last:
					return MDB_LAST
				case .lastDup:
					return MDB_LAST_DUP
				case .next:
					return MDB_NEXT
				case .nextDup:
					return MDB_NEXT_DUP
				case .nextMultiple:
					return MDB_NEXT_MULTIPLE
				case .nextNoDup:
					return MDB_NEXT_NODUP
				case .previous:
					return MDB_PREV
				case .previousDup:
					return MDB_PREV_DUP
				case .previousNoDup:
					return MDB_PREV_NODUP
				case .set:
					return MDB_SET
				case .setKey:
					return MDB_SET_KEY
				case .setRange:
					return MDB_SET_RANGE
			}
		}
	}
}