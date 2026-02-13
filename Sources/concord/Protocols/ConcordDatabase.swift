import QuickLMDB
import RAW

/// a protocol used to express databases that can be automatically synced by way of a shared type of key.
@available(*, deprecated, message:"do not use")
public protocol ConcordDatabase:MDB_db_strict, Sendable where Self.MDB_db_key_type:IndexVector {}