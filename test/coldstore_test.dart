import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:coldstore/coldstore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ColdStore coldStore;
  late FirebaseFirestore firestore;
  late Directory tempDir;

  setUpAll(() async {
    // Initialize Firebase for testing
    await Firebase.initializeApp();
    firestore = FirebaseFirestore.instance;

    // Create a temporary directory for cache
    tempDir = await Directory.systemTemp.createTemp('coldstore_test_');

    // Mock getApplicationDocumentsDirectory to use our temp directory
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  setUp(() {
    coldStore = ColdStore(firestore: firestore);
  });

  tearDown(() async {
    await coldStore.dispose();
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ColdStore initialization', () {
    test('creates instance with default parameters', () {
      final store = ColdStore();
      expect(store, isNotNull);
      expect(store.autoWatch, isTrue);
      expect(store.currentCacheSize, equals(0));
      expect(store.maxCacheSize, equals(100 * 1024 * 1024)); // 100MB
    });

    test('creates instance with custom parameters', () {
      final store = ColdStore(
        autoWatch: false,
        cacheSizeUnlimited: true,
        maxCacheSize: 50 * 1024 * 1024,
      );
      expect(store.autoWatch, isFalse);
      expect(store.maxCacheSize, isNull);
    });
  });

  group('Cache management', () {
    test('tracks cache size correctly', () async {
      final docRef = firestore.doc('test/doc1');

      // Save document to cache
      await coldStore.get(docRef);

      expect(coldStore.currentCacheSize, isNonNegative);
    });

    test('enforces cache size limit', () async {
      final store = ColdStore(maxCacheSize: 1024); // 1KB limit

      // Add documents until we exceed the limit
      for (int i = 0; i < 10; i++) {
        final docRef = firestore.doc('test/doc$i');
        await store.get(docRef);
      }

      expect(store.currentCacheSize, lessThanOrEqualTo(1024));
    });

    test('cache inspection methods work', () async {
      final docRef = firestore.doc('test/doc1');
      await coldStore.get(docRef);
      await coldStore.watch(docRef);

      final stats = coldStore.getCacheStats();
      expect(stats['currentSize'], isNonNegative);
      expect(stats['numDocuments'], equals(1));
      expect(stats['numWatchers'], equals(1));

      final docs = await coldStore.listCachedDocuments();
      expect(docs, isNotEmpty);

      final watchers = coldStore.listActiveWatchers();
      expect(watchers['documents'], contains(docRef.path));
    });
  });

  group('Document operations', () {
    test('get returns null for non-existent document', () async {
      final docRef = firestore.doc('test/nonexistent');
      final doc = await coldStore.get(docRef);
      expect(doc, isNull);
    });

    test('watch starts document listener', () async {
      final docRef = firestore.doc('test/doc1');
      await coldStore.watch(docRef);

      final watchers = coldStore.listActiveWatchers();
      expect(watchers['documents'], contains(docRef.path));
    });

    test('unwatch stops document listener', () async {
      final docRef = firestore.doc('test/doc1');
      await coldStore.watch(docRef);
      await coldStore.unwatch(docRef);

      final watchers = coldStore.listActiveWatchers();
      expect(watchers['documents'], isEmpty);
    });
  });

  group('Collection operations', () {
    test('getCollection returns empty snapshot for empty collection', () async {
      final colRef = firestore.collection('test_empty');
      final snapshot = await coldStore.getCollection(colRef);
      expect(snapshot.empty, isTrue);
      expect(snapshot.size, equals(0));
    });

    test('watchCollection starts collection listener', () async {
      final colRef = firestore.collection('test');
      await coldStore.watchCollection(colRef);

      final watchers = coldStore.listActiveWatchers();
      expect(watchers['collections'], contains(colRef.path));
    });

    test('unwatchCollection stops collection listener', () async {
      final colRef = firestore.collection('test');
      await coldStore.watchCollection(colRef);
      await coldStore.unwatchCollection(colRef);

      final watchers = coldStore.listActiveWatchers();
      expect(watchers['collections'], isEmpty);
    });
  });
}
