import CLMDB
import Foundation
import QuickLMDBFunctionalInterop
import Testing

// ground truth for THIS liblmdb build's nested-transaction rules — whatever
// mdb.c's mdb_txn_begin actually enforces. the vendored 1.0.2 source is explicit:
//   /* Nested transactions:
//    * Only write txns may have nested txns;
//    * if the nested txn is a write txn there may only be 1, no writemap;
//    * if the nested txn is a read txn there may be arbitrarily many.
//    */
//   if (parent->mt_flags & MDB_TXN_RDONLY)
//       return EINVAL;
//   if ((parent->mt_flags & MDB_TXN_WRITEMAP) && !(flags & MDB_RDONLY))
//       return EINVAL;
// these pins freeze the OBSERVED behavior so a liblmdb upgrade that changes
// it fails loudly. (0.9 rejected read-only children with MDB_BAD_TXN — 1.0
// lifted that restriction; this file tracks the 1.0 contract.)

@Suite("raw nested-transaction semantics (this liblmdb build)")
struct NestedTxnSemanticsProbe {

	@Test func readOnlyChildOfWriteParentIsLegal() throws {
		let env = try RawEnv()
		var parent: OpaquePointer? = nil
		try throwRaw(mdb_txn_begin(env.env, nil, 0, &parent), "write parent")

		// 1.0 allows arbitrarily many read-only children of a write parent
		var readChild: OpaquePointer? = nil
		try throwRaw(mdb_txn_begin(env.env, parent, UInt32(MDB_RDONLY), &readChild), "read-only child of write parent")
		#expect(readChild != nil)

		mdb_txn_abort(readChild)
		mdb_txn_abort(parent)
	}

	@Test func writeChildOfWriteParentIsLegal() throws {
		let env = try RawEnv()
		var parent: OpaquePointer? = nil
		try throwRaw(mdb_txn_begin(env.env, nil, 0, &parent), "write parent")
		var child: OpaquePointer? = nil
		try throwRaw(mdb_txn_begin(env.env, parent, 0, &child), "write child of write parent")
		mdb_txn_abort(child)
		mdb_txn_abort(parent)
	}

	@Test func anyChildOfReadOnlyParentIsRejected() throws {
		let env = try RawEnv()
		var readParent: OpaquePointer? = nil
		try throwRaw(mdb_txn_begin(env.env, nil, UInt32(MDB_RDONLY), &readParent), "read parent")

		var writeChild: OpaquePointer? = nil
		let rc = mdb_txn_begin(env.env, readParent, 0, &writeChild)
#if os(Linux)
		#expect(rc == Glibc.EINVAL, "a child of a READ-ONLY parent must be EINVAL, got \(rc)")
#else
		#expect(rc == Darwin.EINVAL, "a child of a READ-ONLY parent must be EINVAL, got \(rc)")
#endif
		mdb_txn_abort(readParent)
	}
}
