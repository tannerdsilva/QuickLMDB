import RAW

/// a 24-byte blake2s digest over a contiguous range of key bytes.
///
/// fingerprints are the comparison unit of the reconcile walk: two ranges with
/// equal fingerprints are presumed in sync and skipped; a mismatch triggers a
/// split and recursion. the digest is computed over the raw key bytes in place,
/// never over a decoded representation.
@RAW_staticbuff(bytes: 24)
public struct Fingerprint:Sendable, Equatable {}
