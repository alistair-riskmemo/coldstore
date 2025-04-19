/// A Flutter package that provides three-layer caching for Firestore documents and collections.
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
/// // Working with documents
/// final docRef = FirebaseFirestore.instance.doc('users/123');
/// final doc = await coldStore.get(docRef);
/// if (doc != null && doc.exists) {
///   print('Document data: ${doc.data()}');
/// }
///
/// // Working with collections
/// final usersRef = FirebaseFirestore.instance.collection('users');
/// final snapshot = await coldStore.getCollection(usersRef);
/// for (var doc in snapshot.docs) {
///   print('User ${doc.id}: ${doc.data()}');
/// }
///
/// // Using queries
/// final activeUsers = await coldStore.getCollection(
///   usersRef.where('active', isEqualTo: true)
/// );
///
/// // Watch collections for changes
/// await coldStore.watchCollection(usersRef);
///
/// // Clear cache when done
/// await coldStore.clear(null);
/// ```
///
/// The package handles all Firestore data types including:
/// - Timestamps
/// - GeoPoints
/// - DocumentReferences
/// - Arrays and nested objects
///
/// No additional setup is required beyond Firebase initialization.
library;

export 'src/coldstore_base.dart'
    show ColdStore, ColdStoreDocument, ColdStoreQuerySnapshot;
