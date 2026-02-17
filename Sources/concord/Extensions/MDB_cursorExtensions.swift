import RAW
import QuickLMDB

//public protocol CONCORD_bounded_payload_type<CONCORD_payload_bounded_content_type>:~Copyable {
////	associatedtype CONCORD_bounded_payload_content_type:CONCORD_payload_type
////	associatedtype UID:RAW_staticbuff
////	associatedtype UIDLengthValueType:RAW_encoded_fixedwidthinteger
////	associatedtype CONCORD_payload_kind_type:RAW_encoded_fixedwidthinteger
////	
////	var boundary:Boundary<UIDLengthValueType, UID> { get }
////	var kind:PayloadKindValueType { get }
////	var content:PayloadContentType { get }
////	init(bound:Boundary<UIDLengthValueType, UID>)
//}

internal protocol CONCORD_payload_mode_type:RAW_encoded_fixedwidthinteger, ExpressibleByIntegerLiteral {
	/// the mode value that is used to signal a fingerprint payload
	static var CONCORD_payload_mode_fingerprint:Self { get }
	/// the mode value that is used to signal a id list payload
	static var CONCORD_payload_mode_list:Self { get }
	/// the mode value that is used to signal a skip payload
	static var CONCORD_payload_mode_skip:Self { get }
}

internal protocol CONCORD_reconciliation_setup {
	/// the type that shall be used to express the length of a bounded UID
	associatedtype CONCORD_rs_identifier_length_type:RAW_encoded_fixedwidthinteger
	associatedtype CONCORD_rs_identifier_type:RAW_staticbuff
	associatedtype CONCORD_fingerprint_hashing_impl:RAW_hasher
	associatedtype CONCORD_reconciliation_mode_type:CONCORD_payload_mode_type
	associatedtype CONCORD_rs_idlist_count_type:RAW_encoded_fixedwidthinteger
}

internal struct BoundedPayload<ReconciliationSetup:CONCORD_reconciliation_setup, PayloadContent:RAW_encodable>:RAW_encodable {
	internal let boundary:Boundary<ReconciliationSetup.CONCORD_rs_identifier_length_type, ReconciliationSetup.CONCORD_rs_identifier_type>
	internal let mode:ReconciliationSetup.CONCORD_reconciliation_mode_type
	internal let content:PayloadContent
	
	internal init(boundary:Boundary<ReconciliationSetup.CONCORD_rs_identifier_length_type, ReconciliationSetup.CONCORD_rs_identifier_type>, mode:ReconciliationSetup.CONCORD_reconciliation_mode_type, content:PayloadContent) {
		self.boundary = boundary
		self.mode = mode
		self.content = content
	}
	
	internal borrowing func RAW_encode(count:inout Int) {
		boundary.RAW_encode(count:&count)
		mode.RAW_encode(count:&count)
		content.RAW_encode(count:&count)
	}
	
	internal borrowing func RAW_encode(dest:UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8> {
		var seeker = boundary.RAW_encode(dest:dest)
		seeker = mode.RAW_encode(dest:seeker)
		return content.RAW_encode(dest:seeker)
	}
}

internal struct IncrementalIDListPayload<ReconciliationSetup:CONCORD_reconciliation_setup>:RAW_encodable {
	/// the identifiers that are being listed
	private var identifiers:Array<MDB_val> = []
	/// stores an identifier to be encoded
	fileprivate mutating func storeIdentifier(_ idValue:consuming MDB_val) {
		identifiers.append(idValue)
	}
	
