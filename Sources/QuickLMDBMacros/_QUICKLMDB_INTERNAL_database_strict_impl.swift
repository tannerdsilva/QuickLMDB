import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

/// this macro needs to exist beceause the implemented functions cannot be marked as borrowing when used as a member of a protocol
internal struct _QUICKLMDB_INTERNAL_database_strict_impl:MemberMacro {
	static func expansion(of node:SwiftSyntax.AttributeSyntax, providingMembersOf declaration:some SwiftSyntax.DeclGroupSyntax, in context:some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
		return [
			DeclSyntax("""
				public borrowing func setEntry(key:borrowing MDB_db_key_type, value:consuming MDB_db_val_type, flags:consuming Operation.Flags, tx:borrowing Transaction) throws(LMDBError) {
					flags.subtract(.reserve)
					try key.MDB_access { (keyVal:consuming MDB_val) throws(LMDBError) in
						try value.MDB_access { (valueVal:consuming MDB_val) throws(LMDBError) in
							try MDB_db_set_entry_static(db:self, key:&keyVal, value:&valueVal, flags:flags, tx:tx)
						}
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func deleteEntry(key:borrowing MDB_db_key_type, value:consuming MDB_db_val_type, tx:borrowing Transaction) throws(LMDBError) {
					return try key.MDB_access { (keyVal:MDB_val) throws(LMDBError) in
						return try value.MDB_access { (valueVal:MDB_val) throws(LMDBError) in
							try deleteEntry(key:keyVal, value:valueVal, tx:tx)
						}
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func deleteEntry(key:borrowing MDB_db_key_type, tx:borrowing Transaction) throws(LMDBError) {
					return try key.MDB_access { (keyVal:MDB_val) throws(LMDBError) in
						return try deleteEntry(key:keyVal, tx:tx)
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func loadEntry(key:borrowing MDB_db_key_type, as:MDB_db_val_type.Type, tx:borrowing Transaction) throws(LMDBError) -> MDB_db_val_type {
					return try key.MDB_access({ (keyVal:MDB_val) throws(LMDBError) in 
						return MDB_db_val_type(try loadEntry(key:keyVal, as:MDB_val.self, tx:tx))!
					})
				}
			"""),
			DeclSyntax("""
				public borrowing func containsEntry(key:borrowing MDB_db_key_type, value:consuming MDB_db_val_type, tx: borrowing Transaction) throws(LMDBError) -> Bool {
					return try key.MDB_access { (keyVal:MDB_val) throws(LMDBError) -> Bool in
						return try value.MDB_access { (valueVal:MDB_val) throws(LMDBError) -> Bool in
							return try containsEntry(key:keyVal, value:valueVal, tx:tx)
						}
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func containsEntry(key:borrowing MDB_db_key_type, tx:borrowing Transaction) throws(LMDBError) -> Bool {
					return try key.MDB_access { (keyVal:MDB_val) throws(LMDBError) -> Bool in
						return try containsEntry(key:keyVal, tx:tx)
					}
				}
			""")
		]
	}
}