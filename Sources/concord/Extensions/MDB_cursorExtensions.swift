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
}

internal struct BoundedPayload<ReconciliationSetup:CONCORD_reconciliation_setup, PayloadContent:RAW_encodable>:RAW_encodable {
	internal let boundary:Boundary<ReconciliationSetup.CONCORD_rs_identifier_length_type, ReconciliationSetup.CONCORD_rs_identifier_type>
	internal let mode:ReconciliationSetup.CONCORD_reconciliation_mode_type
	internal let content:PayloadContent
	
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

public protocol CONCORD_encoding_transmitter {
	borrowing func transmit<E>(payload:consuming E) where E:RAW_encodable
}

extension MDB_cursor {
	internal func splitRangeList<ReconciliationSetup>(elementCount:Int, setup:ReconciliationSetup.Type) throws where ReconciliationSetup:CONCORD_reconciliation_setup {
	
	}
	internal func splitRangeBuckets<ReconciliationSetup>(elementCount:Int, nonzeroBucketCount buckets:Int, setup:ReconciliationSetup.Type) throws where ReconciliationSetup:CONCORD_reconciliation_setup {
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
			
		} while true
	}
}
