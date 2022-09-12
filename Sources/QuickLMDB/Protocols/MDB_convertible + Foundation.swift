import CLMDB
import Foundation

///Any object that conforms to `ContiguousBytes` and declares ``MDB_encodable`` will automatically inherit this implementation.
extension ContiguousBytes where Self:MDB_encodable {
	public func asMDB_val<R>(_ valFunc:(inout MDB_val) throws -> R) rethrows -> R {
		return try withUnsafeBytes({ bytes in
			switch bytes.count {
				case 0:
					var mdb_val = MDB_val(mv_size:0, mv_data:UnsafeMutableRawPointer(mutating:nil))
					return try valFunc(&mdb_val)
				default:
					var mdb_val = MDB_val(mv_size:bytes.count, mv_data:UnsafeMutableRawPointer(mutating:bytes.baseAddress))
					return try valFunc(&mdb_val)
			}
		})
	}
}

///The `Data` struct directly conforms to the `MDB_convertible` protocol.
///Since the `MDB_encodable` functionality is already inherited through the `ContiguousBytes` extension, we only need to define the functions for `MDB_decodable`.
extension Data:MDB_convertible {
	public init?(_ value:MDB_val) {
		self = Data(bytes:value.mv_data, count:value.mv_size)
	}
}

///Any object that conforms to `LosslessStringConvertible` and declares `MDB_convertible` will automatically inherit this implementation.
///`LosslessStringConvertible` is the primary means that QuickLMDB uses to serialize and deserialize common language types (such as number and string types).
extension LosslessStringConvertible where Self:MDB_convertible {
	public init?(_ value:MDB_val) {
		let dataCopy = Data(bytes:value.mv_data, count:value.mv_size)
		guard let asString = String(data:dataCopy, encoding:.utf8), let asSelf = Self(asString) else {
			return nil
		}
		self = asSelf
	}
	public func asMDB_val<R>(_ valFunc:(inout MDB_val) throws -> R) rethrows -> R {
		return try description.data(using:.utf8)!.asMDB_val(valFunc)
	}
}

///Declare `MDB_convertible` for various **number** types that inherit from `LosslessStringConvertible`. The correct implementation will be automatically inherited for these types.
extension Bool:MDB_convertible {}
extension Double:MDB_convertible {}
extension Float:MDB_convertible {}
extension Int:MDB_convertible {}
extension Int8:MDB_convertible {}
extension Int16:MDB_convertible {}
extension Int32:MDB_convertible {}
extension Int64:MDB_convertible {}
extension UInt:MDB_convertible {}
extension UInt8:MDB_convertible {}
extension UInt16:MDB_convertible {}
extension UInt32:MDB_convertible {}
extension UInt64:MDB_convertible {}

///Declare `MDB_convertible` for various **string** types that inherit from `LosslessStringConvertible`. The correct implementation will be automatically inherited for these types.
extension String:MDB_convertible {}
extension Substring:MDB_convertible {}
extension Unicode.Scalar:MDB_convertible {}

extension Date:MDB_convertible {
	public init?(_ value:MDB_val) {
		guard let asTI = TimeInterval(value) else {
			return nil
		}
		self = Date(timeIntervalSinceReferenceDate:asTI)
	}
	public func asMDB_val<R>(_ valFunc:(inout MDB_val) throws -> R) rethrows -> R {
		return try timeIntervalSinceReferenceDate.asMDB_val(valFunc)
	}
}

///Any `Dictionary` that contains Key and Value types that conform to `Codable` is considered `MDB_convertible`
extension Dictionary:MDB_convertible where Key:Codable, Value:Codable {
	public init?(_ value:MDB_val) {
		do {
			self = try JSONDecoder().decode(Self.self, from:Data(bytes:value.mv_data, count:value.mv_size))
		} catch _ {
			return nil
		}
	}
	
	public func asMDB_val<R>(_ valFunc:(inout MDB_val) throws -> R) rethrows -> R {
		let encodedData = try! JSONEncoder().encode(self)
		return try encodedData.asMDB_val(valFunc)
	}
}

///Any `Array` that contains Element types that conform to `Codable` is considered `MDB_convertible`
extension Array:MDB_convertible where Element:Codable {
	public init?(_ value:MDB_val) {
		do {
			self = try JSONDecoder().decode(Self.self, from:Data(bytes:value.mv_data, count:value.mv_size))
		} catch _ {
			return nil
		}
	}
	
	public func asMDB_val<R>(_ valFunc:(inout MDB_val) throws -> R) rethrows -> R {
		let encodedData = try! JSONEncoder().encode(self)
		return try encodedData.asMDB_val(valFunc)
	}
}

///Any `Set` that contains Element types that conform to `Codable` is considered `MDB_convertible`
extension Set:MDB_convertible where Element:Codable {
	public init?(_ value:MDB_val) {
		do {
			self = try JSONDecoder().decode(Self.self, from:Data(bytes:value.mv_data, count:value.mv_size))
		} catch _ {
			return nil
		}
	}
		
	public func asMDB_val<R>(_ valFunc:(inout MDB_val) throws -> R) rethrows -> R {
		let encodedData = try! JSONEncoder().encode(self)
		return try encodedData.asMDB_val(valFunc)
	}
}
