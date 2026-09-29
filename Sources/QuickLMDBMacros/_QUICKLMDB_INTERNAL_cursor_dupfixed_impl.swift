import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// this macro needs to exist beceause the implemented functions cannot be marked as borrowing when used as a member of a protocol
internal struct _QUICKLMDB_INTERNAL_cursor_dupfixed_impl:MemberMacro {
	static func expansion(of node:SwiftSyntax.AttributeSyntax, providingMembersOf declaration:some SwiftSyntax.DeclGroupSyntax, conformingTo protocols:[TypeSyntax], in context:some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
		return [
			DeclSyntax("""
				@available(*, noasync)
				public borrowing func opGetMultiple(returning:[MDB_cursor_dbtype.MDB_db_val_type].Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws(LMDBError) -> [MDB_cursor_dbtype.MDB_db_val_type] {
					try key.MDB_access { (keyVal:consuming MDB_val) throws(LMDBError) -> [MDB_cursor_dbtype.MDB_db_val_type] in
						let valueVal = MDB_val.uninitialized()

						#if DEBUG
						let keyPtr = keyVal.mv_data
						let valuePtr = valueVal.mv_data
						#endif

						let entry = try MDB_cursor_get_entry(cursor:self.cursorHandle(), op:Operation.getMultiple.mdbValue, key:keyVal, value:valueVal)

						#if DEBUG
						assert(keyPtr != entry.key.mv_data, "key buffer was not modified so it cannot be returned")
						assert(entry.value.mv_size != -1, "value buffer was not modified so it cannot be returned")
						assert(entry.value.mv_size % MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_fixed_type>.size == 0, "value buffer must be evenly divisible by the expected size of the value type")
						assert(valuePtr != entry.value.mv_data, "value buffer was not modified so it cannot be returned")
						#endif

						var outVal = entry.value
						return [MDB_cursor_dbtype.MDB_db_val_type](unsafeUninitializedCapacity:(outVal.mv_size / MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_fixed_type>.size), initializingWith: { buff, count in
							var dataSeeker = UnsafeRawPointer(outVal.mv_data)!
							while outVal.mv_size > 0 {
								buff[count] = MDB_cursor_dbtype.MDB_db_val_type(RAW_staticbuff_seeking:&dataSeeker)
								outVal.mv_size -= MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_fixed_type>.size
								count += 1
							}
						})
					}
				}
			"""),
			DeclSyntax("""
				@available(*, noasync)
				public borrowing func opNextMultiple(returning:[MDB_cursor_dbtype.MDB_db_val_type].Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws(LMDBError) -> [MDB_cursor_dbtype.MDB_db_val_type] {
					try key.MDB_access { (keyVal:consuming MDB_val) throws(LMDBError) -> [MDB_cursor_dbtype.MDB_db_val_type] in
						let valueVal = MDB_val.uninitialized()

						#if DEBUG
						let keyPtr = keyVal.mv_data
						let valuePtr = valueVal.mv_data
						#endif

						let entry = try MDB_cursor_get_entry(cursor:self.cursorHandle(), op:Operation.nextMultiple.mdbValue, key:keyVal, value:valueVal)

						#if DEBUG
						assert(keyPtr != entry.key.mv_data, "key buffer was not modified so it cannot be returned")
						assert(entry.value.mv_size != -1, "value buffer was not modified so it cannot be returned")
						assert(entry.value.mv_size % MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_fixed_type>.size == 0, "value buffer must be evenly divisible by the expected size of the value type")
						assert(valuePtr != entry.value.mv_data, "value buffer was not modified so it cannot be returned")
						#endif

						var outVal = entry.value
						return [MDB_cursor_dbtype.MDB_db_val_type](unsafeUninitializedCapacity:(outVal.mv_size / MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_fixed_type>.size), initializingWith: { buff, count in
							var dataSeeker = UnsafeRawPointer(outVal.mv_data)!
							while outVal.mv_size > 0 {
								buff[count] = MDB_cursor_dbtype.MDB_db_val_type(RAW_staticbuff_seeking:&dataSeeker)
								outVal.mv_size -= MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_fixed_type>.size
								count += 1
							}
						})
					}
				}
			""")
		]
	}
}