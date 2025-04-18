import 'package:coldstore/coldstore.dart';

void main() async {
  // Initialize ColdStore
  final coldStore = ColdStore();

  // Example document path
  const userDocPath = 'users/user123';

  // Start watching the document
  await coldStore.watch(userDocPath);

  // Get data (will check memory cache -> persistent storage -> Firestore)
  final userData = await coldStore.getData(userDocPath);
  print('User data: $userData');

  // Data will be automatically updated in cache when Firestore changes

  // When done, stop watching and dispose
  await coldStore.unwatch(userDocPath);
  await coldStore.dispose();

  // Clear specific document cache
  await coldStore.clearCache(userDocPath);

  // Or clear all cache
  await coldStore.clearCache(null);
}
