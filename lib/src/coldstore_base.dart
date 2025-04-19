import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Represents a cached Firestore document, mirroring the DocumentSnapshot interface.
class ColdStoreDocument {
  /// The document's ID (the last component of the path).
  final String id;

  /// The document's data.
  final Map<String, dynamic>? _data;

  /// Whether the document exists in Firestore.
  final bool exists;

  /// A reference to the document's location in Firestore.
  final DocumentReference reference;

  ColdStoreDocument({
    required this.id,
    required Map<String, dynamic>? data,
    required this.exists,
    required this.reference,
  }) : _data = data;

  /// Gets the document's data, or null if the document doesn't exist.
  Map<String, dynamic>? data() =>
      _data != null ? Map<String, dynamic>.from(_data!) : null;
}

/// Represents a cached collection query result, mirroring QuerySnapshot
class ColdStoreQuerySnapshot {
  /// The documents in the collection that matched the query
  final List<ColdStoreDocument> docs;

  /// Whether the collection is empty
  bool get empty => docs.isEmpty;

  /// The number of documents in the collection
  int get size => docs.length;

  ColdStoreQuerySnapshot({required this.docs});
}

/// A caching layer for Firestore documents that implements a three-tier caching strategy.
///
/// ColdStore provides three layers of data access:
/// 1. Memory cache for fastest access
/// 2. Persistent storage (JSON files) for offline capability
/// 3. Firestore as the source of truth
///
/// Example usage:
/// ```dart
/// final coldStore = ColdStore();
/// final docRef = FirebaseFirestore.instance.doc('users/123');
///
/// // Start watching for changes
/// await coldStore.watch(docRef);
///
/// // Get document (checks all cache layers)
/// final doc = await coldStore.get(docRef);
/// final data = doc?.data();  // Get the document data
/// final userId = doc?.id;    // Get the document ID
///
/// // Clear cache when needed
/// await coldStore.clear(docRef);
///
/// // Clean up when done
/// await coldStore.dispose();
/// ```
class ColdStore {
  /// Default maximum cache size in bytes (100MB)
  static const int _defaultMaxCacheSize = 100 * 1024 * 1024;

  /// In-memory cache storing document data and metadata
  final Map<String, ColdStoreDocument> _memoryCache = {};

  /// Memory cache for collections
  final Map<String, ColdStoreQuerySnapshot> _collectionCache = {};

  /// Active document watchers
  final Map<String, StreamSubscription<DocumentSnapshot>> _listeners = {};

  /// Active collection watchers
  final Map<String, StreamSubscription<QuerySnapshot>> _collectionListeners =
      {};

  /// Set of document paths that are being watched
  final Set<String> _watchedPaths = {};

  /// Set of collection paths that are being watched
  final Set<String> _watchedCollections = {};

  /// The Firestore instance to use
  final FirebaseFirestore _firestore;

  /// Whether to automatically watch documents when they're first accessed
  final bool autoWatch;

  /// Whether the cache size is unlimited
  final bool _cacheSizeUnlimited;

  /// Maximum cache size in bytes
  final int _maxCacheSize;

  /// Current cache size in bytes
  int _currentCacheSize = 0;

  /// Map of file paths to their sizes for cache management
  final Map<String, int> _fileSizes = {};