	internal borrowing func RAW_encode(count:inout Int) {
		count += MemoryLayout<ReconciliationSetup.CONCORD_rs_idlist_count_type.RAW_staticbuff_storetype>.size
		for curID in identifiers {
			count += curID.mv_size
		}
	}
	internal borrowing func RAW_encode(dest:UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8> {
		// encode the count as the `ReconciliationSetup.CONCORD_rs_idlist_count_type`
		var seeker = ReconciliationSetup.CONCORD_rs_idlist_count_type(RAW_native:ReconciliationSetup.CONCORD_rs_idlist_count_type.RAW_native_type(identifiers.count)).RAW_encode(dest:dest)
		for curVal in identifiers {
			guard RAW_memcpy(seeker, curVal.mv_data, curVal.mv_size)! == seeker else {
				fatalError("\(#file):\(#line)")
			}
			seeker += curVal.mv_size
		}
		return seeker
	}
}


public protocol CONCORD_encoding_transmitter:~Copyable {
	mutating func transmit<E>(payload:UnsafePointer<E>) throws where E:RAW_encodable
}

extension MDB_cursor {
	internal func splitRangeListRoot<ReconciliationSetup>(transmitter:inout CONCORD_encoding_transmitter, setup:ReconciliationSetup.Type) throws where ReconciliationSetup:CONCORD_reconciliation_setup {
		var incrementalIDList = IncrementalIDListPayload<ReconciliationSetup>()
		for (id, _) in view(begin:.opFirst) {
			incrementalIDList.storeIdentifier(id)
		}
		try withUnsafePointer(to:BoundedPayload<ReconciliationSetup, IncrementalIDListPayload<ReconciliationSetup>>(boundary:.fullSizeMaximumValue(), mode:ReconciliationSetup.CONCORD_reconciliation_mode_type.CONCORD_payload_mode_list, content:incrementalIDList)) { payloadPtr in
			try transmitter.transmit(payload:payloadPtr)
		}
	}

	internal func splitRangeBucketsRoot<ReconciliationSetup>(elementCount:Int, nonzeroBucketCount buckets:Int, transmitter:inout CONCORD_encoding_transmitter, setup:ReconciliationSetup.Type) throws where ReconciliationSetup:CONCORD_reconciliation_setup {
		#if DEBUG
		guard buckets > 0 else {
			fatalError("\(#file):\(#line) buckets <= 0 is not allowed")
		}
		#endif
		let idsPerBucket = elementCount / buckets
		let bucketsWithExtra = elementCount % buckets
		var curStrategy = BeginStrategy.opFirst
		var i = 0
		repeat {
			let bucketSize = idsPerBucket + ((i < bucketsWithExtra) ? 1 : 0)
			let ourFingerprint = try view(begin:curStrategy, steps:bucketSize).fingerprint(hasher:ReconciliationSetup.CONCORD_fingerprint_hashing_impl.self)
			let endCurBucket = try opGetCurrent(returning:(key:MDB_val, value:MDB_val).self).key
			defer { 
				switch i {
					case 0:
						curStrategy = .opGetCurrent
						fallthrough
					default:
						i += 1
				}
			}
			let curUpperBoundary:Boundary<ReconciliationSetup.CONCORD_rs_identifier_length_type, ReconciliationSetup.CONCORD_rs_identifier_type>
			do {
				let startNextBucket = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
				curUpperBoundary = .minimal(previous:UnsafeRawBufferPointer(endCurBucket), current:UnsafeRawBufferPointer(startNextBucket))
			} catch LMDBError.notFound {
				#if DEBUG
				guard i == (buckets - 1) else {
					fatalError("\(#file):\(#line)")
				}
				#endif
				curUpperBoundary = .fullSizeMaximumValue()
			}
			try withUnsafePointer(to:BoundedPayload<ReconciliationSetup, ReconciliationSetup.CONCORD_fingerprint_hashing_impl.RAW_hasher_outputtype>(boundary:curUpperBoundary, mode:ReconciliationSetup.CONCORD_reconciliation_mode_type.CONCORD_payload_mode_fingerprint, content:ourFingerprint)) { payloadPtr in
				try transmitter.transmit(payload:payloadPtr)
			}
		} while true
	}
}


extension MDB_cursor {
	// return first key such that:
	// begin ≤ k < end   &&   k ≥ value
//	internal borrowing func findLowerBound<ReconciliationSetup>(begin:CONCORD_reconciliation_setup.CONCORD_rs_identifier_type, end:MDB_val, value:MDB_val, setup:ReconciliationSetup.Type) throws -> Void where ReconciliationSetup:CONCORD_reconciliation_setup {
//		
//	}
}
