import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:coldstore/coldstore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ColdStore Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const UserProfilePage(),
    );
  }
}

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final ColdStore _coldStore = ColdStore();
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  late final DocumentReference _userDoc;

  @override
  void initState() {
    super.initState();
    _userDoc = FirebaseFirestore.instance.doc('users/example_user');
    _initializeData();
  }

  Future<void> _initializeData() async {
    // Start watching the document for real-time updates
    await _coldStore.watch(_userDoc);

    // Initial data fetch
    await _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);

    try {
      final data = await _coldStore.get(_userDoc);
      setState(() {
        _userData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading user data')),
        );
      }
    }
  }

  Future<void> _updateUserData() async {
    try {
      // Direct Firestore update - ColdStore will automatically sync
      await _userDoc.set({
        'name': 'John Doe',
        'email': 'john@example.com',
        'lastUpdated': Timestamp.now(),
        'location': const GeoPoint(37.7749, -122.4194),
        'preferences': {'theme': 'dark', 'notifications': true}
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User data updated')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error updating user data')),
      );
    }
  }

  @override
  void dispose() {
    _coldStore.unwatch(_userDoc);
    _coldStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _coldStore.clear(_userDoc),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userData == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('No user data found'),
                      ElevatedButton(
                        onPressed: _updateUserData,
                        child: const Text('Create User Data'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UserDataTile(
                        title: 'Name',
                        value: _userData!['name']?.toString() ?? 'N/A',
                      ),
                      UserDataTile(
                        title: 'Email',
                        value: _userData!['email']?.toString() ?? 'N/A',
                      ),
                      UserDataTile(
                        title: 'Last Updated',
                        value: _userData!['lastUpdated'] != null
                            ? (_userData!['lastUpdated'] as Timestamp)
                                .toDate()
                                .toString()
                            : 'N/A',
                      ),
                      UserDataTile(
                        title: 'Location',
                        value: _userData!['location'] != null
                            ? '${(_userData!['location'] as GeoPoint).latitude}, '
                                '${(_userData!['location'] as GeoPoint).longitude}'
                            : 'N/A',
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _updateUserData,
                        child: const Text('Update User Data'),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class UserDataTile extends StatelessWidget {
  final String title;
  final String value;

  const UserDataTile({
    super.key,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const Divider(),
        ],
      ),
    );
  }
}
