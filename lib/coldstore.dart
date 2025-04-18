/// A Flutter package that provides three-layer caching for Firestore documents.
///
/// ColdStore implements an efficient caching strategy that allows you to:
/// - Access Firestore data with minimal latency using in-memory cache
/// - Maintain offline persistence using local JSON storage
/// - Automatically sync with Firestore in the background
///
/// Example usage:
/// ```dart
/// final coldStore = ColdStore();
///
/// // Start watching a document
/// await coldStore.watch('users/123');
///
/// // Get document data (checks cache layers automatically)
/// final userData = await coldStore.getData('users/123');
///
/// // Data is automatically kept in sync with Firestore
/// // and stored in both memory and persistent storage
///
/// // Stop watching when done
/// await coldStore.unwatch('users/123');
/// ```
///
/// The package handles all Firestore data types including:
/// - Timestamps
/// - GeoPoints
/// - DocumentReferences
/// - Arrays and nested objects
library coldstore;

export 'src/coldstore_base.dart' show ColdStore;
