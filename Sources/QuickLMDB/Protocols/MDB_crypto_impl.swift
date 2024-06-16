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
	public static let MDB_crypto_f:MDB_crypto_impl_ftype = { (a, b, c, e) -> Int32 in
		let keyParts = c!
		let ec = keyParts[0]
		let nonce = keyParts[1]
		let ad = keyParts[2]
		guard a!.pointee.mv_size > MemoryLayout<Tag>.size else {
			fatalError("chachapoly encryption impl cannot handle input data smaller than the tag size")
		}

		// gonna hash a bunch of inputs for better clarity
		var dataInputHasher:Hasher<B, [UInt8]>

		// figure out what is going on with the lengths of the pages and stuff
		let dataLength = a!.pointee.mv_size - MemoryLayout<Tag>.size
		
		let fcallID = UInt16.random(in:0..<UInt16.max)
		let shouldEncrypt = e == 1

		// determine what was passed as input
		let dataBufferInput = UnsafeMutableRawBufferPointer(start:a!.pointee.mv_data, count:(a!.pointee.mv_size - MemoryLayout<Tag>.size))
		let tagBufferInput = UnsafeMutableRawBufferPointer(start:a!.pointee.mv_data + dataLength, count:a!.pointee.mv_size - dataLength)
		// determine what was passed as output
		let dataBufferOutput = UnsafeMutableRawBufferPointer(start:b!.pointee.mv_data, count:b!.pointee.mv_size - MemoryLayout<Tag>.size)
		let tagBufferOutput = UnsafeMutableRawBufferPointer(start:b!.pointee.mv_data + dataLength, count:b!.pointee.mv_size - dataLength)
		
		var context = RAW_chachapoly.Context(key:UnsafeBufferPointer<UInt8>(start:ec.mv_data.assumingMemoryBound(to:UInt8.self), count:ec.mv_size))
		switch e == 1 {
			case true:
				// encode the data
				let endingTag:Tag
				do {
					endingTag = try context.encrypt(nonce:nonce.mv_data.load(as:Nonce.self), associatedData:UnsafeRawBufferPointer(start:ad.mv_data, count:ad.mv_size), inputData:dataBufferInput, output:b!.pointee.mv_data)
				} catch {
					return -1
				}
				
				// write the output
				endingTag.RAW_encode(dest:tagBufferOutput.baseAddress!.assumingMemoryBound(to:UInt8.self))
			case false:
				// load the existing tag and decrypt the data
				let endingTag:Tag = tagBufferInput.baseAddress!.load(as:Tag.self)
				do {
					try context.decrypt(tag:endingTag, nonce:nonce.mv_data.load(as:Nonce.self), associatedData:UnsafeRawBufferPointer(start:ad.mv_data, count:ad.mv_size), inputData:dataBufferInput, output:b!.pointee.mv_data)
				} catch {
					return -1
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
		// var blakeHasher = try! RAW_blake2.Hasher<B> 
		var newHasher:RAW_blake2.Hasher<B, UnsafeMutableRawPointer>
		switch c {
			case .some(let hashKey):
				newHasher = try! RAW_blake2.Hasher<B, UnsafeMutableRawPointer>(key:UnsafeBufferPointer(start:c!.pointee.mv_data.assumingMemoryBound(to:UInt8.self), count:c!.pointee.mv_size), outputLength:32)
			default:
				newHasher = try! RAW_blake2.Hasher<B, UnsafeMutableRawPointer>(outputLength:32)
		}
		try! newHasher.update(UnsafeBufferPointer(start:a!.pointee.mv_data.assumingMemoryBound(to:UInt8.self), count:a!.pointee.mv_size))
		try! newHasher.finish(into:b!.pointee.mv_data)
		b!.pointee.mv_size = 32
	}
}