import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

#if QUICKLMDB_MACRO_LOG
import Logging
fileprivate let logger = makeDefaultLogger(label:"MDB_comparable_macro")
fileprivate func makeDefaultLogger(label:String) -> Logger {
	var logger = Logger(label:label)
	logger.logLevel = .debug
	return logger
}
#endif

internal struct MDB_comparable_macro:MemberMacro, ExtensionMacro {
    static func expansion(of node: SwiftSyntax.AttributeSyntax, attachedTo declaration: some SwiftSyntax.DeclGroupSyntax, providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol, conformingTo protocols: [SwiftSyntax.TypeSyntax], in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.ExtensionDeclSyntax] {
        return [try ExtensionDeclSyntax("""
			extension \(type):MDB_comparable {}
		""")]
    }

	private class StructClassEnumModifiersFinder:SyntaxVisitor {
		var modifierList:DeclModifierListSyntax?
		override func visit(_ node:StructDeclSyntax) -> SyntaxVisitorContinueKind {
			if modifierList == nil {
				modifierList = node.modifiers
			}
			return .skipChildren
		}
		override func visit(_ node:ClassDeclSyntax) -> SyntaxVisitorContinueKind {
			if modifierList == nil {
				modifierList = node.modifiers
			}
			return .skipChildren
		}
		override func visit(_ node:EnumDeclSyntax) -> SyntaxVisitorContinueKind {
			if modifierList == nil {
				modifierList = node.modifiers
			}
			return .skipChildren
		}
	}
	static func expansion(of node:SwiftSyntax.AttributeSyntax, providingMembersOf declaration:some SwiftSyntax.DeclGroupSyntax, in context:some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
		let seracher = StructClassEnumModifiersFinder(viewMode:.sourceAccurate)
		seracher.walk(declaration)
		let foundModList = seracher.modifierList ?? []
		return [DeclSyntax("""
			\(foundModList) static let MDB_compare_f:MDB_compare_ftype = { lhs, rhs in
				return Self.RAW_compare(lhs_data:lhs!.pointee.mv_data, lhs_count:lhs!.pointee.mv_size, rhs_data:rhs!.pointee.mv_data, rhs_count:rhs!.pointee.mv_size)
			}
		""")]
	}
	
}