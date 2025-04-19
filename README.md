# ColdStore

A Flutter package that provides three-layer caching for Firestore documents, optimizing data access and offline capabilities.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Detailed Usage](#detailed-usage)
  - [Initialization](#initialization)
  - [Reading Documents](#reading-documents)
  - [Document Properties](#document-properties)
  - [Watching Documents](#watching-documents)
  - [Cache Management](#cache-management)
  - [Cleanup](#cleanup)
  - [Automatic Document Watching](#automatic-document-watching)
- [Supported Data Types](#supported-data-types)
- [How it Works](#how-it-works)
- [Best Practices](#best-practices)
- [Example App](#example-app)
- [License](#license)

## Features

- Three-layer caching strategy (Memory → Persistent Storage → Firestore)
- Document interface matching Firestore's DocumentSnapshot
- Automatic document syncing with Firestore
- Automatic document watching for accessed documents
- Efficient memory cache for fastest access
- Persistent JSON storage as fallback
- No external database dependencies
- Support for all Firestore data types
- Simple API for document access

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

// Get a document reference
final docRef = FirebaseFirestore.instance.doc('users/123');

// Get document data - automatically starts watching for changes
final doc = await coldStore.get(docRef);
if (doc != null && doc.exists) {
  print('Document ID: ${doc.id}');
  print('Document data: ${doc.data()}');
}

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

### Document Properties

ColdStoreDocument provides an interface similar to Firestore's DocumentSnapshot:

- `id` - The document's ID (last component of the path)
- `exists` - Whether the document exists in Firestore
- `reference` - The DocumentReference pointing to this document
- `data()` - Method to get the document's data

### Watching Documents

```dart
// Manual watching (not needed if autoWatch is true)
await coldStore.watch(docRef);

// Stop watching when no longer needed
await coldStore.unwatch(docRef);
```

### Cache Management

```dart
// Clear cache for a specific document
await coldStore.clear(docRef);

// Clear all cached data
await coldStore.clear(null);
```

### Cleanup

```dart
// Always dispose when done to prevent memory leaks
await coldStore.dispose();
```

### Automatic Document Watching

By default, ColdStore automatically starts watching any document that you access via the `get()` method. This means:

1. First call to `get()` for a document:

   - Retrieves document from cache or Firestore
   - Sets up a real-time listener for changes
   - Future changes are automatically synced to cache

2. Subsequent calls to `get()` for the same document:

   - Return cached document immediately
   - Cache is always up-to-date due to background watching

3. Benefits:

   - Simpler API - no need to manually call `watch()`
   - Ensures data stays fresh
   - Prevents missed updates
   - Optimizes Firestore usage

4. Control:
   - Disable with `ColdStore(autoWatch: false)`
   - Manually control with `watch()` and `unwatch()`
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

ColdStore implements a three-layer caching strategy:

1. **Memory Cache (Layer 1)**

   - Fastest access
   - Holds recently accessed documents
   - Cleared when app is terminated

2. **Persistent Storage (Layer 2)**

   - JSON files stored on device
   - Survives app restarts
   - Provides offline access

3. **Firestore (Layer 3)**
   - Source of truth
   - Accessed only when needed
   - Real-time updates via watchers

Data flow:

1. When requesting a document, checks memory cache first
2. If not found, checks persistent storage
3. If not found, fetches from Firestore
4. When watching documents, updates flow from Firestore → Memory → Persistent Storage

## Best Practices

1. **Initialization**

   - Create a single ColdStore instance for your app
   - Initialize early in your app lifecycle

2. **Document Access**

   - Use the document interface consistently
   - Check document.exists before accessing data
   - Keep document references if you need to update

3. **Document Watching**

   - Watch documents you need to keep synchronized
   - Unwatch when the data is no longer needed
   - Consider using StatefulWidget's initState/dispose

4. **Cache Management**

   - Clear specific document caches when data becomes stale
   - Use full cache clear sparingly

5. **Cleanup**
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
