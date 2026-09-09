import Testing
import Foundation
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosTestSupport
import SwiftSyntaxMacrosGenericTestSupport
@testable import QuickLMDBMacros

// strict expansion fixtures for @MDB_transact (attached body macro). the failureHandler
// records a Swift Testing Issue so mismatches actually fail the suite (the default
// XCTFail-based handler is a no-op under Swift Testing).

private func assertTXExpansion(_ source:String, expected expanded:String) {
	assertMacroExpansion(
		source, expandedSource: expanded,
		macroSpecs: ["MDB_transact": MacroSpec(type:MDB_transact_macro.self)],
		failureHandler: { spec in Issue.record(Comment(stringLiteral: spec.message)) }
	)
}

private let voidFixture = """
struct TestCore {
    var env: Environment
    var primary: Database.Strict<TestKey, TestValue>
    func writeBoth(_ key: TestKey, _ value: TestValue) throws {
        let tx = try Transaction(env: self.env, readOnly: false)
        func __mdb_body(_ key: TestKey, _ value: TestValue, _ tx: borrowing Transaction) throws {
            try primary.store(key: key, value: value, tx: tx)
        }
        do {
            try __mdb_body(key, value, tx)
        } catch let error {
            tx.abort()
            throw error
        }
        try tx.commit()
    }
}
"""

@Suite("MDB_transact body macro expansion")
struct MDB_transactExpansionTests {

	@Test func readWriteVoid() {
		assertTXExpansion(
			"""
			struct TestCore {
			    var env: Environment
			    var primary: Database.Strict<TestKey, TestValue>
			    @MDB_transact(.readWrite)
			    func writeBoth(_ key: TestKey, _ value: TestValue) throws {
			        try #store(primary, key: key, value: value)
			    }
			}
			""",
			expected: voidFixture
		)
	}

	@Test func readOnlyWithReturnAndCursor() {
		assertTXExpansion(
			"""
			struct TestCore {
			    var env: Environment
			    var primary: Database.Strict<TestKey, TestValue>
			    @MDB_transact(.readOnly)
			    func scanAll() throws -> [TestValue] {
			        var result: [TestValue] = []
			        #cursor(primary) { cursor in
			            for (_, v) in cursor {
			                result.append(v)
			            }
			        }
			        return result
			    }
			}
			""",
			expected: """
			struct TestCore {
			    var env: Environment
			    var primary: Database.Strict<TestKey, TestValue>
			    func scanAll() throws -> [TestValue] {
			        let tx = try Transaction(env: self.env, readOnly: true)
			        func __mdb_body(_ tx: borrowing Transaction) throws -> [TestValue] {
			            var result: [TestValue] = []
			            primary.cursor(tx: tx) { cursor in
			                        for (_, v) in cursor {
			                            result.append(v)
			                        }
			                    }
			            return result
			        }
			        let __mdb_output: [TestValue]
			        do {
			            __mdb_output = try __mdb_body(tx)
			        } catch let error {
			            tx.abort()
			            throw error
			        }
			        tx.abort()
			        return __mdb_output
			    }
			}
			"""
		)
	}

	@Test func readWriteChildUsesParent() {
		assertTXExpansion(
			"""
			struct TestCore {
			    var env: Environment
			    var primary: Database.Strict<TestKey, TestValue>
			    @MDB_transact(.readWriteChild)
			    func writeNested(_ key: TestKey, _ value: TestValue, parent: Transaction) throws {
			        try #store(primary, key: key, value: value)
			    }
			}
			""",
			expected: """
			struct TestCore {
			    var env: Environment
			    var primary: Database.Strict<TestKey, TestValue>
			    func writeNested(_ key: TestKey, _ value: TestValue, parent: Transaction) throws {
			        let tx = try Transaction(env: self.env, readOnly: false, parent: parent)
			        func __mdb_body(_ key: TestKey, _ value: TestValue, parent: Transaction, _ tx: borrowing Transaction) throws {
			            try primary.store(key: key, value: value, tx: tx)
			        }
			        do {
			            try __mdb_body(key, value, parent: parent, tx)
			        } catch let error {
			            tx.abort()
			            throw error
			        }
			        try tx.commit()
			    }
			}
			"""
		)
	}

