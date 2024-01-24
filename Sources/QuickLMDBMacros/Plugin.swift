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
		RAW_function_add_transaction_macro.self
	]
}