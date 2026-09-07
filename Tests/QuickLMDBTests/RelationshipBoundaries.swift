import Testing
import Foundation
import QuickLMDB

// shared test utilities for the runtime suites.

enum TestHelpers {
	@available(*, noasync)
	static func tempDirPath() throws -> String {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-tests-\(UUID().uuidString)", isDirectory:true)
		try FileManager.default.createDirectory(at:dir, withIntermediateDirectories:true)
		return dir.path
	}

	@available(*, noasync)
	static func makeCore() throws -> TestCore {
		return try TestCore.open(at: TestHelpers.tempDirPath())
	}
}

// - MARK: relationship-policy boundaries
// sibling reads/sibling writes are engine defaults; the macro opens top-level
// transactions of the requested mode. these boundaries exercise those relationships.

extension TestCore {

	@MDB_transact(.readOnly)
	public func innerRead(_ key: borrowing TestKey) throws -> TestValue? {
		return try? primary.loadEntry(key: key, as: TestValue.self)
	}

	@MDB_transact(.readOnly)
	public func outerReadThenInnerRead(_ key: borrowing TestKey) throws -> TestValue? {
		return try innerRead(key)
	}

	@MDB_transact(.readWrite)
	public func touchWrite(_ key: borrowing TestKey, _ value: consuming TestValue) throws {
		try primary.setEntry(key: key, value: value, flags: [])
	}

	// outer WRITE + inner READ (sibling): the sibling read sees last-committed state
	@MDB_transact(.readWrite)
	public func writeThenSiblingRead(_ key: borrowing TestKey, uncommitted value: consuming TestValue) throws -> TestValue? {
		try primary.setEntry(key: key, value: value, flags: [])
		return try innerRead(key)
	}

	// outer READ + sibling WRITE: the write commits independently of the outer read
	@MDB_transact(.readOnly)
	public func siblingReadThenWrite(_ key: borrowing TestKey, committed value: consuming TestValue) throws -> TestValue? {
		let before = try? primary.loadEntry(key: key, as: TestValue.self)
		try touchWrite(key, value)
		return before
	}
}
