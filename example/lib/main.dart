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
      home: const UserListPage(),
    );
  }
}

class UserListPage extends StatefulWidget {
  const UserListPage({super.key});

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  final ColdStore _coldStore = ColdStore();
  ColdStoreQuerySnapshot? _usersSnapshot;
  bool _isLoading = true;
  late final CollectionReference _usersRef;
  bool _showActiveOnly = false;

  @override
  void initState() {
    super.initState();
    _usersRef = FirebaseFirestore.instance.collection('users');
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);

    try {
      Query query = _usersRef;
      if (_showActiveOnly) {
        query = query.where('active', isEqualTo: true);
      }

      final snapshot = await _coldStore.getCollection(query);
      setState(() {
        _usersSnapshot = snapshot;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading users')),
        );
      }
    }
  }

  Future<void> _addSampleUser() async {
    try {
      final docRef = _usersRef.doc();
      await docRef.set({
        'name': 'New User ${DateTime.now().millisecondsSinceEpoch}',
        'email': 'user@example.com',
        'active': true,
        'lastUpdated': Timestamp.now(),
        'location': const GeoPoint(37.7749, -122.4194),
        'preferences': {'theme': 'dark', 'notifications': true}
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User added')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error adding user')),
      );
    }
  }

  @override
  void dispose() {
    _coldStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          // Toggle active filter
          IconButton(
            icon: Icon(
              _showActiveOnly ? Icons.check_box : Icons.check_box_outline_blank,
            ),
            tooltip: 'Show active only',
            onPressed: () {
              setState(() {
                _showActiveOnly = !_showActiveOnly;
              });
              _loadUsers();
            },
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsers,
          ),
          // Clear cache
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              await _coldStore.clear(null);
              await _loadUsers();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _usersSnapshot == null || _usersSnapshot!.empty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('No users found'),
                      ElevatedButton(
                        onPressed: _addSampleUser,
                        child: const Text('Add Sample User'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _usersSnapshot!.size,
                  itemBuilder: (context, index) {
                    final doc = _usersSnapshot!.docs[index];
                    final data = doc.data()!;
                    return ListTile(
                      title: Text(data['name']?.toString() ?? 'Unnamed User'),
                      subtitle: Text(data['email']?.toString() ?? 'No email'),
                      trailing: Icon(
                        data['active'] == true
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                        color:
                            data['active'] == true ? Colors.green : Colors.grey,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => UserProfilePage(
                              userRef: doc.reference,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSampleUser,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class UserProfilePage extends StatefulWidget {
  final DocumentReference userRef;

  const UserProfilePage({super.key, required this.userRef});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final ColdStore _coldStore = ColdStore();
  ColdStoreDocument? _userDoc;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);

    try {
      final doc = await _coldStore.get(widget.userRef);
      setState(() {
        _userDoc = doc;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading user')),
        );
      }
    }
  }

  Future<void> _toggleActive() async {
    if (_userDoc == null) return;

    try {
      final currentData = _userDoc!.data()!;
      await widget.userRef.update({
        'active': !(currentData['active'] ?? false),
        'lastUpdated': Timestamp.now(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User updated')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error updating user')),
      );
    }
  }

  @override
  void dispose() {
    _coldStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userData = _userDoc?.data();

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUser,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userDoc == null || !_userDoc!.exists
              ? const Center(child: Text('User not found'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UserDataTile(
                        title: 'Document ID',
                        value: _userDoc!.id,
                      ),
                      UserDataTile(
                        title: 'Name',
                        value: userData!['name']?.toString() ?? 'N/A',
                      ),
                      UserDataTile(
                        title: 'Email',
                        value: userData['email']?.toString() ?? 'N/A',
                      ),
                      UserDataTile(
                        title: 'Status',
                        value:
                            userData['active'] == true ? 'Active' : 'Inactive',
                      ),
                      UserDataTile(
                        title: 'Last Updated',
                        value: userData['lastUpdated'] != null
                            ? (userData['lastUpdated'] as Timestamp)
                                .toDate()
                                .toString()
                            : 'N/A',
                      ),
                      UserDataTile(
                        title: 'Location',
                        value: userData['location'] != null
                            ? '${(userData['location'] as GeoPoint).latitude}, '
                                '${(userData['location'] as GeoPoint).longitude}'
                            : 'N/A',
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _toggleActive,
                        child: Text(userData['active'] == true
                            ? 'Deactivate User'
                            : 'Activate User'),
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
