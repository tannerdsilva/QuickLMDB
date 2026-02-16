import RAW

public struct Boundary<IdentifierLengthType:RAW_encoded_fixedwidthinteger, IdentifierType:RAW_staticbuff>:Sendable {
	
	internal let length:IdentifierLengthType
	internal let identifier:IdentifierType
	
	internal init(length:consuming IdentifierLengthType, identifier:consuming IdentifierType) {
		self.length = length
		self.identifier = identifier
	}
	
	internal static func minimal(previous:UnsafeRawBufferPointer, current:UnsafeRawBufferPointer) -> Self {
		var sharedPrefixBytes:IdentifierLengthType.RAW_native_type = 0
		var returnKey = IdentifierType.RAW_comparable_fixed_theoretical_min()
		returnKey.RAW_access_mutating { retKey in
			copyLoop: for i in 0..<min(current.count, previous.count) {
				retKey[i] = current[i]
				sharedPrefixBytes += 1
				guard current[i] == previous[i] else {
					break copyLoop
				}
			}
		}
		return Self(length:IdentifierLengthType(RAW_native:sharedPrefixBytes), identifier:returnKey)
	}
	
	internal static func fullSizeMaximumValue() -> Self {
		return Self(length:IdentifierLengthType(RAW_native:IdentifierLengthType.RAW_native_type(MemoryLayout<IdentifierType.RAW_staticbuff_storetype>.size)), identifier:IdentifierType.RAW_comparable_fixed_theoretical_max())
	}
}

public struct BoundaryV2<IdentifierLengthType:RAW_encoded_fixedwidthinteger, IdentifierType:RAW_staticbuff>:~Copyable {

}
extension Boundary:RAW_encodable {
	public borrowing func RAW_encode(count:inout Int) {
		length.RAW_encode(count:&count)
		identifier.RAW_encode(count:&count)
	}
	
	public borrowing func RAW_encode(dest:UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8> {
		return identifier.RAW_encode(dest:length.RAW_encode(dest:dest))
	}
}