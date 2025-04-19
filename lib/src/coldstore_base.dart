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
  /// In-memory cache storing document data and metadata
  final Map<String, ColdStoreDocument> _memoryCache = {};

  /// Active document watchers
  final Map<String, StreamSubscription<DocumentSnapshot>> _listeners = {};

  /// Set of document paths that are being watched
  final Set<String> _watchedPaths = {};

  /// The Firestore instance to use
  final FirebaseFirestore _firestore;

  /// Whether to automatically watch documents when they're first accessed
  final bool autoWatch;

  /// Creates a new ColdStore instance.
  ///
  /// [firestore] - Optional custom Firestore instance. If not provided,
  /// uses [FirebaseFirestore.instance].
  ///
  /// [autoWatch] - Whether to automatically start watching documents when they're
  /// first accessed via [get]. Defaults to true.
  ColdStore({FirebaseFirestore? firestore, this.autoWatch = true})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Gets the storage key for a document reference.
  String _getDocumentKey(DocumentReference docRef) => docRef.path;

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

  /// Saves document data to persistent storage.
  Future<void> _saveToFile(
      DocumentReference docRef, Map<String, dynamic> data) async {
    final file = await _getLocalFile(docRef);
    await file.parent.create(recursive: true);
    final convertedData = _convertForStorage(data);
    await file.writeAsString(jsonEncode(convertedData));
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
        await file.delete();
      }
    } else {
      _memoryCache.clear();
      final directory = Directory(await _localPath);
      if (await directory.exists()) {
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
    for (final subscription in _listeners.values) {
      await subscription.cancel();
    }
    _listeners.clear();
    _watchedPaths.clear();
    _memoryCache.clear();
  }
}
