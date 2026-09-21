import CLMDB
import RAW
import RAW_chachapoly
import RAW_blake2

// the encryption/checksum provider surface for LMDB 1.0 environments.
//
// LMDB 1.0 supports authenticated per-page encryption and optional per-page
// checksums. both are supplied as C callbacks the engine invokes during page
// reads and writes — the `MDB_enc_func` and `MDB_sum_func` function types,
// registered on the environment with `mdb_env_set_encrypt` and
// `mdb_env_set_checksum`. these protocols lift those C callbacks into typed
// Swift conformances a consumer can declare on their environment type.

/// a provider of LMDB 1.0 authenticated per-page encryption. conforming
/// types supply a C-compatible callback that encrypts and decrypts page data
/// with the engine-provided key material.
public protocol MDB_crypto_impl {
	/// the C function type LMDB calls for every page-level encrypt/decrypt.
	typealias MDB_crypto_impl_ftype = @convention(c) (
		UnsafePointer<MDB_val>?,
		UnsafeMutablePointer<MDB_val>?,
		UnsafePointer<MDB_val>?,
		Int32
	) -> Int32
	/// the per-page authentication data size (in bytes) this implementation appends to
	/// every encrypted page. LMDB reserves this much of each page for the auth tag.
	static var MDB_esumsize: UInt32 { get }
	/// the encrypt/decrypt callback, in the exact shape of `MDB_enc_func`. called
	/// with `(src, dst, keyParts, encdec)` where `src` is the page data, `dst` the
	/// output buffer, `keyParts` points to the 3-part key array (`[0]` = cipher key,
	/// `[1]` = nonce, `[2]` = auth tag), and `encdec` is `1` for encrypt, `0` for
	/// decrypt. return `0` on success, non-zero on failure.
	static var MDB_crypto_f: MDB_crypto_impl_ftype { get }
}

/// a ChaCha20-Poly1305 authenticated-encryption provider backed by rawdog's
/// `RAW_chachapoly`. the cipher key is any 16- or 32-byte value; the engine's
/// per-page nonce (page number + txn id) and auth tag ride in the key array.
public struct ChaChaPoly: MDB_crypto_impl {
	public static let MDB_esumsize: UInt32 = UInt32(MemoryLayout<Tag>.size)
	public static let MDB_crypto_f: MDB_crypto_impl_ftype = { (src, dst, keyParts, encdec) in
		guard let src, let dst, let keyParts else {
			return -1
		}
		let keyDat = keyParts[0]
		let nonceDat = keyParts[1]
		let tagDat = keyParts[2]
		guard src.pointee.mv_size > MemoryLayout<Tag>.size else {
			return -1
		}
		guard let keyBuf = keyDat.mv_data, let srcBuf = src.pointee.mv_data, let dstBuf = dst.pointee.mv_data else {
			return -1
		}
		guard let noncePtr = nonceDat.mv_data, let tagPtr = tagDat.mv_data else {
			return -1
		}
		// a bad key length (not 16/32) makes the context initializer return nil — fail
		// the C call rather than trap.
		guard var ctx = RAW_chachapoly.Context(key: UnsafeRawBufferPointer(start: keyBuf.assumingMemoryBound(to: UInt8.self), count: keyDat.mv_size)) else {
			return -1
		}
		let input = UnsafeRawBufferPointer(start: srcBuf, count: src.pointee.mv_size)
		let output = dstBuf
		do {
			switch encdec {
				case 1: // encrypt
					try ctx.encrypt(nonce: noncePtr, associatedData: UnsafeRawBufferPointer(start: nil, count: 0), inputData: input, output: output, tag: tagPtr)
					return 0
				case 0: // decrypt
					try ctx.decrypt(tag: tagPtr, nonce: noncePtr, associatedData: UnsafeRawBufferPointer(start: nil, count: 0), inputData: input, output: output)
					return 0
				default:
					return -1
			}
		} catch {
			return -1
		}
	}
}

/// a provider of LMDB 1.0 per-page checksums. conforming types supply a
/// C-compatible callback that hashes page data into the engine-provided
/// output buffer.
public protocol MDB_checksum_impl {
	/// the C function type LMDB calls to compute a page checksum.
	typealias MDB_checksum_ftype = @convention(c) (
		UnsafePointer<MDB_val>?,
		UnsafeMutablePointer<MDB_val>?,
		UnsafePointer<MDB_val>?
	) -> Void
	/// the per-page checksum size (in bytes) this implementation produces.
	/// LMDB reserves this much of each page for the checksum.
	static var MDB_sumsize: UInt32 { get }
	/// the checksum callback, in the exact shape of `MDB_sum_func`. called with
	/// `(src, dst, key)` where `src` is the page data, `dst` the output buffer, and
	/// `key` the cipher key when the environment is encrypted (nil otherwise).
	static var MDB_sum_f: MDB_checksum_ftype { get }
}

/// a BLAKE2b checksum provider backed by rawdog's `RAW_blake2`, producing an
/// 8-byte keyed (or keyless) digest per page.
public struct Blake2: MDB_checksum_impl {
	public static let outputLength = 8
	public static let MDB_sumsize: UInt32 = UInt32(outputLength)
	public static let MDB_sum_f: MDB_checksum_ftype = { (src, dst, key) in
		guard let src, let dst, let srcBuf = src.pointee.mv_data, let dstBuf = dst.pointee.mv_data else {
			return
		}
		do {
			var hasher: RAW_blake2.Hasher<RAW_blake2.B, [UInt8]>
			if let key = key?.pointee, let keyBuf = key.mv_data {
				hasher = try RAW_blake2.Hasher<RAW_blake2.B, [UInt8]>(key: UnsafeRawPointer(keyBuf), count: key.mv_size, outputLength: outputLength)
			} else {
				hasher = try RAW_blake2.Hasher<RAW_blake2.B, [UInt8]>(outputLength: outputLength)
			}
			try hasher.update(UnsafeRawBufferPointer(start: srcBuf, count: src.pointee.mv_size))
			let result = try hasher.finish()
			result.withUnsafeBytes { srcRaw in
				dstBuf.copyMemory(from: srcRaw.baseAddress!, byteCount: srcRaw.count)
			}
			dst.pointee.mv_size = outputLength
		} catch {
			return
		}
	}
}
