# ColdStore

A Flutter package that provides three-layer caching for Firestore documents, optimizing data access and offline capabilities.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Detailed Usage](#detailed-usage)
  - [Initialization](#initialization)
  - [Reading Data](#reading-data)
  - [Watching Documents](#watching-documents)
  - [Cache Management](#cache-management)
  - [Cleanup](#cleanup)
- [Supported Data Types](#supported-data-types)
- [How it Works](#how-it-works)
- [Best Practices](#best-practices)
- [Example App](#example-app)
- [License](#license)

## Features

- Three-layer caching strategy (Memory → Persistent Storage → Firestore)
- Automatic document syncing with Firestore
- Efficient memory cache for fastest access
- Persistent JSON storage as fallback
- No external database dependencies
- Support for all Firestore data types
- Simple API for document watching and retrieval

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

// Start watching the document
await coldStore.watch(docRef);

// Get document data (checks all cache layers)
final userData = await coldStore.get(docRef);

// Clean up when done
await coldStore.dispose();
```

## Detailed Usage

### Initialization

```dart
// Default initialization
final coldStore = ColdStore();

// With custom Firestore instance
final customFirestore = FirebaseFirestore.instance;
final coldStore = ColdStore(firestore: customFirestore);
```

### Reading Data

```dart
final docRef = FirebaseFirestore.instance.doc('users/123');

// Get data (checks memory → persistent storage → Firestore)
final data = await coldStore.get(docRef);
```

### Watching Documents

```dart
// Start watching
await coldStore.watch(docRef);

// Document changes will automatically update both memory and persistent cache

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

1. When requesting data, checks memory cache first
2. If not found, checks persistent storage
3. If not found, fetches from Firestore
4. When watching documents, updates flow from Firestore → Memory → Persistent Storage

## Best Practices

1. **Initialization**

   - Create a single ColdStore instance for your app
   - Initialize early in your app lifecycle

2. **Document Watching**

   - Watch documents you need to keep synchronized
   - Unwatch when the data is no longer needed
   - Consider using StatefulWidget's initState/dispose

3. **Cache Management**

   - Clear specific document caches when data becomes stale
   - Use full cache clear sparingly

4. **Cleanup**
   - Always call dispose() when done with ColdStore
   - Particularly important in temporary screens/widgets

## Example App

Check out the [example](example) directory for a complete sample application demonstrating:

- User profile management
- Real-time updates
- Cache management
- Proper lifecycle handling

## License

MIT
