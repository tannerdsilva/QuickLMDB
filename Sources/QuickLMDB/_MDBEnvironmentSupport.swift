import CLMDB
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// tiny macro support surface for `@MDB_environment`'s generated `open(at:)`
// factory. contains no transaction logic — just the stat-based file-size probe
// and directory creation that the generated schema open needs (Foundation-free,
// so generated consumer code has no import requirements beyond the Swift
// standard library).

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

	/// joins two path components with exactly one separator, tolerating a trailing
	/// slash on the base. used by the generated container `open(at:)` to build each
	/// core's subdirectory.
	public static func __joinPath(_ base:String, _ component:String) -> String {
		if base.isEmpty { return component }
		if base.hasSuffix("/") { return base + component }
		return base + "/" + component
	}

	/// creates the directory at `path` (and any missing parents) when it does not
	/// already exist. returns true when the directory is present afterwards.
	/// used by the generated container `open(at:)` for the per-core subdirectories.
	public static func __createDirectory(at path:String) -> Bool {
		// mkdir -p semantics by walking the path forward; stops at an existing dir
		let absolute = path.hasPrefix("/") ? path : "/" + path
		let components = absolute.split(separator: "/", omittingEmptySubsequences: true)
		var current = ""
		for component in components {
			current = current.isEmpty ? "/" + component : current + "/" + component
			let isDir = current.withCString { cPath in
				var statBuffer = stat()
				if stat(cPath, &statBuffer) == 0 {
					return statBuffer.st_mode & S_IFMT == S_IFDIR
				}
				return false
			}
			if isDir { continue }
			let mkdirResult = current.withCString { cPath in mkdir(cPath, S_IRWXU | S_IRWXG | S_IRWXO) }
			if mkdirResult != 0 && errno != EEXIST {
				return false
			}
		}
		return true
	}
}
