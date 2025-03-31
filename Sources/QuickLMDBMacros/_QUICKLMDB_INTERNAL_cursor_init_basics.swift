import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

/// this macro needs to exist beceause the implemented functions cannot be marked as borrowing when used as a member of a protocol
internal struct _QUICKLMDB_INTERNAL_cursor_init_basics_impl:MemberMacro {
	static func expansion(of node:SwiftSyntax.AttributeSyntax, providingMembersOf declaration:some SwiftSyntax.DeclGroupSyntax, in context:some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
		return [
			DeclSyntax("""
				/// this is the pointer to the `MDB_cursor` struct associated with a given instance.
				private let _cursor_handle:OpaquePointer
			"""),
			DeclSyntax("""
				public borrowing func cursorHandle() -> OpaquePointer {
					return _cursor_handle
				}
			"""),
			DeclSyntax("""
				/// this is the database that this cursor is associated with.
				private let _db_handle:MDB_dbi
			"""),
			DeclSyntax("""
				public borrowing func dbHandle() -> MDB_dbi {
					return _db_handle
				}
			"""),
			DeclSyntax("""
				/// pointer to the `MDB_txn` struct associated with a given instance.
				private let _tx_handle:OpaquePointer
			"""),
			DeclSyntax("""
				public borrowing func txHandle() -> OpaquePointer {
					return _tx_handle
				}
			"""),
			DeclSyntax("""
				#if QUICKLMDB_SHOULDLOG
				private let _logger:Logger?
				public borrowing func logger() -> Logger? {
					return _logger
				}
				/// opens a new cursor instance from a given database and transaction pairing.
				public init(db:borrowing MDB_cursor_dbtype, tx:borrowing Transaction) throws(LMDBError) {
					var buildCursor:OpaquePointer? = nil
					let openCursorResult = mdb_cursor_open(tx.txHandle(), db.dbHandle(), &buildCursor)
					guard openCursorResult == MDB_SUCCESS else {
						throw LMDBError(returnCode:openCursorResult)
					}
					self._cursor_handle = buildCursor!
					self._db_handle = db.dbHandle()
					self._tx_handle = tx.txHandle()
					self._logger = db.logger()
				}
				#else
				public init(db:borrowing MDB_cursor_dbtype, tx:borrowing Transaction) throws(LMDBError) {
					var buildCursor:OpaquePointer? = nil
					let openCursorResult = mdb_cursor_open(tx.txHandle(), db.dbHandle(), &buildCursor)
					guard openCursorResult == MDB_SUCCESS else {
						throw LMDBError(returnCode:openCursorResult)
					}
					self._cursor_handle = buildCursor!
					self._db_handle = db.dbHandle()
					self._tx_handle = tx.txHandle()
				}
				#endif
			"""),
			DeclSyntax("""
				deinit {
					// close the cursor
					mdb_cursor_close(_cursor_handle)
				}
			"""),
		]
	}
}