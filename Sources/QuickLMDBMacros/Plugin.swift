import SwiftCompilerPlugin
import SwiftSyntaxMacros
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

@main
struct QuickLMDBMacros:CompilerPlugin {
	let providingMacros:[Macro.Type] = [
		MDB_comparable_macro.self,
		_QUICKLMDB_INTERNAL_cursor_encodable_impl.self,
		_QUICKLMDB_INTERNAL_cursor_init_basics_impl.self,
		_QUICKLMDB_INTERNAL_cursor_dupfixed_impl.self,
		_QUICKLMDB_INTERNAL_database_strict_impl.self,
		_QUICKLMDB_INTERNAL_cursor_dupsort_impl.self,
		MDB_environment_macro.self,
		MDB_transact_macro.self,
		MDB_verb_error_macro.self,
		MDB_app_macro.self,
		MDB_transact_span_macro.self
	]
}