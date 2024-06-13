import XCTest
@testable import QuickLMDB
import RAW

fileprivate var envPath:URL? = nil
fileprivate var testerEnv:Environment? = nil

@RAW_staticbuff(bytes:4)
@RAW_staticbuff_fixedwidthinteger_type<UInt32>(bigEndian:true)
@MDB_comparable()
struct TestKey:Sendable, ExpressibleByIntegerLiteral {}

@RAW_convertible_string_type<RAW_byte>(UTF8)
@MDB_comparable()
struct EncodedString:Sendable, ExpressibleByStringLiteral {}

final class QuickLMDBTests:XCTestCase {
	static let useMapSize = 5_000_000_000
	override class func setUp() {
		envPath = FileManager.default.temporaryDirectory.appendingPathComponent("QuickLMDB_tests", isDirectory:true)
		try? FileManager.default.removeItem(at:envPath!)
		try! FileManager.default.createDirectory(at:envPath!, withIntermediateDirectories:false)
		testerEnv = try! Environment(path:envPath!.path, flags:[], mapSize:useMapSize, maxReaders:10, maxDBs:10, mode:[.ownerReadWriteExecute], encrypt:Environment.EncryptionConfiguration(ChaChaPoly.self, key:Array("foobarlookddddddfoobarlookdddddd".utf8)), checksum:Blake2.self)
	}
		
	func test1DatabaseCreateDestroy() throws {
		let newTransaction = try! Transaction(env:testerEnv!, readOnly:false)
		let newDatabase = try! Database.Strict<TestKey, EncodedString>(env:testerEnv!, name:"tester_write", flags:[.create], tx:newTransaction)
		try newDatabase.setEntry(key:5, value:"fighters", flags:[], tx:newTransaction)
		try newDatabase.setEntry(key:700, value:"lighters", flags:[], tx:newTransaction)
		try! newTransaction.commit()
		try testerEnv!.sync()
	}

	func test2CloseAndReEncryt() throws {
		testerEnv = nil
		testerEnv = try! Environment(path:envPath!.path, flags:[], mapSize:Self.useMapSize, maxReaders:10, maxDBs:10, mode:[.ownerReadWriteExecute], encrypt:Environment.EncryptionConfiguration(ChaChaPoly.self, key:Array("foobarlookddddddfoobarlookdddddd".utf8)), checksum:Blake2.self)
		let newTransaction = try Transaction(env:testerEnv!, readOnly:true)
		let newDatabase = try Database.Strict<TestKey, EncodedString>(env:testerEnv!, name:"tester_write", flags:[], tx:newTransaction)

		let foo = try newDatabase.loadEntry(key:5, tx:newTransaction)
		let bar = try newDatabase.loadEntry(key:700, tx:newTransaction)
	}
	
	// func testMDBConvertible() throws {
	// 	let isEqual:Bool = try testerEnv!.transact(readOnly:false) { someTrans in
	
	// 		// test the objects that are relying on the codable protocol under the hood
	// 		let makeSet = Set(["foo", "fighters"])
	// 		let makeArray = ["yin", "yang"]
	// 		let makeDict = ["key":"value"]
		
	// 		let newDatabase = try testerEnv!.openDatabase(named:"tester_write", flags:[.create], tx:someTrans)
	// 		try newDatabase.setEntry(value:makeSet, forKey:"setSerial", tx:someTrans)
	// 		try newDatabase.setEntry(value:makeArray, forKey:"arrSerial", tx:someTrans)
	// 		try newDatabase.setEntry(value:makeDict, forKey:"dictSerial", tx:someTrans)
		
	// 		let getSet = try newDatabase.getEntry(type:Set<String>.self, forKey:"setSerial", tx:someTrans)
	// 		let getArray = try newDatabase.getEntry(type:[String].self, forKey:"arrSerial", tx:someTrans)
	// 		let getDict = try newDatabase.getEntry(type:[String:String].self, forKey:"dictSerial", tx:someTrans)
		
	// 		// test objects that rely on LosslessStringProtocol
	// 		let makeNumber = Double.random(in:0..<500)
	// 		try newDatabase.setEntry(value:makeNumber, forKey:"testDouble", tx:someTrans)
	// 		let getNumber = try newDatabase.getEntry(type:Double.self, forKey:"testDouble", tx:someTrans)
		
	// 		return (getSet == makeSet && makeArray == getArray && makeDict == getDict && makeNumber == getNumber) 
	// 	}
	
	// 	XCTAssertEqual(isEqual, true)
	// }
	
	// func testSubTransaction() throws {
	// 	let dbName = "subTransIO_test"
	// 	let inputTest = "hello world"
	// 	let key = "_TEST_hwkey"
	// 	let externalTransTest_IN = "hello world"
	// 	let internalTransTest_IN = "HELLO WORLD"
	// 	let (internalTransTest_OUT, newDB) = try testerEnv!.transact(readOnly:false) { someTrans in
	// 		let newDB = try someTrans.transact(readOnly:false) { subTrans in
	// 			let newDB = try testerEnv!.openDatabase(named:dbName, flags:[.create], tx:subTrans)
	// 			try newDB.setEntry(value:internalTransTest_IN, forKey:key, tx:subTrans)
	// 			return newDB
	// 		}
	// 		let getDBVal = try newDB.getEntry(type:String.self, forKey:key, tx:someTrans)!
	// 		try newDB.setEntry(value:inputTest, forKey:key, tx:someTrans)
	// 		return (getDBVal, newDB)
	// 	}
		
	// 	let externalTransTest_OUT = try testerEnv!.transact(readOnly:true) { someTrans in
	// 		return try newDB.getEntry(type:String.self, forKey:key, tx:someTrans)!
	// 	}
		
	// 	let isEqual:Bool = (externalTransTest_IN == externalTransTest_OUT && internalTransTest_IN == internalTransTest_OUT)
		
	// 	XCTAssertEqual(isEqual, true)
	// }
	
	// func testDupSort() throws {
	// 	let someTrans = try Transaction(testerEnv!, readOnly:false)
	// 	let getDatabase = try testerEnv!.openDatabase(named:"tester_dupsort", flags:[.create, .dupSort], tx:someTrans)
	// 	try getDatabase.setEntry(value:"tradeogre.com", forKey:"XMRBTC", tx:someTrans)
	// 	try getDatabase.setEntry(value:"kraken.com", forKey:"XMRBTC", tx:someTrans)
	// 	print("\(try getDatabase.getStatistics(tx:someTrans).entries)")
	// 	let isSuccessful:Bool = try getDatabase.getStatistics(tx:someTrans).entries == 2
		
	// 	XCTAssertEqual(isSuccessful, true)
	// }

	// func testDatabaseSort() throws {
	// 	let compareResult = try testerEnv!.transact(readOnly:false) { someTrans in
	// 		let getDatabase = try testerEnv!.openDatabase(named:"tester_sort", flags:[.create], tx:someTrans)
	// 		let compareCursor = try getDatabase.cursor(tx:someTrans)
	// 		return compareCursor.compareKeys(672857148.331025, 672857147.99631405)
	// 	}
	// 	XCTAssertEqual(compareResult, 1)
	// }
	override class func tearDown() {
		testerEnv = nil
		try! FileManager.default.removeItem(at:envPath!)
	}
}
