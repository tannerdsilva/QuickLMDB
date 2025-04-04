import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

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
				#if DEBUG
				assert(lhs!.pointee.mv_size >= 0, "expected a lhs size greater than or equal to zero")
				assert(rhs!.pointee.mv_size >= 0, "expected a rhs size greater than or equal to zero")
				#endif
				switch (lhs!.pointee.mv_size, rhs!.pointee.mv_size) {
				
					case (0, 0):
						return 0
						
					case (_, 0):
						return Int32(lhs!.pointee.mv_size)
						
					case (0, _):
						return Int32(-1 * rhs!.pointee.mv_size)
					
					case (_, _):
						return Self.RAW_compare(lhs_data:lhs!.pointee.mv_data, lhs_count:lhs!.pointee.mv_size, rhs_data:rhs!.pointee.mv_data, rhs_count:rhs!.pointee.mv_size)
				}
				
			}
		""")]
	}
	
}