import 'package:flutter/material.dart';
import 'package:netconnect/screens/home.dart';
import 'package:netconnect/screens/inbox.dart';
import 'package:netconnect/screens/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:netconnect/server_config.dart';
import 'package:netconnect/screens/notice_board.dart';
import 'package:provider/provider.dart'; // NEW: Import provider
import 'package:netconnect/screens/websocket_provider.dart'; // NEW: Import your WebSocketProvider

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  List<User> _allUsers = []; // Replace with your actual user fetching logic
  List<User> _selectedUsers = [];

  int _selectedIndex = 1; // Set initial index to New Group tab in bottom nav

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 0) {
        print('Users Tapped');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const UsersScreen()),
        );
      } else if (index == 1) {
        print('Add Group Tapped');
        // This is the current screen, no need to navigate
      } else if (index == 2) {
        print('Feed tapped');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const NoticeBoardPage()),
        );
      } else if (index == 3) {
        print('Inbox Tapped');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const InboxScreen()),
        );
      } else if (index == 4) {
        print('Settings Tapped');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const NetworkSettingsScreen(),
          ),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  // Simulate fetching users from your LAN
  Future<void> _fetchUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null) return;

    final serverIp = await ServerConfig.getServerIp();
    if (serverIp == null) {
      if (mounted) {
        // Added mounted check
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Server IP not set. Please configure network settings.',
            ),
          ),
        );
      }
      return;
    }

    final response = await http.get(
      Uri.parse('http://$serverIp:8000/api/users'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final List<dynamic> usersJson = json.decode(response.body);
      setState(() {
        _allUsers = usersJson.map((u) => User.fromJson(u)).toList();
      });
    } else {
      setState(() {
        _allUsers = [];
      });
      if (mounted) {
        // Added mounted check
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch users: ${response.body}')),
        );
      }
    }
  }

  void _toggleUserSelection(User user) {
    setState(() {
      if (_selectedUsers.contains(user)) {
        _selectedUsers.remove(user);
      } else {
        _selectedUsers.add(user);
      }
    });
  }

  void _createGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty || _selectedUsers.isEmpty) {
      if (mounted) {
        // Added mounted check
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please enter a group name and select at least one user.',
            ),
          ),
        );
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final myUsername = prefs.getString('username');
    if (token == null || myUsername == null) {
      if (mounted) {
        // Added mounted check
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Not authenticated!')));
      }
      return;
    }

    // Ensure the current user is always added to the group
    if (!_selectedUsers.any((u) => u.username == myUsername)) {
      final me = _allUsers.firstWhere(
        (u) => u.username == myUsername,
        orElse:
            () => User(
              id: '',
              name: myUsername,
              username: myUsername,
            ), // Fallback if current user not in _allUsers
      );
      _selectedUsers.add(me);
    }

    final usernames = _selectedUsers.map((u) => u.username).join(',');

    final serverIp2 = await ServerConfig.getServerIp();
    if (serverIp2 == null) {
      if (mounted) {
        // Added mounted check
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Server IP not set. Please configure network settings.',
            ),
          ),
        );
      }
      return;
    }
    final response = await http.post(
      Uri.parse('http://$serverIp2:8000/groups'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'name': groupName, 'member_usernames': usernames},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (mounted) {
        // Added mounted check
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Group created: ${data['group_name']}')),
        );
      }
      // Redirect to Inbox after a short delay so the user sees the message
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          // Added mounted check
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => const InboxScreen(),
            ), // Assuming InboxScreen is the destination
            (route) => false,
          );
        }
      });
    } else {
      if (mounted) {
        // Added mounted check
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: ${response.body}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // NEW: Consume the WebSocketProvider
    final webSocketProvider = Provider.of<WebSocketProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Group'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed:
              () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const UsersScreen()),
              ),
        ),
        actions: [
          TextButton(
            onPressed: _createGroup,
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue, // Or your primary color
            ),
            child: const Text('Create'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Group Name',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _groupNameController,
              decoration: const InputDecoration(hintText: 'Enter group name'),
            ),
            const SizedBox(height: 24),
            Text(
              'Add Participants',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child:
                  _allUsers.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                        itemCount: _allUsers.length,
                        itemBuilder: (context, index) {
                          final user = _allUsers[index];
                          final isSelected = _selectedUsers.contains(user);
                          // NEW: Determine if the user is online using the provider
                          final isUserOnline = webSocketProvider.isUserOnline(
                            user.username,
                          );

                          return ListTile(
                            leading: Stack(
                              // Wrap CircleAvatar in Stack for online indicator
                              children: [
                                CircleAvatar(
                                  backgroundImage:
                                      user.avatarUrl != null
                                          ? NetworkImage(user.avatarUrl!)
                                          : null,
                                  child:
                                      user.avatarUrl == null
                                          ? Text(user.name[0].toUpperCase())
                                          : null,
                                ),
                                // NEW: Online indicator
                                if (isUserOnline)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(user.name),
                            trailing: Checkbox(
                              value: isSelected,
                              onChanged: (bool? value) {
                                if (value != null) {
                                  _toggleUserSelection(user);
                                }
                              },
                            ),
                            onTap: () => _toggleUserSelection(user),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'New Group',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.feed), label: 'Feed'),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Inbox',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
        showUnselectedLabels: false,
        onTap: _onItemTapped,
      ),
    );
  }
}

class User {
  final String id;
  final String name;
  final String? avatarUrl;
  final String username;

  User({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.username,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      name: json['name'],
      username: json['username'],
      avatarUrl: json['avatar_url'] ?? 'https://via.placeholder.com/40',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User &&
          runtimeType == other.runtimeType &&
          username == other.username;

  @override
  int get hashCode => username.hashCode;

  @override
  String toString() {
    return 'User{id: $id, name: $name, username: $username}';
  }
}
