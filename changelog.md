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