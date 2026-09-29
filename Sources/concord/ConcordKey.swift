import RAW
import QuickLMDB

/// the identifier type requirement for negentropy reconciliation.
///
/// a concord key is a fixed-size raw-byte buffer whose byte order defines the
/// stored row order via `MDB_compare_f`, which makes keys valid, total-order
/// bound identifiers for the reconciliation walk. keys are the only values the
/// reconcile phase inspects — fingerprints hash key bytes, sections delimit key
/// ranges, and idLists carry keys.
public protocol ConcordKey:RAW_staticbuff, MDB_comparable, Comparable, Hashable, Sendable {}
