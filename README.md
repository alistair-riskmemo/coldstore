# ColdStore

A Flutter package that provides a three-layer caching system for Firestore documents, optimizing data access and offline capabilities.

## Features

- Three-layer caching strategy (Memory → Persistent Storage → Firestore)
- Automatic document syncing with Firestore
- Efficient memory cache for fastest access
- Persistent JSON storage as fallback
- No external database dependencies
- Simple API for document watching and retrieval

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  coldstore: ^0.1.0
```

## Usage

```dart
// Initialize ColdStore
final coldStore = ColdStore();

// Start watching a document
await coldStore.watch('users/123');

// Get document data (checks cache layers automatically)
final userData = await coldStore.getData('users/123');

// Data is automatically kept in sync with Firestore
// and stored in both memory and persistent storage

// Stop watching when done
await coldStore.unwatch('users/123');

// Clear cache for specific document
await coldStore.clearCache('users/123');

// Clear all cache
await coldStore.clearCache(null);

// Dispose when done
await coldStore.dispose();
```

## How it works

ColdStore implements a three-layer caching strategy:

1. Memory Cache: Fastest access, holds recently accessed documents
2. Persistent Storage: JSON files stored on device for offline access
3. Firestore: Source of truth, accessed only when needed

When requesting data:

- First checks memory cache
- If not found, checks persistent storage
- If not found, fetches from Firestore

When watching documents:

- Updates memory cache and persistent storage automatically
- Maintains subscription to Firestore changes
- Ensures data consistency across all layers

## License

MIT
