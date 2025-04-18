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
/// final docRef = FirebaseFirestore.instance.doc('users/123');
///
/// // Start watching a document
/// await coldStore.watch(docRef);
///
/// // Get document data (checks cache layers automatically)
/// final userData = await coldStore.get(docRef);
///
/// // Data is automatically kept in sync with Firestore
/// // and stored in both memory and persistent storage
///
/// // Clear cache for a specific document
/// await coldStore.clear(docRef);
///
/// // Or clear all cached data
/// await coldStore.clear(null);
///
/// // Stop watching when done
/// await coldStore.unwatch(docRef);
/// ```
///
/// The package handles all Firestore data types including:
/// - Timestamps
/// - GeoPoints
/// - DocumentReferences
/// - Arrays and nested objects
///
/// No additional setup is required beyond Firebase initialization.
library coldstore;

export 'src/coldstore_base.dart' show ColdStore;
