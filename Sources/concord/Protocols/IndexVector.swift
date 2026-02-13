import RAW
import QuickLMDB

@available(*, deprecated, message:"do not use")
public protocol IndexVector:RAW_staticbuff, RAW_comparable, MDB_comparable, Equatable, Comparable, Hashable {}