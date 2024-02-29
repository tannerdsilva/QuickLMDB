import QuickLMDBMacros

@attached(member,		names:			named(MDB_compare_f))
@attached(extension,	conformances:	MDB_comparable)
public macro MDB_comparable() = #externalMacro(module:"QuickLMDBMacros", type:"MDB_comparable_macro")

@attached(member,		names:			arbitrary)
internal macro MDB_cursor_impl() = #externalMacro(module:"QuickLMDBMacros", type:"MDB_cursor_impl_macro")