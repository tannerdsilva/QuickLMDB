import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

#if QUICKLMDB_MACRO_LOG
import Logging
fileprivate let logger = makeDefaultLogger(label:"_QUICKLMDB_INTERNAL_cursor_dupsort_impl")
fileprivate func makeDefaultLogger(label:String) -> Logger {
	var logger = Logger(label:label)
	logger.logLevel = .debug
	return logger
}
#endif

/// this macro needs to exist beceause the implemented functions cannot be marked as borrowing when used as a member of a protocol
internal struct _QUICKLMDB_INTERNAL_cursor_dupsort_impl:MemberMacro {
	static func expansion(of node:SwiftSyntax.AttributeSyntax, providingMembersOf declaration:some SwiftSyntax.DeclGroupSyntax, in context:some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
		return [
			DeclSyntax("""
				public borrowing func opGetBoth(returning _: (key: MDB_cursor_dbtype.MDB_db_key_type, value: MDB_cursor_dbtype.MDB_db_val_type).Type, key keyVal:consuming MDB_cursor_dbtype.MDB_db_key_type, value valueVal:consuming MDB_cursor_dbtype.MDB_db_val_type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
					return try keyVal.MDB_access({ (keyMDBVal:consuming MDB_val) throws(LMDBError) in
						return try valueVal.MDB_access({ (valueMDBVal:consuming MDB_val) throws(LMDBError) in
							return try opGetBoth(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:keyMDBVal, value:valueMDBVal)
						})
					})
				}
			"""),
			DeclSyntax("""
				public borrowing func opGetBothRange(returning _: (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type, key keyVal:consuming MDB_cursor_dbtype.MDB_db_key_type, value valueVal:consuming MDB_cursor_dbtype.MDB_db_val_type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
					return try keyVal.MDB_access({ (keyMDBVal:consuming MDB_val) throws(LMDBError) in
						return try valueVal.MDB_access({ (valueMDBVal:consuming MDB_val) throws(LMDBError)  in
							return try opGetBothRange(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! }, key:keyMDBVal, value:valueMDBVal)
						})
					})
				}
			"""),
			DeclSyntax("""
				public borrowing func opFirstDup(returning:MDB_cursor_dbtype.MDB_db_val_type.Type) throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type {
					return try opFirstDup(transforming:MDB_val.self, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! })
				}
			"""),
			DeclSyntax("""
				public borrowing func opLastDup(returning:MDB_cursor_dbtype.MDB_db_val_type.Type) throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type {
					return try opLastDup(transforming:MDB_val.self, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! })
				}
			"""),
			DeclSyntax("""
				public borrowing func opNextNoDup(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
					return try opNextNoDup(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! })
				}
			"""),
			DeclSyntax("""
				public borrowing func opNextDup(returning:MDB_cursor_dbtype.MDB_db_val_type.Type) throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type {
					return try opNextDup(transforming:MDB_val.self, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! })
				}
			"""),
			DeclSyntax("""
				public borrowing func opPreviousDup(returning:MDB_cursor_dbtype.MDB_db_val_type.Type) throws(LMDBError) -> MDB_cursor_dbtype.MDB_db_val_type {
					return try opPreviousDup(transforming:MDB_val.self, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! })
				}
			"""),
			DeclSyntax("""
				public borrowing func opPreviousNoDup(returning:(key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type).Type) throws(LMDBError) -> (key:MDB_cursor_dbtype.MDB_db_key_type, value:MDB_cursor_dbtype.MDB_db_val_type) {
					return try opPreviousNoDup(transforming:(key:MDB_val, value:MDB_val).self, keyOutTransformer: { MDB_cursor_dbtype.MDB_db_key_type($0)! }, valueOutTransformer: { MDB_cursor_dbtype.MDB_db_val_type($0)! })
				}
			""")
		]
	}
}