	@Test func explicitTxArgumentIsPreserved() {
		assertTXExpansion(
			"""
			struct TestCore {
			    var env: Environment
			    var primary: Database.Strict<TestKey, TestValue>
			    @MDB_transact(.readWrite)
			    func forward(_ key: TestKey, _ value: TestValue, _ helperTX: Transaction) throws {
			        try primary.setEntry(key: key, value: value, flags: [], tx: helperTX)
			    }
			}
			""",
			expected: """
			struct TestCore {
			    var env: Environment
			    var primary: Database.Strict<TestKey, TestValue>
			    func forward(_ key: TestKey, _ value: TestValue, _ helperTX: Transaction) throws {
			        let tx = try Transaction(env: self.env, readOnly: false)
			        func __mdb_body(_ key: TestKey, _ value: TestValue, _ helperTX: Transaction, _ tx: borrowing Transaction) throws {
			            try primary.setEntry(key: key, value: value, flags: [], tx: helperTX)
			        }
			        do {
			            try __mdb_body(key, value, helperTX, tx)
			        } catch let error {
			            tx.abort()
			            throw error
			        }
			        try tx.commit()
			    }
			}
			"""
		)
	}

	@Test func loadDeleteContainsAndClearVerbsLower() {
		assertTXExpansion(
			"""
			struct TestCore {
			    var env: Environment
			    var primary: Database.Strict<TestKey, TestValue>
			    var secondary: Database.DupSort<TestKey, TestValue>
			    @MDB_transact(.readWrite)
			    func orchestrate(_ key: TestKey, _ value: TestValue, _ dup: TestValue) throws -> TestValue? {
			        let v = try #load(primary, key: key)
			        let present = try #contains(secondary, key: key)
			        let pair = try #contains(secondary, key: key, value: dup)
			        try #delete(primary, key: key)
			        try #delete(secondary, key: key, value: dup)
			        try #clear(primary)
			        return v
			    }
			}
			""",
			expected: """
			struct TestCore {
			    var env: Environment
			    var primary: Database.Strict<TestKey, TestValue>
			    var secondary: Database.DupSort<TestKey, TestValue>
			    func orchestrate(_ key: TestKey, _ value: TestValue, _ dup: TestValue) throws -> TestValue? {
			        let tx = try Transaction(env: self.env, readOnly: false)
			        func __mdb_body(_ key: TestKey, _ value: TestValue, _ dup: TestValue, _ tx: borrowing Transaction) throws -> TestValue? {
			            let v = try primary.load(key: key, tx: tx)
			            let present = try secondary.contains(key: key, tx: tx)
			            let pair = try secondary.cursor(tx: tx) {
			                try $0.containsEntry(key: key, value: dup)
			            }
			            try primary.delete(key: key, tx: tx)
			            try secondary.delete(key: key, value: dup, tx: tx)
			            try primary.deleteAllEntries(tx: tx)
			            return v
			        }
			        let __mdb_output: TestValue?
			        do {
			            __mdb_output = try __mdb_body(key, value, dup, tx)
			        } catch let error {
			            tx.abort()
			            throw error
			        }
			        try tx.commit()
			        return __mdb_output
			    }
			}
			"""
		)
	}

	@Test func userFunctionNamedLikeOperationIsUntouched() {
		// marker-gated attribution: a user helper named `setEntry` (different shape than
		// the operation) is emitted byte-for-byte — no callee-name matching remains.
		assertTXExpansion(
			"""
			struct TestCore {
			    var env: Environment
			    var primary: Database.Strict<TestKey, TestValue>
			    @MDB_transact(.readWrite)
			    func audit(_ key: TestKey) throws {
			        let n = setEntry("label")
			        _ = n
			    }
			}
			""",
			expected: """
			struct TestCore {
			    var env: Environment
			    var primary: Database.Strict<TestKey, TestValue>
			    func audit(_ key: TestKey) throws {
			        let tx = try Transaction(env: self.env, readOnly: false)
			        func __mdb_body(_ key: TestKey, _ tx: borrowing Transaction) throws {
			            let n = setEntry("label")
			            _ = n
			        }
			        do {
			            try __mdb_body(key, tx)
			        } catch let error {
			            tx.abort()
			            throw error
			        }
			        try tx.commit()
			    }
			}
			"""
		)
	}
}
