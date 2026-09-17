import RAW
import QuickLMDB
import concord

/// a 64-bit big-endian test key. mirrors the key types used across the
/// QuickLMDB test suite (`TestKey`/`DayKey`/`EventID`).
@RAW_staticbuff(bytes: 8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian: true)
@MDB_comparable
@frozen public struct TestID:Sendable, Hashable, Equatable, Comparable, ConcordKey {}

/// a 64-bit big-endian test value. `MDB_convertible` is satisfied through the
/// `RAW_staticbuff`-generated conformances, exactly as the existing
/// `TestValue` does in the QuickLMDB tests.
@RAW_staticbuff(bytes: 8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian: true)
@MDB_comparable
@frozen public struct TestValue:Sendable, Hashable, Equatable, Comparable {}
