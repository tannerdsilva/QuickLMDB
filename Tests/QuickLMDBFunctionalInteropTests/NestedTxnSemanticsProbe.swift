import CLMDB
import Foundation
import QuickLMDBFunctionalInterop
import Testing

// ground truth for THIS liblmdb build's nested-transaction rules — whatever
// mdb.c's mdb_txn_begin actually enforces. the vendored source is explicit:
//   /* Nested transactions: Max 1 child, write txns only, no writemap */
//   if (flags & (MDB_RDONLY|MDB_WRITEMAP|MDB_TXN_BLOCKED))
//       return (parent->mt_flags & MDB_TXN_RDONLY) ? EINVAL : MDB_BAD_TXN;
// these pins freeze the OBSERVED behavior so a liblmdb upgrade that changes
// it fails loudly.

@Suite("raw nested-transaction semantics (this liblmdb build)")
struct NestedTxnSemanticsProbe {

	@Test func readOnlyChildOfWriteParentIsRejected() throws {
		let env = try RawEnv()
		var parent: OpaquePointer? = nil
		try throwRaw(mdb_txn_begin(env.env, nil, 0, &parent), "write parent")

		var readChild: OpaquePointer? = nil
		let rc = mdb_txn_begin(env.env, parent, UInt32(MDB_RDONLY), &readChild)
		#expect(rc == MDB_BAD_TXN, "a read-only child of a WRITE parent must be MDB_BAD_TXN, got \(rc)")
		#expect(readChild == nil)

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
