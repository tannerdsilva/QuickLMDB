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

internal protocol CONCORD_mode_type:RAW_encoded_fixedwidthinteger, ExpressibleByIntegerLiteral {
	static var CONCORD_payload_mode_skip:Self { get }
	static var CONCORD_payload_mode_fingerprint:Self { get }
	static var CONCORD_payload_mode_list:Self { get }
}

internal protocol CONCORD_reconciliation_setup {
	associatedtype CONCORD_identifier_length_type:RAW_encoded_fixedwidthinteger
	associatedtype CONCORD_identifier_type:RAW_staticbuff
	associatedtype CONCORD_fingerprint_hashing_impl:RAW_hasher
	associatedtype CONCORD_reconciliation_mode_type:CONCORD_mode_type
}

internal struct BoundedPayload<IdentifierLengthType:CONCORD_mode_type, IdentifierType:RAW_staticbuff, ModeType:CONCORD_mode_type>:~Copyable {
	internal let boundary:Boundary<IdentifierLengthType, IdentifierType>
	internal let payloadMode:IdentifierType
	internal let payloadContent:UnsafeRawBufferPointer
	internal init(boundary:consuming Boundary<IdentifierLengthType, IdentifierType>, payloadMode:consuming IdentifierType, payloadContent:UnsafeRawBufferPointer) {
		self.boundary = boundary
		self.payloadMode = payloadMode
		self.payloadContent = payloadContent
	}
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
			let curUpperBoundary:Boundary<ReconciliationSetup.CONCORD_identifier_length_type, ReconciliationSetup.CONCORD_identifier_type>
			do {
				let startNextBucket = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
				curUpperBoundary = Boundary<ReconciliationSetup.CONCORD_identifier_length_type, ReconciliationSetup.CONCORD_identifier_type>.minimal(previous:UnsafeRawBufferPointer(endCurBucket), current:UnsafeRawBufferPointer(startNextBucket))
			} catch LMDBError.notFound {
				#if DEBUG
				guard i == (buckets - 1) else {
					fatalError("\(#file):\(#line)")
				}
				#endif
				let uidLength = ReconciliationSetup.CONCORD_identifier_length_type(RAW_native:ReconciliationSetup.CONCORD_identifier_length_type.RAW_native_type(MemoryLayout<ReconciliationSetup.CONCORD_identifier_type.RAW_staticbuff_storetype>.size))
				curUpperBoundary = Boundary<ReconciliationSetup.CONCORD_identifier_length_type, ReconciliationSetup.CONCORD_identifier_type>(length:uidLength, identifier:ReconciliationSetup.CONCORD_identifier_type.RAW_comparable_fixed_theoretical_max())
			}

		} while true
	}
}
//
//// MARK: Fingerprint Extensions
//extension MDB_cursor {
//
//}
