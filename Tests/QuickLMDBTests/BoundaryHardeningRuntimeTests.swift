import Testing
import Foundation
import QuickLMDB
import RAW

// runtime pins for the boundary-macro hardening that pricedb exposed:
// (1) generic boundary methods — the sibling must preserve the author's
//     generic parameters AND where-clause (they were dropped before, leaving
//     `P` unresolved in the sibling body);
// (2) inout parameters — the shell must re-prefix `&` when it forwards the
//     caller's storage into the sibling.

protocol PricedbProtocol {
	var tag: UInt64 { get }
}

@MDB_comparable
struct GenericKey: RAW_staticbuff, RAW_decodable, RAW_encodable, RAW_accessible_immutable, RAW_accessible_mutable, PricedbProtocol {
	typealias RAW_fixed_type = UInt64
	var RAW_staticbuff_value: RAW_fixed_type = 0
	init() {}
	init(tag: UInt64) { RAW_staticbuff_value = tag }
	init(RAW_staticbuff storetype: consuming RAW_fixed_type) { RAW_staticbuff_value = storetype }
	var tag: UInt64 { RAW_staticbuff_value }
	init?(RAW_decode buffer: UnsafeRawBufferPointer) {
		guard buffer.count == MemoryLayout<UInt64>.size else { return nil }
		self.init(RAW_staticbuff: buffer.loadUnaligned(as: UInt64.self))
	}
	func RAW_access_immutable<R, E>(_: UnsafeRawBufferPointer.Type, _ body: (UnsafeRawBufferPointer) throws(E) -> R) throws(E) -> R where E: Swift.Error {
		do {
			return try withUnsafeBytes(of: RAW_staticbuff_value) { try body($0) }
		} catch let error as E {
			throw error
		} catch {
			preconditionFailure("unexpected error type")
		}
	}
	mutating func RAW_access_mutable<R, E>(_: UnsafeMutableRawBufferPointer.Type, _ body: (UnsafeMutableRawBufferPointer) throws(E) -> R) throws(E) -> R where E: Swift.Error {
		do {
			return try withUnsafeMutableBytes(of: &RAW_staticbuff_value) { try body($0) }
		} catch let error as E {
			throw error
		} catch {
			preconditionFailure("unexpected error type")
		}
	}
	func RAW_encode(count: inout Int) { count += MemoryLayout<UInt64>.size }
	@discardableResult func RAW_encode(_: UnsafeMutableRawPointer.Type, destination: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
		withUnsafeBytes(of: RAW_staticbuff_value) { destination.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
		return destination + MemoryLayout<UInt64>.size
	}
	static func RAW_compare(lhs_data: UnsafeRawPointer, lhs_count: Int, rhs_data: UnsafeRawPointer, rhs_count: Int) -> Int32 {
		let l = lhs_data.loadUnaligned(as: UInt64.self), r = rhs_data.loadUnaligned(as: UInt64.self)
		return l < r ? -1 : (l > r ? 1 : 0)
	}
}

@MDB_environment(file: "generic-boundary.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
struct HardenedCore: Sendable {
	let env: Environment
	let primary: Database.Strict<GenericKey, TestValue>
}

extension HardenedCore {

	@MDB_transact(.readWrite)
	func install<P>(_ meta: P, key: GenericKey, _ value: TestValue) throws -> P where P: PricedbProtocol {
		try #store(HardenedCore.self, database: \.primary, key: key, value: value)
		return meta
	}

	@MDB_transact(.readOnly)
	func loadLogical() throws -> TestValue? {
		#load(HardenedCore.self, database: \.primary, key: GenericKey(tag: 9))
	}

	// the READ-ONLY generic boundary is the harder sibling merge —
	// `<P, M:TransactionMode>` — which pricedb's bulk loaders exercise
	// (`bulkLoadDirectPricesVX<P>`) but the suite had only pinned the
	// readWrite form (`<P>`). reads are generic over the mode, so writing
	// boundaries can join this one.
	@MDB_transact(.readOnly)
	func echoReadOnly<P>(_ meta: P, key: GenericKey) throws -> P where P: PricedbProtocol {
		_ = #load(HardenedCore.self, database: \.primary, key: key)
		return meta
	}

	@MDB_transact(.readWrite)
	func bump(_ counter: inout UInt64) throws {
		try #store(HardenedCore.self, database: \.primary, key: GenericKey(tag: counter + 1), value: TestValue(RAW_native: 1))
		counter += 1
	}
}

@Suite("boundary hardening — generic methods + inout params (pricedb exposure)")
struct BoundaryHardeningRuntimeTests {

	private func freshCore() throws -> HardenedCore {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-hardened-\(UUID().uuidString)", isDirectory: true)
		return try HardenedCore.open(at: dir.path)
	}

	@Test func genericBoundaryPreservesPAndTheWhereClause() throws {
		let core = try freshCore()
		let echo = try core.install(GenericKey(tag: 9), key: GenericKey(tag: 9), TestValue(RAW_native: 99))
		#expect(echo.tag == 9)
		#expect(try core.loadLogical() == TestValue(RAW_native: 99))
	}

	@Test func readOnlyGenericBoundaryMergesTheModeGeneric() throws {
		let core = try freshCore()
		// `<P, M:TransactionMode>` sibling (mode-generic read) — the shape
		// pricedb's bulk loaders depend on
		let echoed = try core.echoReadOnly(GenericKey(tag: 5), key: GenericKey(tag: 9))
		#expect(echoed.tag == 5)
	}

	@Test func inoutBoundaryThreadsTheAmpersand() throws {
		let core = try freshCore()
		var counter: UInt64 = 0
		try core.bump(&counter)
		#expect(counter == 1)
		try core.bump(&counter)
		#expect(counter == 2)
	}
}
