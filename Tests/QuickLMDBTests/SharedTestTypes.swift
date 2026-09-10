import Foundation
import QuickLMDB
import RAW

// shared runtime test types for the QuickLMDB suite: fixed-width RAW keys and
// values, the standard `@MDB_environment` core, and the environment helpers.

@RAW_staticbuff(bytes: 4)
@RAW_staticbuff_fixedwidthinteger_type<UInt32>(bigEndian: true)
@MDB_comparable
@frozen public struct TestKey: Sendable, Hashable, Equatable, Comparable {}

@RAW_staticbuff(bytes: 8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian: true)
@MDB_comparable
@frozen public struct TestValue: Sendable, Hashable, Equatable, Comparable {}

public enum TestError: Error {
	case simulatedFailure
}

@MDB_environment(file: "test.mdb", flags: [.noSubDir], maxReaders: 16, maxDBs: 8)
public struct TestCore: Sendable {
	public let env: Environment
	public let primary: Database.Strict<TestKey, TestValue>
	public let secondary: Database.DupSort<TestKey, TestValue>
}

enum TestHelpers {
	@available(*, noasync)
	static func tempDirPath() throws -> String {
		// the generated open(at:) creates the directory as needed
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qlmdb-tests-\(UUID().uuidString)", isDirectory: true)
		return dir.path
	}

	@available(*, noasync)
	static func makeCore() throws -> TestCore {
		return try TestCore.open(at: TestHelpers.tempDirPath())
	}
}
