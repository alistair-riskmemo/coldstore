# Changelog

## 0.1.2 - 2025-07-30

### Changed

- Updated Firebase dependencies to latest versions
  - Firebase Core ^4.0.0 (previously ^2.24.2)
  - Cloud Firestore ^6.0.0 (previously ^4.14.0)
  - Path Provider ^2.1.5 (previously ^2.1.2)

## 0.1.0 - 2025-04-18

### Added

- Initial release with three-layer caching system
- DocumentReference-based API for type-safe operations
- Support for all Firestore data types (Timestamp, GeoPoint, DocumentReference)
- Memory caching layer for fast access
- Persistent JSON storage for offline capability
- Automatic document watching and syncing
- Clear API for cache management
- Comprehensive documentation and examples
- Cache size management with configurable limits (100MB default)
- Cache usage monitoring and statistics
- Tools for inspecting cached documents and collections
- Cache usage threshold warnings
- Automatic cleanup of old cache entries

### Breaking Changes

None (initial release)

### Dependencies

- Requires Flutter SDK >=3.0.0
- Firebase Core ^2.24.2
- Cloud Firestore ^4.14.0
- Path Provider ^2.1.2

## 1.0.0

- Initial version.
