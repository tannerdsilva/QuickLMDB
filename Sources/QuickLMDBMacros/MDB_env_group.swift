import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// @MDB_env_group(file:flags:maxReaders:maxDBs:mode:) — the SHARED-PHYSICAL-ENV layer.
//
// one physical LMDB file = one TYPE = one struct whose stored instance
// properties are its member cores, each a NESTED @MDB_environment struct.
// the group opens the physical env ONCE and constructs every member core from
// the same `Environment` value — one setup write-transaction opens every
// member's tables — restoring cross-core atomic composition on one file (the
// v22 multi-environment blind spot: several cores over one physical env used
// to mean two write transactions on one handle → LMDB writer-mutex
// self-deadlock).
//
// membership is POSITIONAL (nesting), not attributed: a nested
// @MDB_environment struct inside a @MDB_env_group is a member by construction,
// and its full type name (`DaemonEnv.DaemonDB`) carries the group prefix — so
// the boundary dialect (@MDB_transact) can key transactions to the GROUP from
// the type spelling alone, with no cross-declaration resolution.
//
// generated, on the group struct:
//
//   public static func open(at basePath: String, mapHeadroom: UInt64 = ...) throws -> Self
//       creates the dir, sizes the map (file size + headroom), opens the env
//       (forcing .noTLS), opens EVERY member's tables in one setup
//       write-transaction, commits, and assembles the members.
//
//   public var env: Environment { <firstMember>.env }
//       the group's shared env — the boundary shell opens its transactions from
//       it, and the typed verbs address member tables through the members
//       (`\.member.table`), so the whole shared-env surface needs no special
//       casing in the transaction layer.
//
//   public static let mdb_core_names: [String]
//       the member inventory, arrangement order (docs/tooling).
//
//   extension <Group>: MDB_environment {}
//       the group is itself verb-addressable.
//
// contract: stored instance properties = exactly the member cores (nested
// @MDB_environment structs), each arranged exactly once; a member core must be
// arranged; no property named `env` (the accessor owns that name). every
// nested @MDB_environment member is schema-only (validated by the member
// macro: no file:, no env tuning). table names must be unique ACROSS members —
// they share one physical env.

internal struct MDB_env_group_macro: MemberMacro, ExtensionMacro {

	enum GroupError: Swift.Error, CustomStringConvertible {
		case notAStruct
		case missingFileArg
		case noMembers
		case propertyNotAMember(String, String)
		case memberNotArranged(String)
		case memberArrangedTwice(String)
		case propertyNamedEnv
		case duplicateTableName(String, String)

		var description: String {
			switch self {
			case .notAStruct:
				return "@MDB_env_group can only be applied to a struct"
			case .missingFileArg:
				return "@MDB_env_group requires a `file:` argument naming the environment file (e.g. @MDB_env_group(file: \"daemon.mdb\"))"
			case .noMembers:
				return "@MDB_env_group requires at least one member core — a stored property of a nested @MDB_environment struct type, e.g. `public let daemon: DaemonDB`"
			case .propertyNotAMember(let prop, let type):
				return "@MDB_env_group: stored property '\(prop)' has type '\(type)' which is not a nested @MDB_environment member core — a group's stored instance properties must be exactly its member cores"
			case .memberNotArranged(let name):
				return "@MDB_env_group: member core '\(name)' is declared but not arranged as a stored property — add one property of its type and remove any field you delegate outside the group"
			case .memberArrangedTwice(let name):
				return "@MDB_env_group: member core '\(name)' is arranged by more than one stored property — each member core is arranged exactly once"
			case .propertyNamedEnv:
				return "@MDB_env_group: no stored property may be named `env` — the group owns that name for its shared-environment accessor"
			case .duplicateTableName(let table, let member):
				return "@MDB_env_group: table \"\(table)\" on member '\(member)' collides with a table already claimed by another member — member cores share one physical environment, so table names must be unique across the group"
			}
		}
	}

