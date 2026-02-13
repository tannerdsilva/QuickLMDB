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

internal struct BoundedPayload<IdentifierLengthType:RAW_encoded_fixedwidthinteger, IdentifierType:RAW_staticbuff, ModeType:RAW_encoded_fixedwidthinteger> {
	internal let boundary:Boundary<IdentifierLengthType, IdentifierType>
	internal let payloadMode:IdentifierType
	internal let payloadContent:UnsafeRawBufferPointer
}

//// fingerprint, idlist, skip should be expressed with this protocol
//public protocol CONCORD_payload_type:~Copyable, RAW_encodable {
//	associatedtype CONCORD_payload_kind_type:RAW_encoded_fixedwidthinteger
//	associatedtype CONCORD_payload_content_type:RAW_encodable
//	
//	static var CONCORD_payload_kind_value:CONCORD_payload_kind_type { get }
//	var CONCORD_payload_content:CONCORD_payload_content_type
//	init(CONCORD_payload_content:consuming CONCORD_payload_content)
//}
//
//public protocol CONCORD_payload_fingerprint_type:CONCORD_payload_type where CONCORD_payload_content_type == CONCORD_payload_fingerprint_hasher_impl.RAW_hasher_outputtype {
//	associatedtype CONCORD_payload_fingerprint_hasher_impl:RAW_hasher
//}
//
//
//extension MDB_cursor {
//	internal func splitRangeBuckets<UIDLengthValueType, UID, F>(elementCount:Int, nonzeroBucketCount buckets:Int, hasher:F.Type) throws where F:CONCORD_payload_fingerprint {
//		#if DEBUG
//		guard buckets > 0 else {
//			fatalError("\(#file):\(#line) buckets <= 0 is not allowed")
//		}
//		#endif
//		let idsPerBucket = elementCount / buckets
//		let bucketsWithExtra = elementCount % buckets
//			var curStrategy = BeginStrategy.opFirst
//			var i = 0
//			repeat {
//				let bucketSize = idsPerBucket + ((i < bucketsWithExtra) ? 1 : 0)
//				let ourFingerprint = try view(begin:curStrategy, steps:bucketSize).fingerprint(hasher:F.CONCORD_payload_fingerprint_hasher_impl.self)
//				let endCurBucket = try opGetCurrent(returning:(key:MDB_val, value:MDB_val).self).key
//				defer { 
//					switch i {
//						case 0:
//							curStrategy = .opGetCurrent
//							fallthrough
//						default:
//							i += 1
//					}
//				}
//				let curUpperBoundary:Boundary<UIDLengthValueType, UID>
//				do {
//					let startNextBucket = try cursor.opNext(returning:(key:MDB_val, value:MDB_val).self).key
//					curUpperBoundary = Boundary<UIDLengthValueType, UID>.minimalBound(prev:endCurrBucket, cur:startNextBucket)
//				} catch LMDBError.notFound {
//					curUpperBoundary = upperBound
//				}
//				write fingerprint flag
//				write fingerprint content
//			}
//		}
//	}
//}
//
//// MARK: Fingerprint Extensions
//extension MDB_cursor {
//
//}
