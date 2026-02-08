import RAW

internal struct Boundary<UID:RAW_staticbuff>:Sendable {
	internal let length:UInt8
	internal let identifier:UID
	internal init(length:UInt8, identifier:UID) {
		self.length = length
		self.identifier = identifier
	}
}