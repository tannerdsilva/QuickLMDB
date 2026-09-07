import CLMDB
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// tiny macro support surface for `@MDB_environment`'s generated `open(at:)`.
// contains no transaction logic — just the stat-based file-size probe that the
// generated schema-open needs (Foundation-free, so generated consumer code has no
// import requirements beyond the Swift standard library).

/// the macro support surface for `@MDB_environment`.
/// - note: underscored public names are not user-facing API; they exist only so
///   macro-generated code in the consuming module can reference them.
public enum _MDBEnvironmentSupport {

	/// returns the size in bytes of the file at `path`, or 0 when the file does not
	/// exist or cannot be read. used by the generated `open(at:)` map-sizing logic.
	public static func __fileSize(at path:String) -> UInt64 {
		return path.withCString { cPath in
			var statBuffer = stat()
			guard stat(cPath, &statBuffer) == 0 else {
				return 0
			}
			return UInt64(statBuffer.st_size)
		}
	}
}