  /// Creates a new ColdStore instance.
  ///
  /// [firestore] - Optional custom Firestore instance. If not provided,
  /// uses [FirebaseFirestore.instance].
  ///
  /// [autoWatch] - Whether to automatically start watching documents when they're
  /// first accessed via [get]. Defaults to true.
  ///
  /// [cacheSizeUnlimited] - Whether to allow unlimited cache size. Defaults to false.
  ///
  /// [maxCacheSize] - Maximum cache size in bytes. Ignored if cacheSizeUnlimited is true.
  /// Defaults to 100MB.
  ColdStore({
    FirebaseFirestore? firestore,
    this.autoWatch = true,
    bool cacheSizeUnlimited = false,
    int? maxCacheSize,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _cacheSizeUnlimited = cacheSizeUnlimited,
        _maxCacheSize = maxCacheSize ?? _defaultMaxCacheSize {
    _initializeCacheSize();
  }

  /// Gets the storage key for a document reference.
  String _getDocumentKey(DocumentReference docRef) => docRef.path;

  /// Gets the collection cache key
  String _getCollectionKey(Query query) {
    if (query is CollectionReference) {
      return query.path;
    }
    // For queries, include the filters in the cache key
    return '${(query as dynamic).path}_${query.parameters.hashCode}';
  }

  /// Gets the base path for persistent storage.
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return path.join(directory.path, 'coldstore_cache');
  }

  /// Gets the file handle for a document's persistent storage.
  Future<File> _getLocalFile(DocumentReference docRef) async {
    final basePath = await _localPath;
    final sanitizedPath = _getDocumentKey(docRef).replaceAll('/', '_');
    return File(path.join(basePath, '$sanitizedPath.json'));
  }

  /// Gets the file handle for a collection's persistent storage
  Future<File> _getCollectionFile(Query query) async {
    final basePath = await _localPath;
    final sanitizedPath = _getCollectionKey(query).replaceAll('/', '_');
    return File(path.join(basePath, 'collections', '$sanitizedPath.json'));
  }

  /// Converts Firestore data types to JSON-serializable format.
  ///
  /// Handles:
  /// - Timestamps
  /// - GeoPoints
  /// - DocumentReferences
  /// - Arrays (including nested special types)
  /// - Maps/Objects (including nested special types)
  Map<String, dynamic> _convertForStorage(Map<String, dynamic> data) {
    return Map.fromEntries(data.entries.map((entry) {
      var value = entry.value;
      if (value is Timestamp) {
        return MapEntry(entry.key, {
          'type': 'timestamp',
          'seconds': value.seconds,
          'nanoseconds': value.nanoseconds
        });
      } else if (value is GeoPoint) {
        return MapEntry(entry.key, {
          'type': 'geopoint',
          'latitude': value.latitude,
          'longitude': value.longitude
        });
      } else if (value is DocumentReference) {
        return MapEntry(entry.key, {'type': 'reference', 'path': value.path});
      } else if (value is List) {
        return MapEntry(entry.key, {
          'type': 'array',
          'values': value
              .map((e) => e is Map
                  ? _convertForStorage(Map<String, dynamic>.from(e))
                  : e)
              .toList()
        });
      } else if (value is Map) {
        return MapEntry(
            entry.key, _convertForStorage(Map<String, dynamic>.from(value)));
      }
      return MapEntry(entry.key, value);
    }));
  }

  /// Converts stored JSON data back to Firestore types.
  Map<String, dynamic> _convertFromStorage(
      Map<String, dynamic> data, FirebaseFirestore firestore) {
    return Map.fromEntries(data.entries.map((entry) {
      var value = entry.value;
      if (value is Map) {
        final mapValue = Map<String, dynamic>.from(value);
        if (mapValue['type'] == 'timestamp') {
          return MapEntry(entry.key,
              Timestamp(mapValue['seconds'], mapValue['nanoseconds']));
        } else if (mapValue['type'] == 'geopoint') {
          return MapEntry(
              entry.key, GeoPoint(mapValue['latitude'], mapValue['longitude']));
        } else if (mapValue['type'] == 'reference') {
          return MapEntry(entry.key, firestore.doc(mapValue['path']));
        } else if (mapValue['type'] == 'array') {
          return MapEntry(
              entry.key,
              (mapValue['values'] as List)
                  .map((e) => e is Map
                      ? _convertFromStorage(
                          Map<String, dynamic>.from(e), firestore)
                      : e)
                  .toList());
        } else {
          return MapEntry(
              entry.key,
              _convertFromStorage(
                  Map<String, dynamic>.from(mapValue), firestore));
        }
      }
      return MapEntry(entry.key, value);
    }));
  }

  /// Initializes cache size tracking by calculating current cache size
  Future<void> _initializeCacheSize() async {
    if (_cacheSizeUnlimited) return;

    final directory = Directory(await _localPath);
    if (!await directory.exists()) return;

    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        final size = await entity.length();
        _currentCacheSize += size;
        _fileSizes[entity.path] = size;
      }
    }
  }

  /// Updates cache size tracking when adding or removing files
  Future<void> _updateCacheSize(String filePath, int? newSize) async {
    if (_cacheSizeUnlimited) return;

    // Remove old size if file existed
    final oldSize = _fileSizes[filePath];
    if (oldSize != null) {
      _currentCacheSize -= oldSize;
      _fileSizes.remove(filePath);
    }

    // Add new size if provided
    if (newSize != null) {
      _currentCacheSize += newSize;
      _fileSizes[filePath] = newSize;
    }

    // Enforce cache size limit if needed
    await _enforceCacheSizeLimit();
  }

  /// Enforces the cache size limit by removing oldest files if needed
  Future<void> _enforceCacheSizeLimit() async {
    if (_cacheSizeUnlimited || _currentCacheSize <= _maxCacheSize) return;

    // Get list of files sorted by last modified time
    final directory = Directory(await _localPath);
    if (!await directory.exists()) return;

    final files = await directory
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();

    // Get modification times for all files
    final modTimes = <File, DateTime>{};
    for (final file in files) {
      final stats = await file.stat();
      modTimes[file] = stats.modified;
    }

    // Sort files by last modified time (oldest first)
    files.sort((a, b) => modTimes[a]!.compareTo(modTimes[b]!));

    // Remove oldest files until under limit
    for (final file in files) {
      if (_currentCacheSize <= _maxCacheSize) break;

      final size = _fileSizes[file.path] ?? 0;
      await file.delete();
      _currentCacheSize -= size;
      _fileSizes.remove(file.path);

      // Also remove from memory cache if it's a document
      final key = file.path.split('/').last.replaceAll('.json', '');
      _memoryCache.remove(key);
      _collectionCache.remove(key);
    }
  }

  /// Saves document data to persistent storage.
  Future<void> _saveToFile(
      DocumentReference docRef, Map<String, dynamic> data) async {
    if (_cacheSizeUnlimited || _currentCacheSize < _maxCacheSize) {
      final file = await _getLocalFile(docRef);
      await file.parent.create(recursive: true);
      final convertedData = _convertForStorage(data);
      final jsonData = jsonEncode(convertedData);
      await file.writeAsString(jsonData);
      await _updateCacheSize(file.path, jsonData.length);
    }
  }

  /// Saves collection data to persistent storage
  Future<void> _saveCollectionToFile(
      Query query, List<ColdStoreDocument> docs) async {
    if (_cacheSizeUnlimited || _currentCacheSize < _maxCacheSize) {
      final file = await _getCollectionFile(query);
      await file.parent.create(recursive: true);

      final List<Map<String, dynamic>> serializedDocs = docs.map((doc) {
        return {
          'id': doc.id,
          'path': doc.reference.path,
          'data': _convertForStorage(doc.data()!),
        };
      }).toList();

      final jsonData = jsonEncode(serializedDocs);
      await file.writeAsString(jsonData);
      await _updateCacheSize(file.path, jsonData.length);
    }
  }

  /// Reads document data from persistent storage.
  Future<Map<String, dynamic>?> _readFromFile(DocumentReference docRef) async {
    try {
      final file = await _getLocalFile(docRef);
      if (!await file.exists()) return null;
      final contents = await file.readAsString();
      final data = jsonDecode(contents) as Map<String, dynamic>;
      return _convertFromStorage(data, _firestore);
    } catch (e) {
      return null;
    }
  }

  /// Reads collection data from persistent storage
  Future<List<ColdStoreDocument>?> _readCollectionFromFile(Query query) async {
    try {
      final file = await _getCollectionFile(query);
      if (!await file.exists()) return null;
      final contents = await file.readAsString();
      final List<dynamic> data = jsonDecode(contents);

      return data.map((docData) {
        final id = docData['id'] as String;
        final documentData = _convertFromStorage(
          Map<String, dynamic>.from(docData['data']),
          _firestore,
        );
        return ColdStoreDocument(
          id: id,
          data: documentData,
          exists: true,
          reference: _firestore.doc(docData['path']),
        );
      }).toList();
    } catch (e) {
      return null;
    }
  }

  /// Gets document data from cache or Firestore.
  ///
  /// The data is retrieved in the following order:
  /// 1. Memory cache (fastest)
  /// 2. Persistent storage (JSON files)
  /// 3. Firestore (if not found in cache)
  ///
  /// If [autoWatch] is true (default), automatically starts watching the document
  /// for changes when it's first accessed.
  ///
  /// Returns null if the document doesn't exist or an error occurs.
  ///
  /// Example:
  /// ```dart
  /// final docRef = FirebaseFirestore.instance.doc('users/123');
  /// final data = await coldStore.get(docRef);
  /// // Document is now automatically watched if autoWatch is true
  /// ```
  Future<ColdStoreDocument?> get(DocumentReference docRef) async {
    final key = _getDocumentKey(docRef);

    // Start watching if auto-watch is enabled and not already watching
    if (autoWatch && !_watchedPaths.contains(key)) {
      await watch(docRef);
    }

    // 1. Check memory cache
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }

    // 2. Check persistent storage
    final persistedData = await _readFromFile(docRef);
    if (persistedData != null) {
      final document = ColdStoreDocument(
        id: docRef.id,
        data: persistedData,
        exists: true,
        reference: docRef,
      );
      _memoryCache[key] = document;
      return document;
    }

    // 3. Fetch from Firestore
    try {
      final doc = await docRef.get();
      final data = doc.data() as Map<String, dynamic>?;
      final document = ColdStoreDocument(
        id: docRef.id,
        data: data,
        exists: doc.exists,
        reference: docRef,
      );
      if (data != null) {
        await _saveToFile(docRef, data);
        _memoryCache[key] = document;
      }
      return document;
    } catch (e) {
      return null;
    }
  }

  /// Gets documents from a collection or query.
  ///
  /// Similar to document caching, collection results are cached in:
  /// 1. Memory cache
  /// 2. Persistent storage
  /// 3. Firestore
  ///
  /// Example:
  /// ```dart
  /// final collectionRef = FirebaseFirestore.instance.collection('users');
  /// // Get all documents
  /// final snapshot = await coldStore.getCollection(collectionRef);
  ///
  /// // With query
  /// final activeUsers = await coldStore.getCollection(
  ///   collectionRef.where('active', isEqualTo: true)
  /// );
  /// ```
  Future<ColdStoreQuerySnapshot> getCollection(Query query) async {
    final key = _getCollectionKey(query);

    // Start watching if auto-watch is enabled and not already watching
    if (autoWatch && !_watchedCollections.contains(key)) {
      await watchCollection(query);
    }

    // 1. Check memory cache
    if (_collectionCache.containsKey(key)) {
      return _collectionCache[key]!;
    }

    // 2. Check persistent storage
    final persistedData = await _readCollectionFromFile(query);
    if (persistedData != null) {
      final snapshot = ColdStoreQuerySnapshot(docs: persistedData);
      _collectionCache[key] = snapshot;

      // Start watching even if we got data from cache
      if (autoWatch && !_watchedCollections.contains(key)) {
        // Don't await here since we already have cached data
        watchCollection(query);
      }

      return snapshot;
    }

    // 3. Fetch from Firestore
    try {
      final querySnapshot = await query.get();
      final docs = querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return ColdStoreDocument(
          id: doc.id,
          data: data,
          exists: true,
          reference: doc.reference,
        );
      }).toList();

      final snapshot = ColdStoreQuerySnapshot(docs: docs);
      await _saveCollectionToFile(query, docs);
      _collectionCache[key] = snapshot;

      // Start watching even after fresh Firestore fetch
      if (autoWatch && !_watchedCollections.contains(key)) {
        // Don't await here since we already have fresh data
        watchCollection(query);
      }

      return snapshot;
    } catch (e) {
      return ColdStoreQuerySnapshot(docs: []);
    }
  }

  /// Starts watching a document for changes.
  ///
  /// Changes are automatically synchronized to both memory cache and persistent storage.
  /// If the document is already being watched, this is a no-op.
  ///
  /// This is called automatically by [get] if [autoWatch] is true.
  ///
  /// Example:
  /// ```dart
  /// final docRef = FirebaseFirestore.instance.doc('users/123');
  /// await coldStore.watch(docRef);
  /// // Changes will now be automatically cached
  /// ```
  Future<void> watch(DocumentReference docRef) async {
    final key = _getDocumentKey(docRef);
    if (_watchedPaths.contains(key)) return;

    final subscription = docRef.snapshots().listen((doc) async {
      final data = doc.data() as Map<String, dynamic>?;
      final document = ColdStoreDocument(
        id: docRef.id,
        data: data,
        exists: doc.exists,
        reference: docRef,
      );
      if (data != null) {
        _memoryCache[key] = document;
        await _saveToFile(docRef, data);
      }
    });

    _listeners[key] = subscription;
    _watchedPaths.add(key);
  }

  /// Watches a collection or query for changes.
  ///
  /// Changes are automatically synchronized to both memory cache and persistent storage.
  /// If the collection is already being watched, this is a no-op.
  ///
  /// Example:
  /// ```dart
  /// final collectionRef = FirebaseFirestore.instance.collection('users');
  /// await coldStore.watchCollection(collectionRef);
  /// // Changes will now be automatically cached
  /// ```
  Future<void> watchCollection(Query query) async {
    final key = _getCollectionKey(query);
    if (_watchedCollections.contains(key)) return;

    final subscription = query.snapshots().listen((snapshot) async {
      final docs = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return ColdStoreDocument(
          id: doc.id,
          data: data,
          exists: true,
          reference: doc.reference,
        );
      }).toList();

      final querySnapshot = ColdStoreQuerySnapshot(docs: docs);
      _collectionCache[key] = querySnapshot;
      await _saveCollectionToFile(query, docs);
    });

    _collectionListeners[key] = subscription;
    _watchedCollections.add(key);
  }

  /// Stops watching a document for changes.
  ///
  /// The document data remains in cache but won't be automatically updated.
  /// If the document isn't being watched, this is a no-op.
  ///
  /// Example:
  /// ```dart
  /// await coldStore.unwatch(docRef);
  /// ```
  Future<void> unwatch(DocumentReference docRef) async {
    final key = _getDocumentKey(docRef);
    final subscription = _listeners.remove(key);
    if (subscription != null) {
      await subscription.cancel();
      _watchedPaths.remove(key);
    }
  }

  /// Stops watching a collection for changes.
  Future<void> unwatchCollection(Query query) async {
    final key = _getCollectionKey(query);
    final subscription = _collectionListeners.remove(key);
    if (subscription != null) {
      await subscription.cancel();
      _watchedCollections.remove(key);
    }
  }

  /// Clears cached data for a specific document or all documents.
  ///
  /// If [docRef] is provided, clears cache only for that document.
  /// If [docRef] is null, clears all cached data.
  ///
  /// Example:
  /// ```dart
  /// // Clear specific document
  /// await coldStore.clear(docRef);
  ///
  /// // Clear all cache
  /// await coldStore.clear(null);
  /// ```
  Future<void> clear(DocumentReference? docRef) async {
    if (docRef != null) {
      final key = _getDocumentKey(docRef);
      _memoryCache.remove(key);
      final file = await _getLocalFile(docRef);
      if (await file.exists()) {
        await _updateCacheSize(file.path, null);
        await file.delete();
      }
    } else {
      _memoryCache.clear();
      _collectionCache.clear();
      final directory = Directory(await _localPath);
      if (await directory.exists()) {
        // Update cache size tracking
        _currentCacheSize = 0;
        _fileSizes.clear();
        await directory.delete(recursive: true);
      }
    }
  }

  /// Disposes of the ColdStore instance.
  ///
  /// - Cancels all document watchers
  /// - Clears memory cache
  ///
  /// Always call this when you're done with the ColdStore instance
  /// to prevent memory leaks.
  ///
  /// Example:
  /// ```dart
  /// await coldStore.dispose();
  /// ```
  Future<void> dispose() async {
    // Clean up collection watchers
    for (final subscription in _collectionListeners.values) {
      await subscription.cancel();
    }
    _collectionListeners.clear();
    _watchedCollections.clear();
    _collectionCache.clear();

    // Clean up document watchers
    for (final subscription in _listeners.values) {
      await subscription.cancel();
    }
    _listeners.clear();
    _watchedPaths.clear();
    _memoryCache.clear();
  }

  /// Returns statistics about the current cache state.
  ///
  /// Returns a Map containing:
  /// - currentSize: Current cache size in bytes
  /// - maxSize: Maximum allowed cache size in bytes (null if unlimited)
  /// - percentUsed: Percentage of cache used (null if unlimited)
  /// - numDocuments: Number of cached documents
  /// - numCollections: Number of cached collections
  /// - numWatchers: Total number of active watchers
  Map<String, dynamic> getCacheStats() {
    return {
      'currentSize': _currentCacheSize,
      'maxSize': _cacheSizeUnlimited ? null : _maxCacheSize,
      'percentUsed': _cacheSizeUnlimited
          ? null
          : (_currentCacheSize / _maxCacheSize * 100).round(),
      'numDocuments': _memoryCache.length,
      'numCollections': _collectionCache.length,
      'numWatchers': _listeners.length + _collectionListeners.length,
    };
  }

  /// Lists all cached documents.
  ///
  /// Returns a map where:
  /// - key: document path
  /// - value: document metadata including last modified time and size
  Future<Map<String, Map<String, dynamic>>> listCachedDocuments() async {
    final result = <String, Map<String, dynamic>>{};

    for (final entry in _memoryCache.entries) {
      final docRef = entry.value.reference;
      final file = await _getLocalFile(docRef);
      if (await file.exists()) {
        final stat = await file.stat();
        result[entry.key] = {
          'id': entry.value.id,
          'path': entry.value.reference.path,
          'size': _fileSizes[file.path] ?? 0,
          'lastModified': stat.modified,
          'isWatched': _watchedPaths.contains(entry.key),
        };
      }
    }

    return result;
  }

  /// Lists all cached collections.
  ///
  /// Returns a map where:
  /// - key: collection path/query string
  /// - value: collection metadata including document count and size
  Future<Map<String, Map<String, dynamic>>> listCachedCollections() async {
    final result = <String, Map<String, dynamic>>{};

    for (final entry in _collectionCache.entries) {
      final file =
          await _getCollectionFile(entry.value.docs.first.reference.parent);
      if (await file.exists()) {
        final stat = await file.stat();
        result[entry.key] = {
          'path': entry.key,
          'documentCount': entry.value.size,
          'size': _fileSizes[file.path] ?? 0,
          'lastModified': stat.modified,
          'isWatched': _watchedCollections.contains(entry.key),
        };
      }
    }

    return result;
  }

  /// Lists all active watchers (listeners).
  ///
  /// Returns a map containing:
  /// - documents: List of watched document paths
  /// - collections: List of watched collection paths/queries
  Map<String, List<String>> listActiveWatchers() {
    return {
      'documents': _watchedPaths.toList(),
      'collections': _watchedCollections.toList(),
    };
  }

  /// Returns true if the cache is approaching its size limit.
  ///
  /// [threshold] - Percentage (0-100) at which to consider the cache nearly full.
  /// Defaults to 90%.
  ///
  /// Always returns false if cache size is unlimited.
  bool isCacheNearlyFull([int threshold = 90]) {
    if (_cacheSizeUnlimited) return false;
    return (_currentCacheSize / _maxCacheSize * 100) >= threshold;
  }

  /// Gets the current cache size in bytes.
  int get currentCacheSize => _currentCacheSize;

  /// Gets the maximum cache size in bytes, or null if unlimited.
  int? get maxCacheSize => _cacheSizeUnlimited ? null : _maxCacheSize;
}
