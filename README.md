# ColdStore

A Flutter package that provides three-layer caching for Firestore documents and collections, optimizing data access and offline capabilities.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Detailed Usage](#detailed-usage)
  - [Initialization](#initialization)
  - [Reading Documents](#reading-documents)
  - [Reading Collections](#reading-collections)
  - [Document Properties](#document-properties)
  - [Collection Properties](#collection-properties)
  - [Watching Documents](#watching-documents)
  - [Watching Collections](#watching-collections)
  - [Cache Management](#cache-management)
  - [Cleanup](#cleanup)
  - [Automatic Watching](#automatic-watching)
- [Supported Data Types](#supported-data-types)
- [How it Works](#how-it-works)
- [Best Practices](#best-practices)
- [Example App](#example-app)
- [License](#license)

## Features

- Three-layer caching strategy (Memory → Persistent Storage → Firestore)
- Document and collection caching with query support
- Efficient memory cache for fastest access
- Persistent JSON storage as fallback
- Real-time synchronization with Firestore
- Automatic document/collection watching
- Support for all Firestore data types
- Query result caching
- Simple API for data access

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  coldstore: ^0.1.0
```

## Quick Start

```dart
// Initialize Firebase (required)
await Firebase.initializeApp();

// Create a ColdStore instance
final coldStore = ColdStore();

// Working with documents
final docRef = FirebaseFirestore.instance.doc('users/123');
final doc = await coldStore.get(docRef);
if (doc != null && doc.exists) {
  print('Document data: ${doc.data()}');
}

// Working with collections
final usersRef = FirebaseFirestore.instance.collection('users');
final snapshot = await coldStore.getCollection(usersRef);
for (var doc in snapshot.docs) {
  print('User ${doc.id}: ${doc.data()}');
}

// Using queries
final activeUsers = await coldStore.getCollection(
  usersRef.where('active', isEqualTo: true)
);

// Watch collections for changes
await coldStore.watchCollection(usersRef);

// Clean up when done
await coldStore.dispose();
```

## Detailed Usage

### Initialization

```dart
// Default initialization with auto-watching enabled
final coldStore = ColdStore();

// Disable automatic watching if needed
final coldStore = ColdStore(autoWatch: false);

// With custom Firestore instance
final customFirestore = FirebaseFirestore.instance;
final coldStore = ColdStore(firestore: customFirestore);
```

### Reading Documents

```dart
final docRef = FirebaseFirestore.instance.doc('users/123');

// Get document (automatically starts watching for changes)
final doc = await coldStore.get(docRef);

// Check if document exists
if (doc != null && doc.exists) {
  // Access document data and metadata
  final data = doc.data();
  final docId = doc.id;
  final docRef = doc.reference;
}
```

### Reading Collections

```dart
final collectionRef = FirebaseFirestore.instance.collection('users');

// Get all documents in a collection
final snapshot = await coldStore.getCollection(collectionRef);
print('Found ${snapshot.size} documents');

// Access documents
for (var doc in snapshot.docs) {
  print('${doc.id}: ${doc.data()}');
}

// Using queries
final activeUsers = await coldStore.getCollection(
  collectionRef.where('active', isEqualTo: true)
);

final recentUsers = await coldStore.getCollection(
  collectionRef
    .where('lastActive', isGreaterThan: Timestamp.now())
    .orderBy('lastActive', descending: true)
    .limit(10)
);
```

### Document Properties

ColdStoreDocument provides an interface similar to Firestore's DocumentSnapshot:

- `id` - The document's ID (last component of the path)
- `exists` - Whether the document exists in Firestore
- `reference` - The DocumentReference pointing to this document
- `data()` - Method to get the document's data

### Collection Properties

ColdStoreQuerySnapshot provides an interface similar to Firestore's QuerySnapshot:

- `docs` - List of documents in the collection
- `empty` - Whether the collection is empty
- `size` - The number of documents in the collection

### Watching Documents

```dart
// Manual watching (not needed if autoWatch is true)
await coldStore.watch(docRef);

// Stop watching when no longer needed
await coldStore.unwatch(docRef);
```

### Watching Collections

```dart
// Start watching a collection
await coldStore.watchCollection(collectionRef);

// With query
final activeUsersQuery = collectionRef.where('active', isEqualTo: true);
await coldStore.watchCollection(activeUsersQuery);

// Stop watching when no longer needed
await coldStore.unwatchCollection(collectionRef);
```

### Cache Management

```dart
// Clear cache for a specific document
await coldStore.clear(docRef);

// Clear all cached data (documents and collections)
await coldStore.clear(null);
```

### Cleanup

```dart
// Always dispose when done to prevent memory leaks
// This will clean up both document and collection watchers
await coldStore.dispose();
```

### Automatic Watching

By default, ColdStore automatically starts watching any document or collection that you access. This means:

1. First call to `get()` or `getCollection()`:

   - Retrieves data from cache or Firestore
   - Sets up a real-time listener for changes
   - Future changes are automatically synced to cache

2. Subsequent calls:

   - Return cached data immediately
   - Cache is always up-to-date due to background watching

3. Benefits:

   - Simpler API - no need to manually call watch methods
   - Ensures data stays fresh
   - Prevents missed updates
   - Optimizes Firestore usage

4. Control:
   - Disable with `ColdStore(autoWatch: false)`
   - Manually control with watch/unwatch methods
   - All watchers cleaned up on `dispose()`

## Supported Data Types

ColdStore automatically handles all Firestore data types:

- Timestamps
- GeoPoints
- DocumentReferences
- Arrays
- Maps/Objects
- Nested combinations of the above

## How it Works

ColdStore implements a three-layer caching strategy for both documents and collections:

1. **Memory Cache (Layer 1)**

   - Fastest access
   - Holds recently accessed documents and query results
   - Cleared when app is terminated

2. **Persistent Storage (Layer 2)**

   - JSON files stored on device
   - Survives app restarts
   - Provides offline access
   - Separate storage for documents and collections

3. **Firestore (Layer 3)**
   - Source of truth
   - Accessed only when needed
   - Real-time updates via watchers

Data flow:

1. When requesting data, checks memory cache first
2. If not found, checks persistent storage
3. If not found, fetches from Firestore
4. When watching, updates flow from Firestore → Memory → Persistent Storage

## Best Practices

1. **Initialization**

   - Create a single ColdStore instance for your app
   - Initialize early in your app lifecycle

2. **Document Access**

   - Use the document interface consistently
   - Check document.exists before accessing data
   - Keep document references if you need to update

3. **Collection Access**

   - Use queries consistently to ensure proper cache hits
   - Consider pagination for large collections
   - Watch collections you need to keep synchronized

4. **Query Caching**

   - Each unique query combination is cached separately
   - Reuse query references when possible
   - Clear cache if query conditions change significantly

5. **Document Watching**

   - Watch documents you need to keep synchronized
   - Unwatch when the data is no longer needed
   - Consider using StatefulWidget's initState/dispose

6. **Resource Management**

   - Dispose of ColdStore instances when no longer needed
   - Unwatch collections that are not currently visible
   - Use clear() selectively to manage cache size

7. **Cache Management**

   - Clear specific document caches when data becomes stale
   - Use full cache clear sparingly

8. **Offline Support**

   - Test your app in airplane mode
   - Handle both cached and fresh data gracefully
   - Consider implementing retry logic for failed operations

9. **Cleanup**
   - Always call dispose() when done with ColdStore
   - Particularly important in temporary screens/widgets

## Example App

Check out the [example](example) directory for a complete sample application demonstrating:

- User profile management
- Document metadata access
- Real-time updates
- Cache management
- Proper lifecycle handling

## License

MIT
