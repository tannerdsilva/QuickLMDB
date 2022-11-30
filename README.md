# QuickLMDB

QuickLMDB is designed to be a easy, efficient, and uncompromising integration of the LMDB library. QuickLMDB does not hide access to the underlying LMDB core, allowing you to directly utilize the core LMDB API at any time. Likewise, QuickLMDB makes it very easy to write high-level code that is simultaneously memory-safe and high-performance. 

- QuickLMDB is the only known Swift library to allow full transactional control over an Environment. This is crucial to achieving high performance.

- QuickLMDB allows direct access to the LMDB memorymap without overhead or copies. This is also a unique feature for Swift-based LMDB wrappers.

## Full Documentation

QuickLMDB is fully documented. This documentation is available [HERE](https://quicklmdb.com/documentation). Documentation may be generated from source using `swift-docc`.

## Compatibility

QuickLMDB is fully supported on all platforms capable of running Swift, including:

- Linux

- MacOS

- iOS

## License

QuickLMDB is available with an MIT license.

LMDB is included with QuickLMDB with an OpenLDAP license.
