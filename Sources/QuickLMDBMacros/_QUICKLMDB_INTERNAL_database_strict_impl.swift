import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

#if QUICKLMDB_MACRO_LOG
import Logging
fileprivate let logger = makeDefaultLogger(label:"_QUICKLMDB_INTERNAL_database_strict_impl")
fileprivate func makeDefaultLogger(label:String) -> Logger {
	var logger = Logger(label:label)
	logger.logLevel = .debug
	return logger
}
#endif

/// this macro needs to exist beceause the implemented functions cannot be marked as borrowing when used as a member of a protocol
internal struct _QUICKLMDB_INTERNAL_database_strict_impl:MemberMacro {
	static func expansion(of node:SwiftSyntax.AttributeSyntax, providingMembersOf declaration:some SwiftSyntax.DeclGroupSyntax, in context:some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
		return [
			DeclSyntax("""
				public borrowing func setEntry(key:borrowing MDB_db_key_type, value:consuming MDB_db_val_type, flags:consuming Operation.Flags, tx:borrowing Transaction) throws {
					flags.subtract(.reserve)
					return try key.MDB_access { (keyVal:consuming MDB_val) in
						return try value.MDB_access { (valueVal:consuming MDB_val) in
							return try MDB_db_set_entry_static(db:self, key:&keyVal, value:&valueVal, flags:flags, tx:tx)
						}
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func deleteEntry(key:borrowing MDB_db_key_type, value:consuming MDB_db_val_type, tx:borrowing Transaction) throws {
					return try key.MDB_access { keyVal in
						return try value.MDB_access { valueVal in
							return try deleteEntry(key:keyVal, value:valueVal, tx:tx)
						}
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func deleteEntry(key:borrowing MDB_db_key_type, tx:borrowing Transaction) throws {
					return try key.MDB_access { keyVal in
						return try deleteEntry(key:keyVal, tx:tx)
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func loadEntry(key:borrowing MDB_db_key_type, as:MDB_db_val_type.Type, tx:borrowing Transaction) throws -> MDB_db_val_type {
					return try key.MDB_access({ keyVal in 
						return MDB_db_val_type(try loadEntry(key:keyVal, as:MDB_val.self, tx:tx))!
					})
				}
			"""),
			DeclSyntax("""
				public borrowing func containsEntry(key:borrowing MDB_db_key_type, value:consuming MDB_db_val_type, tx: borrowing Transaction) throws -> Bool {
					return try key.MDB_access { keyVal in
						return try value.MDB_access { valueVal in
							return try containsEntry(key:keyVal, value:valueVal, tx:tx)
						}
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func containsEntry(key:borrowing MDB_db_key_type, tx:borrowing Transaction) throws -> Bool {
					return try key.MDB_access { keyVal in
						return try containsEntry(key:keyVal, tx:tx)
					}
				}
			""")
		]
	}
}