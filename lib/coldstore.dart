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
/// // Get document with all metadata
/// final doc = await coldStore.get(docRef);
/// if (doc != null && doc.exists) {
///   // Access document properties
///   print('Document ID: ${doc.id}');
///   print('Document data: ${doc.data()}');
///   print('Document reference: ${doc.reference}');
/// }
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

export 'src/coldstore_base.dart' show ColdStore, ColdStoreDocument;
