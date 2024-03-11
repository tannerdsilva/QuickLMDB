import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

#if QUICKLMDB_MACRO_LOG
import Logging
fileprivate let logger = makeDefaultLogger(label:"RAW_function_add_transaction_macro")
fileprivate func makeDefaultLogger(label:String) -> Logger {
	var logger = Logger(label:label)
	logger.logLevel = .debug
	return logger
}
#endif

/// this macro needs to exist beceause the implemented functions cannot be marked as borrowing when used as a member of a protocol
internal struct _QUICKLMDB_INTERNAL_cursor_encodable_impl:MemberMacro {
	static func expansion(of node:SwiftSyntax.AttributeSyntax, providingMembersOf declaration:some SwiftSyntax.DeclGroupSyntax, in context:some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
		return [
			DeclSyntax("""
				/// compares two value entries based on the native value comparison function for the database.
				/// - parameters:
				/// 	- dataL: the left-hand side of the comparison. (borrowing memory ideal)
				/// 	- dataR: the right-hand side of the comparison. (consuming memory ideal)
				/// - returns: a value less than zero if `dataL` is less than `dataR`, zero if `dataL` is equal to `dataR`, and a value greater than zero if `dataL` is greater than `dataR`.
				public borrowing func compareEntryValues(_ dataL:borrowing MDB_cursor_dbtype.MDB_db_key_type, _ dataR:consuming MDB_cursor_dbtype.MDB_db_val_type) -> Int32 {
					return dataL.MDB_access { (lhsVal:consuming MDB_val) in
						return dataR.MDB_access { (rhsVal:consuming MDB_val) in
							return compareEntryValues(lhsVal, rhsVal)
						}
					}
				}
			"""),
			DeclSyntax("""
				/// compares two key entries based on the native key comparison function for the database.
				/// - parameters:
				/// 	- dataL: the left-hand side of the comparison. (borrowing memory ideal)
				///		- dataR: the right-hand side of the comparison. (consuming memory ideal)
				/// - returns: a value less than zero if `dataL` is less than `dataR`, zero if `dataL` is equal to `dataR`, and a value greater than zero if `dataL` is greater than `dataR`.
				public borrowing func compareEntryKeys(_ dataL:borrowing MDB_cursor_dbtype.MDB_db_key_type, _ dataR:consuming MDB_cursor_dbtype.MDB_db_val_type) -> Int32 {
					return dataL.MDB_access { (lhsVal:consuming MDB_val) in
						return dataR.MDB_access { (rhsVal:consuming MDB_val) in
							return compareEntryKeys(lhsVal, rhsVal)
						}
					}
				}
			"""),
			DeclSyntax("""
				/// checks the database for a given key entry.
				/// - parameters:
				/// 	- key: the key to check for. (borrowing memory ideal)
				/// - returns: `true` if the key exists in the database, `false` otherwise.
				public borrowing func containsEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws -> Bool {
					return try key.MDB_access { (keyVal:consuming MDB_val) in
						try containsEntry(key:keyVal)
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func opSetRange(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:MDB_cursor_dbtype.MDB_db_key_type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
					return try key.MDB_access { (keyVal:consuming MDB_val) in
						return try opSetRange(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:keyVal)
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func opSet(returning:MDB_cursor_dbtype.MDB_db_val_type.Type, key: MDB_cursor_dbtype.MDB_db_key_type) throws -> MDB_cursor_dbtype.MDB_db_val_type {
					return try key.MDB_access({ (mdbKey:consuming MDB_val) in
						return MDB_cursor_dbtype.MDB_db_val_type(try opSet(returning:MDB_val.self, key:mdbKey))!
					})
				}
			"""),
			DeclSyntax("""
				public borrowing func opGetCurrent(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
					return try opGetCurrent(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! })
				}
			"""),
			DeclSyntax("""
				public borrowing func opGetBoth(returning: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
					return try key.MDB_access { (mdbKey:consuming MDB_val) in
						return try value.MDB_access { (mdbVal:consuming MDB_val) in
							return try opGetBoth(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:mdbKey, value:mdbVal)
						}
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func opGetBothRange(returning: (key:MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type) {
					return try key.MDB_access { (mdbKey:consuming MDB_val) in
						return try value.MDB_access { (mdbVal:consuming MDB_val) in
							return try opGetBothRange(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:mdbKey, value:mdbVal)
						}
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func opSetKey(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
					return try key.MDB_access({ (mdbKey:consuming MDB_val) in
						return try opSetKey(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:mdbKey)
					})
				}
			"""),
			DeclSyntax("""
				public borrowing func setEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type, flags:Operation.Flags) throws {
					return try key.MDB_access { (keyVal:consuming MDB_val) in
						try value.MDB_access { (valueVal:consuming MDB_val) in
							try setEntry(key:keyVal, value:valueVal, flags:flags)
						}
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func containsEntry(key:borrowing MDB_cursor_dbtype.MDB_db_key_type, value:consuming MDB_cursor_dbtype.MDB_db_val_type) throws -> Bool {
					return try key.MDB_access { (keyVal:consuming MDB_val) in
						return try value.MDB_access { (valueVal:consuming MDB_val) in
							try containsEntry(key:keyVal, value:valueVal)
						}
					}
				}
			""")
		]
	}
}