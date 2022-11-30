import XCTest
@testable import QuickLMDB

fileprivate var envPath:URL? = nil
fileprivate var testerEnv:Environment? = nil

final class QuickLMDBTests:XCTestCase {

	override class func setUp() {
		envPath = FileManager.default.temporaryDirectory.appendingPathComponent("QuickLMDB_tests", isDirectory:true)
		try? FileManager.default.removeItem(at:envPath!)
		try! FileManager.default.createDirectory(at:envPath!, withIntermediateDirectories:false)
		testerEnv = try! Environment(path:envPath!.path, flags:[.noSync])
	}
		
	func testDatabaseCreateDestroy() throws {
		let getDB = try testerEnv!.transact(readOnly:false) { someTrans in
			let newDB = try testerEnv!.openDatabase(named:"test_destroy_db", flags:[.create], tx:someTrans)
			try testerEnv!.deleteDatabase(newDB, tx:someTrans)
		}
	}
	
	func testMDBConvertible() throws {
		let isEqual:Bool = try testerEnv!.transact(readOnly:false) { someTrans in
	
			// test the objects that are relying on the codable protocol under the hood
			let makeSet = Set(["foo", "fighters"])
			let makeArray = ["yin", "yang"]
			let makeDict = ["key":"value"]
		
			let newDatabase = try testerEnv!.openDatabase(named:"tester_write", flags:[.create], tx:someTrans)
			try newDatabase.setEntry(value:makeSet, forKey:"setSerial", tx:someTrans)
			try newDatabase.setEntry(value:makeArray, forKey:"arrSerial", tx:someTrans)
			try newDatabase.setEntry(value:makeDict, forKey:"dictSerial", tx:someTrans)
		
			let getSet = try newDatabase.getEntry(type:Set<String>.self, forKey:"setSerial", tx:someTrans)
			let getArray = try newDatabase.getEntry(type:[String].self, forKey:"arrSerial", tx:someTrans)
			let getDict = try newDatabase.getEntry(type:[String:String].self, forKey:"dictSerial", tx:someTrans)
		
			// test objects that rely on LosslessStringProtocol
			let makeNumber = Double.random(in:0..<500)
			try newDatabase.setEntry(value:makeNumber, forKey:"testDouble", tx:someTrans)
			let getNumber = try newDatabase.getEntry(type:Double.self, forKey:"testDouble", tx:someTrans)
		
			return (getSet == makeSet && makeArray == getArray && makeDict == getDict && makeNumber == getNumber) 
		}
	
		XCTAssertEqual(isEqual, true)
	}

	func testDatabaseSort() throws {
		let compareResult = try testerEnv!.transact(readOnly:false) { someTrans in
			let getDatabase = try testerEnv!.openDatabase(named:"tester_sort", flags:[.create], tx:someTrans)
			let compareCursor = try getDatabase.cursor(tx:someTrans)
			return try compareCursor.compareKeys(672857148.331025, 672857147.99631405)
		}
		XCTAssertEqual(compareResult, 1)
	}
//	    
	

	override class func tearDown() {
		try! FileManager.default.removeItem(at:envPath!)
	}
}
