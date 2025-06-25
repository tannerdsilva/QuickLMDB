# 11.0.0

- Dropped `QuickLMDB.CursorAccessError` error type from the cursor access function. Now in v11, errors thrown within the cursor handler block will be transparently thrown (aka rethrows, but type strict). Any errors encountered in creating the cursor before the handler is called will result in a fatal error.

# 10.0.0

- Any LMDB function that associates with an active `Transaction` has now been marked as `@available(*, noasync)` to guarantee safe thread-local usage. While LMDB offers a `.noTLS` flag, it only applies to read transactions. As such, LMDB is always using TLS to some extent or another, and as such, this `noasync` requirement is most optimal to ensure safe usage in all contexts.

- Elimination of integrated logging functions. More effort to support this than it was worth. On the upside, one less dependency to rely on for building this project.

### 9.0.1

- Also supporting `rawdog` v17.

# 9.0.0

- `rawdog` requirement is now v16.

# 8.0.1

- Will also support `rawdog` v17 in addition to v16.

# 8.0.0

- Revised `MDB_db` protocol.

	- Improved clarity on thrown errors for `cursor` function.
	
- Revised `Transaction` to throw strict error types.

# 7.0.0

- PackageDescription and encompassing source code is now strictly Swift 6.

- No longer `throws` any type. Every function within the core API of QuickLMDB now throws a strict type.

# 6.0.0

- Updated PackageDescription to require rawdog v13 or above. This is considered a breaking change because rawdog v13 requires sendable on RAW_staticbuff and this cannot be applied automatically by the macro.

### 5.0.1

- Updated PackageDescription to include rawdog v12 within the supported scope.

# 5.0.0

- Another relatively small "breaking change". This update restores the correct return type on `Database.loadEntry` function. Since any type may be stored in a general (non-strcit) database, the decoding of any given type may fail, hence the need for a nullable return type.

# 4.0.0

- This update does not change any code in the QuickLMDB project, however, it modifies the requirements of its sister project `rawdog`, moving from `10.1.0..<11.0.0` of QuickLMDB v3 to `11.0.0...` in this v4 release.

	- `rawdog` v11 is in itself a negligibly small "major release", as it is identical to the outgoing v10, only adding Sendable conformance to a few key protocols to make the framework more friendly for concurrent applications.

- In light of the above, QuickLMDB 4.0.0 can be seen as a "Sendable friendly" re-release of QuickLMDB v3. This version is only being tagged as a major release to keep in line with the SemVer semantics and the breaking changes that this new Sendable requirement in `rawdog` entails.

# 3.0.0

- Revised the structure of various protocols and extensions to make it less easy to pass a type into a struct Database or Cursor.

- Now requires ``rawdog`` version `10.1.0` or later.

- Full documentation coming soon.

# 2.0.0

- Foundation-free implementation.

- Introduction of ``changelog.md`` to document the changes to this library over time.

- Eliminates all default implementations for serialization. QuickLMDB 2.0.0 leaves the serialization techniques entirely up to the developer.

- Added peer dependency ``rawdog``, a sophisticated library for defining how types serialize into portable binary formats with minimal copies (and code) in between.

	- Dependencies for QuickLMDB are deeply scrutinized and considered. ``rawdog`` is being added not only because of the functionality it provides for developers, but also because it was forged from this very library in many ways. rawdog started as a way for me to use MDB_val-like structures in other projects, and quickly grew to become the "final word" on native binary handling in Swift (imo ofc). The amount of work and code required to reach this point spanned far beyond the code I would ever expect QuickLMDB to take on, which is why it is being added as a dependency here.

	- In light of the removal of the built-in serialiation extensions of prior releases, QuickLMDB now offers ``rawdog`` as the answer to defining how abstract types transcode to the database as binary.

	- By committing to use QuickLMDB in v2.x.x and beyond, you are making an equal commitment to use ``rawdog`` library for serialization. Plan your development accordingly.

- Eliminated optional transactions on all argument types.

- Introduction of attached macro ``MDB_comparable`` which applies the native ``RAW_comparable`` protocol of rawdog into c convention funcs that LMDB can use for native sorting.

	- ``MDB_comparable``

- High-level naming scheme for arguments (mostly in ``Database`` and ``Cursor`` types) has changed to simple "key" | "value" names. While the previous naming scheme was arguably more aligned with the cultured naming conventions found in the Swift ecosystem, this change is being made in the name of simplicity and in preparation for more complex syntax macros in future releases.

- Introduction of database variants `Strict`, `DupFixed` and `DupSort` (and their respective protocols) that help enforce safe and efficient use of flag-variant databases using type safety.

	- Corresponding cursor variants to match.

- This tag is not completely documented and will see further coverage in the coming releases.