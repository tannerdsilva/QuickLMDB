import Testing
import Foundation
import QuickLMDB

// shared test utilities for the runtime suites.

enum TestHelpers {
	@available(*, noasync)
	static func tempDirPath() throws -> String {
		// the generated open(at:) creates the directory as needed
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-tests-\(UUID().uuidString)", isDirectory:true)
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
		return #load(primary, key: key)
	}

	@MDB_transact(.readOnly)
	public func outerReadThenInnerRead(_ key: borrowing TestKey) throws -> TestValue? {
		return try innerRead(key)
	}

	@MDB_transact(.readWrite)
	public func touchWrite(_ key: borrowing TestKey, _ value: consuming TestValue) throws {
		try #store(primary, key: key, value: value)
	}

	// outer WRITE + inner READ (sibling): the sibling read sees last-committed state
	@MDB_transact(.readWrite)
	public func writeThenSiblingRead(_ key: borrowing TestKey, uncommitted value: consuming TestValue) throws -> TestValue? {
		try #store(primary, key: key, value: value)
		return try innerRead(key)
	}

	// outer READ + sibling WRITE: the write commits independently of the outer read
	@MDB_transact(.readOnly)
	public func siblingReadThenWrite(_ key: borrowing TestKey, committed value: consuming TestValue) throws -> TestValue? {
		let before = #load(primary, key: key)
		try touchWrite(key, value)
		return before
	}
}
