import RAW
import RAW_chachapoly
import RAW_blake2

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

public protocol MDB_crypto_impl {
	typealias MDB_crypto_impl_ftype = @convention(c)(UnsafePointer<MDB_val>?, UnsafeMutablePointer<MDB_val>?, UnsafePointer<MDB_val>?, Int32) -> Int32
	static var MDB_crypto_f:MDB_crypto_impl_ftype { get }
}

public struct ChaChaPoly:MDB_crypto_impl {
	public static let MDB_crypto_f:MDB_crypto_impl_ftype = { (a, b, c, d) -> Int32 in
		let keyParts = c!
		let ec = keyParts[0]
		let nonce = keyParts[1]
		let ad = keyParts[2]
		var context = RAW_chachapoly.Context(key:UnsafeBufferPointer<UInt8>(start:ec.mv_data.assumingMemoryBound(to:UInt8.self), count:ec.mv_size))
		switch d == 1 {
			case true:
				let endingTag:Tag
				do {
					endingTag = try context.encrypt(nonce:nonce.mv_data.load(as:Nonce.self), associatedData:UnsafeRawBufferPointer(start:ad.mv_data, count:ad.mv_size), inputData:UnsafeMutableRawBufferPointer(start:a!.pointee.mv_data, count:a!.pointee.mv_size), output:b!.pointee.mv_data)
				} catch {
					fatalError("NOT SUPPOSED TO HAPPEN")
				}
				endingTag.RAW_encode(dest:(b!.pointee.mv_data + a!.pointee.mv_size).assumingMemoryBound(to:UInt8.self))
				b!.pointee.mv_size = a!.pointee.mv_size + 16
			case false:
				guard a!.pointee.mv_size > 16 else {
					fatalError("FOO")
				}
				let dataBuffer = UnsafeMutableRawBufferPointer(start:a!.pointee.mv_data, count:(a!.pointee.mv_size - 16))
				let tagStart = a!.pointee.mv_data + (a!.pointee.mv_size - 16)
				let loadedTag = Tag(RAW_staticbuff:tagStart.assumingMemoryBound(to:UInt8.self))
				do {
					try context.decrypt(tag:loadedTag, nonce:nonce.mv_data.load(as:Nonce.self), associatedData:UnsafeRawBufferPointer(start:ad.mv_data, count:ad.mv_size), inputData:dataBuffer, output:b!.pointee.mv_data)
				} catch {
					fatalError("FUCK")
				}
		}
		return 0
	}
}

public protocol MDB_checksum_impl {
	typealias MDB_checksum_ftype = @convention(c)(UnsafePointer<MDB_val>?, UnsafeMutablePointer<MDB_val>?, UnsafePointer<MDB_val>?) -> Void
	static var MDB_sum_f:MDB_checksum_ftype { get }
}

public struct Blake2:MDB_checksum_impl {
	public static let MDB_sum_f:MDB_checksum_ftype = { (a, b, c) in
		var newHasher:RAW_blake2.Hasher<B, UnsafeMutableRawPointer>
		switch c {
			case .some(let hashKey):
				let keyBuffer = c!.pointee.mv_data.assumingMemoryBound(to:UInt8.self)
				newHasher = try! RAW_blake2.Hasher<B, UnsafeMutableRawPointer>(key:UnsafeBufferPointer(start:keyBuffer, count:c!.pointee.mv_size), outputLength:32)
			default:
				newHasher = try! RAW_blake2.Hasher<B, UnsafeMutableRawPointer>(outputLength:32)
		}
		try! newHasher.update(UnsafeBufferPointer(start:a!.pointee.mv_data.assumingMemoryBound(to:UInt8.self), count:a!.pointee.mv_size))
		try! newHasher.finish(into:b!)
	}
}