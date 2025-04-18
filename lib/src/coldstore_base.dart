import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ColdStore {
  final Map<String, dynamic> _memoryCache = {};
  final Map<String, StreamSubscription<DocumentSnapshot>> _listeners = {};
  final FirebaseFirestore _firestore;

  ColdStore({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return path.join(directory.path, 'coldstore_cache');
  }

  Future<File> _getLocalFile(String documentPath) async {
    final basePath = await _localPath;
    final sanitizedPath = documentPath.replaceAll('/', '_');
    return File(path.join(basePath, '$sanitizedPath.json'));
  }

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

  Map<String, dynamic> _convertFromStorage(Map<String, dynamic> data) {
    return Map.fromEntries(data.entries.map((entry) {
      var value = entry.value;
      if (value is Map) {
        if (value['type'] == 'timestamp') {
          return MapEntry(
              entry.key, Timestamp(value['seconds'], value['nanoseconds']));
        } else if (value['type'] == 'geopoint') {
          return MapEntry(
              entry.key, GeoPoint(value['latitude'], value['longitude']));
        } else if (value['type'] == 'reference') {
          return MapEntry(entry.key, _firestore.doc(value['path']));
        } else if (value['type'] == 'array') {
          return MapEntry(
              entry.key,
              (value['values'] as List)
                  .map((e) => e is Map
                      ? _convertFromStorage(Map<String, dynamic>.from(e))
                      : e)
                  .toList());
        } else {
          return MapEntry(
              entry.key, _convertFromStorage(Map<String, dynamic>.from(value)));
        }
      }
      return MapEntry(entry.key, value);
    }));
  }

  Future<void> _saveToFile(
      String documentPath, Map<String, dynamic> data) async {
    final file = await _getLocalFile(documentPath);
    await file.parent.create(recursive: true);
    final convertedData = _convertForStorage(data);
    await file.writeAsString(jsonEncode(convertedData));
  }

  Future<Map<String, dynamic>?> _readFromFile(String documentPath) async {
    try {
      final file = await _getLocalFile(documentPath);
      if (!await file.exists()) return null;
      final contents = await file.readAsString();
      final data = jsonDecode(contents) as Map<String, dynamic>;
      return _convertFromStorage(data);
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getData(String documentPath) async {
    // 1. Check memory cache
    if (_memoryCache.containsKey(documentPath)) {
      return _memoryCache[documentPath];
    }

    // 2. Check persistent storage
    final persistedData = await _readFromFile(documentPath);
    if (persistedData != null) {
      _memoryCache[documentPath] = persistedData;
      return persistedData;
    }

    // 3. Fetch from Firestore
    try {
      final doc = await _firestore.doc(documentPath).get();
      final data = doc.data();
      if (data != null) {
        await _saveToFile(documentPath, data);
        _memoryCache[documentPath] = data;
        return data;
      }
    } catch (e) {
      return null;
    }

    return null;
  }

  Future<void> watch(String documentPath) async {
    if (_listeners.containsKey(documentPath)) return;

    final subscription =
        _firestore.doc(documentPath).snapshots().listen((doc) async {
      final data = doc.data();
      if (data != null) {
        _memoryCache[documentPath] = data;
        await _saveToFile(documentPath, data);
      }
    });

    _listeners[documentPath] = subscription;
  }

  Future<void> unwatch(String documentPath) async {
    final subscription = _listeners.remove(documentPath);
    if (subscription != null) {
      await subscription.cancel();
    }
  }

  Future<void> clearCache(String? documentPath) async {
    if (documentPath != null) {
      _memoryCache.remove(documentPath);
      final file = await _getLocalFile(documentPath);
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

  Future<void> dispose() async {
    for (final subscription in _listeners.values) {
      await subscription.cancel();
    }
    _listeners.clear();
    _memoryCache.clear();
  }
}