	private struct ArrangedMember {
		let property: String          // stored property name (arrow in Self init)
		let typeName: String          // bare member struct name (resolves inside the group)
		let access: String
		let tables: [MDB_environment_macro.ResolvedTable]
	}

	static func expansion(
		of node: AttributeSyntax,
		attachedTo declaration: some DeclGroupSyntax,
		providingExtensionsOf type: some TypeSyntaxProtocol,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [ExtensionDeclSyntax] {
		return [try ExtensionDeclSyntax("""
			extension \(type):MDB_environment {}
			""")]
	}

	static func expansion(
		of node: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		guard let structDecl = declaration.as(StructDeclSyntax.self) else {
			throw GroupError.notAStruct
		}

		// -- attribute arguments (env tuning, mirroring @MDB_environment)
		var fileArg: String? = nil
		var flagsArg = "[.noSubDir]"
		var maxReadersArg = "32"
		var maxDBsArg = "8"
		var modeArg = "[.ownerReadWriteExecute, .groupRead, .otherRead]"
		var versionArg: String? = nil
		if let argList = node.arguments?.as(LabeledExprListSyntax.self) {
			for arg in argList {
				guard let label = arg.label?.text else { continue }
				let value = arg.expression.trimmedDescription
				switch label {
				case "file": fileArg = value
				case "version": versionArg = value
				case "flags": flagsArg = value
				case "maxReaders": maxReadersArg = value
				case "maxDBs": maxDBsArg = value
				case "mode": modeArg = value
				default: break
				}
			}
		}
		guard let fileArg, fileArg.isEmpty == false else {
			throw GroupError.missingFileArg
		}

		// -- scan nested @MDB_environment structs (the member core TYPES)
		var memberTypes: [(name: String, decl: StructDeclSyntax)] = []
		for member in structDecl.memberBlock.members {
			guard let nested = member.decl.as(StructDeclSyntax.self) else { continue }
			if nested.attributes.contains(where: { attr in
				(attr.as(AttributeSyntax.self)?.attributeName.trimmedDescription) == "MDB_environment"
			}) {
				memberTypes.append((name: nested.name.text, decl: nested))
			}
		}

		// -- scan stored instance properties (the ARRANGED members)
		var arranged: [(name: String, typeText: String, access: String)] = []
		for member in structDecl.memberBlock.members {
			guard let prop = member.decl.as(VariableDeclSyntax.self) else { continue }
			if prop.modifiers.contains(where: { $0.name.text == "static" }) { continue }
			guard let binding = prop.bindings.first,
				  let propName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
				  let typeAnnot = binding.typeAnnotation else { continue }
			if binding.accessorBlock != nil { continue }
			let access = prop.modifiers.first(where: { ["public", "internal", "fileprivate", "private"].contains($0.name.text) })?.name.text ?? ""
			arranged.append((name: propName, typeText: typeAnnot.type.trimmedDescription, access: access))
		}

		// -- match arranged properties to member types (bare or self-qualified)
		//    and validate the arrangement contract
		var members: [ArrangedMember] = []
		var memberArrangeCount: [String: Int] = [:]
		for nested in memberTypes { memberArrangeCount[nested.name] = 0 }
		for arr in arranged {
			if arr.name == "env" { throw GroupError.propertyNamedEnv }
			guard let match = memberTypes.first(where: {
				$0.name == arr.typeText || arr.typeText.hasSuffix("." + $0.name)
			}) else {
				throw GroupError.propertyNotAMember(arr.name, arr.typeText)
			}
			memberArrangeCount[match.name] = (memberArrangeCount[match.name] ?? 0) + 1
			let (hasEnv, tables) = try MDB_environment_macro.scanCore(match.decl)
			guard hasEnv else { throw MDB_environment_macro.MacroError.missingEnv }
			members.append(ArrangedMember(property: arr.name, typeName: match.name, access: arr.access, tables: tables))
		}
		guard !members.isEmpty else { throw GroupError.noMembers }
		for (name, count) in memberArrangeCount {
			guard count != 0 else { throw GroupError.memberNotArranged(name) }
			guard count == 1 else { throw GroupError.memberArrangedTwice(name) }
		}

		// -- cross-member table-name uniqueness (one physical env)
		var claimed: [String: String] = [:]
		for member in members {
			for table in member.tables {
				if claimed[table.name] != nil {
					throw GroupError.duplicateTableName(table.name, member.property)
				}
				claimed[table.name] = member.property
			}
		}

		// -- access prefix: the common core access (mirrors @MDB_layout)
		let accessPrefix = members.allSatisfy { $0.access == members[0].access } ? members[0].access : ""
		let mods = accessPrefix.isEmpty ? "" : accessPrefix + " "

		var decls: [String] = []

		// -- the shared-env accessor (the boundary shell opens from it)
		var accessor = "/// the shared environment handle of this group's physical environment — every member core opens from the same value.\n"
		accessor += "\(mods)var env: Environment {\n    \(members[0].property).env\n}"
		decls.append(accessor)

		// -- the member inventory (arrangement order)
		let names = members.map { "\"\($0.property)\"" }.joined(separator: ", ")
		decls.append("\(mods)static let mdb_core_names: [String] = [\(names)]")

		// -- the arrangement open: ONE env, ONE setup write-transaction
		var open = "/// opens the physical environment once and constructs every member core from it —\n"
		open += "/// all member tables are created in a single setup write-transaction.\n"
		open += "/// - parameter basePath: the directory that will contain the environment file (created if\n"
		open += "///   it does not already exist).\n"
		open += "/// - parameter mapHeadroom: added to the current file size when sizing the memory map.\n"
		open += "@available(*, noasync)\n"
		open += "\(mods)static func open(at basePath: String, mapHeadroom: UInt64 = 1073741824) throws -> Self {\n"
		open += "    _ = QuickLMDB._MDBEnvironmentSupport.__createDirectory(at: basePath)\n"
		open += "    let slash = basePath.hasSuffix(\"/\") ? \"\" : \"/\"\n"
		if let versionArg {
			open += "    let targetPath = basePath + slash + (\(fileArg).hasSuffix(\".mdb\") ? String(\(fileArg).dropLast(4)) + \"-v\(versionArg)\" + \".mdb\" : \(fileArg) + \"-v\(versionArg)\")\n"
		} else {
			open += "    let targetPath = basePath + slash + \(fileArg)\n"
		}
		open += "    let fileSize = QuickLMDB._MDBEnvironmentSupport.__fileSize(at: targetPath)\n"
		open += "    let env = try Environment(path: targetPath, flags: QuickLMDB.Environment.Flags([.noTLS]).union(\(flagsArg)), mapSize: Int(fileSize + mapHeadroom), maxReaders: \(maxReadersArg), maxDBs: \(maxDBsArg), mode: \(modeArg))\n"
		open += "    let setupTX = try Transaction<Write>(env: env)\n"
		var initArgs: [String] = []
		for member in members {
			for table in member.tables {
				let flagsText = table.extraFlags.map { "QuickLMDB.MDB_db_flags([.create]).union(\($0))" } ?? "[.create]"
				let nameLiteral = table.nameIsExpression ? table.name : "\"\(table.name)\""
				open += "    let \(table.property) = try \(table.type)(env: env, name: \(nameLiteral), flags: \(flagsText), tx: setupTX)\n"
			}
			open += "    let \(member.property) = \(member.typeName)(env: env, \(member.tables.map { "\($0.property): \($0.property)" }.joined(separator: ", ")))\n"
			initArgs.append("\(member.property): \(member.property)")
		}
		open += "    try setupTX.commit()\n"
		open += "    return Self(\(initArgs.joined(separator: ", ")))\n"
		open += "}"
		decls.append(open)

		return decls.map { DeclSyntax(stringLiteral: $0) }
	}
}
