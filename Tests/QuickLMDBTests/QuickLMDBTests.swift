import XCTest
@testable import QuickLMDB

final class QuickLMDBTests:XCTestCase {
	
	///Tests that an environment can be created and written to and that the same environment can later be opened and read successfully
	func testEnvironmentCreate() throws {
		
		let writeKey = "THIS is a TEST key"
		let writeValue = "thsi IS A test VALUE"
		
		//this is the function that will either create an environment or read the environment. Encapsulating the environment in a child function like this will allow Swift to release the environment from memory between the "create" and "read" phase of this test.
		func executeEnvTest(writeIt:Bool) throws -> Bool {
			let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("QuickLMDB_tests", isDirectory:true)
			if (writeIt == true) {
				try? FileManager.default.removeItem(at:tempDir)
				try FileManager.default.createDirectory(at:tempDir, withIntermediateDirectories:false)
				let makeEnv = try Environment(path:tempDir.path)
				try makeEnv.transact(readOnly:false) { someTrans in
					let newDatabase = try makeEnv.openDatabase(named:nil, tx:someTrans)
					try newDatabase.setEntry(value:writeValue, forKey:writeKey, tx:someTrans)
				}
				return true
			} else {
				let makeEnv = try Environment(path:tempDir.path)
				defer {
					try? FileManager.default.removeItem(at:tempDir)
				}
				return try makeEnv.transact(readOnly:true) { someTrans in
					let openDatabase = try makeEnv.openDatabase(named:nil, tx:someTrans)
					if let checkVal = try openDatabase.getEntry(type:String.self, forKey:writeKey, tx:someTrans), checkVal == writeValue {
						return true
					} else {
						return false
					}
				}
			}
		}
		
		//create the environment
		_ = try executeEnvTest(writeIt:true)

		//read the environment
		XCTAssertEqual(try executeEnvTest(writeIt:false), true)
	}
    
    func testDatabaseSort() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("QuickLMDB_tests", isDirectory:true)
        try? FileManager.default.removeItem(at:tempDir)
        try FileManager.default.createDirectory(at:tempDir, withIntermediateDirectories:false)
        let makeEnv = try Environment(path:tempDir.path)
        try makeEnv.transact(readOnly:false) { someTrans in
            let checkDatabase = try makeEnv.openDatabase(named:nil, flags:[.create], tx:someTrans)
            let compareCursor = try checkDatabase.cursor(tx:someTrans)
            
			XCTAssertEqual(compareCursor.compareKeys("672857148.331025", "672857147.99631405"), 1)
        }
        
    }
}
