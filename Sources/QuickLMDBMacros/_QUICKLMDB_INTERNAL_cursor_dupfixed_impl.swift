import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

#if QUICKLMDB_MACRO_LOG
import Logging
fileprivate let logger = makeDefaultLogger(label:"RAW_function_add_transaction_macro")
fileprivate func makeDefaultLogger(label:String) -> Logger {
	var logger = Logger(label:label)
	logger.logLevel = .debug
	return logger
}
#endif

/// this macro needs to exist beceause the implemented functions cannot be marked as borrowing when used as a member of a protocol
internal struct _QUICKLMDB_INTERNAL_cursor_dupfixed_impl:MemberMacro {
	static func expansion(of node:SwiftSyntax.AttributeSyntax, providingMembersOf declaration:some SwiftSyntax.DeclGroupSyntax, in context:some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
		return [
			DeclSyntax("""
				public borrowing func opGetMultiple(returning:[MDB_cursor_dbtype.MDB_db_val_type].Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws -> [MDB_cursor_dbtype.MDB_db_val_type] {
					try key.MDB_access { (keyVal:consuming MDB_val) in
						var valueVal = MDB_val.uninitialized()

						#if DEBUG
						let keyPtr = keyVal.mv_data
						let valuePtr = valueVal.mv_data
						#endif

						try MDB_cursor_get_entry_static(cursor:self, .getMultiple, key:&keyVal, value:&valueVal)

						#if DEBUG
						assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
						assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
						assert(valueVal.mv_size % MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_staticbuff_storetype>.size == 0, "value buffer must be evenly divisible by the expected size of the value type")
						assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
						#endif

						return [MDB_cursor_dbtype.MDB_db_val_type](unsafeUninitializedCapacity:(valueVal.mv_size / MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_staticbuff_storetype>.size), initializingWith: { buff, count in
							var dataSeeker = UnsafeRawPointer(valueVal.mv_data)!
							while valueVal.mv_size > 0 {
								buff[count] = MDB_cursor_dbtype.MDB_db_val_type(RAW_staticbuff_seeking:&dataSeeker)
								valueVal.mv_size -= MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_staticbuff_storetype>.size
								count += 1
							}
						})
					}
				}
			"""),
			DeclSyntax("""
				public borrowing func opNextMultiple(returning:[MDB_cursor_dbtype.MDB_db_val_type].Type, key:borrowing MDB_cursor_dbtype.MDB_db_key_type) throws -> [MDB_cursor_dbtype.MDB_db_val_type] {
					try key.MDB_access { (keyVal:consuming MDB_val) in
						var valueVal = MDB_val.uninitialized()

						#if DEBUG
						let keyPtr = keyVal.mv_data
						let valuePtr = valueVal.mv_data
						#endif

						try MDB_cursor_get_entry_static(cursor:self, .nextMultiple, key:&keyVal, value:&valueVal)

						#if DEBUG
						assert(keyPtr != keyVal.mv_data, "key buffer was not modified so it cannot be returned")
						assert(valueVal.mv_size != -1, "value buffer was not modified so it cannot be returned")
						assert(valueVal.mv_size % MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_staticbuff_storetype>.size == 0, "value buffer must be evenly divisible by the expected size of the value type")
						assert(valuePtr != valueVal.mv_data, "value buffer was not modified so it cannot be returned")
						#endif

						var dataSeeker = UnsafeRawPointer(valueVal.mv_data)!
						return [MDB_cursor_dbtype.MDB_db_val_type](unsafeUninitializedCapacity:(valueVal.mv_size / MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_staticbuff_storetype>.size), initializingWith: { buff, count in
							while valueVal.mv_size > 0 {
								buff[count] = MDB_cursor_dbtype.MDB_db_val_type(RAW_staticbuff_seeking:&dataSeeker)
								valueVal.mv_size -= MemoryLayout<MDB_cursor_dbtype.MDB_db_val_type.RAW_staticbuff_storetype>.size
								count += 1
							}
						})
					}
				}
			""")
		]
	}
}