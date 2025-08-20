import "package:flutter/material.dart";
import 'package:netconnect/screens/chat_screen.dart';
import 'package:netconnect/screens/create_group.dart';
import 'package:netconnect/screens/notice_board.dart';
import 'inbox.dart';
import 'settings.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:netconnect/server_config.dart';
import 'package:provider/provider.dart';
import 'package:netconnect/screens/websocket_provider.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _boardSearchController = TextEditingController();
  List<AppUser> _availableUsers = [];
  bool _isLoading = true;
  List<NoticeBoardData> _noticeBoards = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _fetchNoticeBoards();
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<void> _fetchUsers() async {
    try {
      final token = await getToken();
      final serverIp = await ServerConfig.getServerIp();
      if (serverIp == null) {
        if (mounted) {
          setState(() => _isLoading = false);
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
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _availableUsers =
                data.map((json) => AppUser.fromJson(json)).toList();
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Failed to load users: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error fetching users: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchNoticeBoards() async {
    try {
      final token = await getToken();
      final serverIp = await ServerConfig.getServerIp();
      if (serverIp == null) {
        if (mounted) {
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
        Uri.parse('http://$serverIp:8000/notice_boards'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _noticeBoards =
                data.map((json) => NoticeBoardData.fromJson(json)).toList();
          });
        }
      } else {
        throw Exception('Failed to load notice boards: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching notice boards: $e')),
        );
      }
    }
  }

  int _selectedIndex = 0;
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 0) {
        print('Users Tapped');
      } else if (index == 1) {
        print('Add Group Tapped');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const CreateGroupScreen()),
        );
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

  Future<void> _toggleBoardFollowStatus(NoticeBoardData board) async {
    final serverIp = await ServerConfig.getServerIp();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (serverIp == null || token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication or server IP missing.')),
        );
      }
      return;
    }

    final url =
        board.isFollowed
            ? 'http://$serverIp:8000/notice_boards/${board.id}/unfollow'
            : 'http://$serverIp:8000/notice_boards/${board.id}/follow';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            final index = _noticeBoards.indexWhere((b) => b.id == board.id);
            if (index != -1) {
              _noticeBoards[index] = board.copyWith(
                isFollowed: !board.isFollowed,
              );
            }
          });
        }
        _fetchNoticeBoards();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                board.isFollowed
                    ? 'Unfollowed ${board.name}'
                    : 'Following ${board.name}',
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to update follow status: ${response.statusCode}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating follow status: $e')),
        );
      }
    }
  }

  // --- SEPARATE SEARCH FILTERS ---

  List<AppUser> get _filteredUsers {
    final q = _userSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return _availableUsers;
    return _availableUsers
        .where(
          (u) =>
              u.name.toLowerCase().contains(q) ||
              u.username.toLowerCase().contains(q),
        )
        .toList();
  }

  List<NoticeBoardData> get _filteredBoards {
    final q = _boardSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return _noticeBoards;
    return _noticeBoards
        .where((b) => b.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final webSocketProvider = Provider.of<WebSocketProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('NetConnect'),
        centerTitle: false,
        // actions: [
        //   IconButton(
        //     icon: const Icon(Icons.notifications, color: Colors.black),
        //     onPressed: () {},
        //   ),
        // ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- USERS SEARCH BAR ---
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: TextField(
                        controller: _userSearchController,
                        decoration: InputDecoration(
                          hintText: 'Search users...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 12,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const Text(
                      'Available Users',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          final isUserOnline = webSocketProvider.isUserOnline(
                            user.username,
                          );
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).cardColor, // <-- USE THIS
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: Stack(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.lightBlue.shade200,
                                    backgroundImage: NetworkImage(
                                      user.avatarUrl,
                                    ),
                                  ),
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
                              title: Text(
                                user.name,
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).textTheme.bodyLarge?.color,
                                ),
                              ),
                              subtitle: Text(
                                user.username,
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.color,
                                ),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => ChatScreen(
                                          username: user.username,
                                          avatarUrl: user.avatarUrl,
                                        ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    // --- BOARDS SEARCH BAR ---
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: TextField(
                        controller: _boardSearchController,
                        decoration: InputDecoration(
                          hintText: 'Search notice boards...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 12,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const Text(
                      'Notice Boards',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child:
                          _filteredBoards.isEmpty
                              ? const Center(
                                child: Text('No notice boards found.'),
                              )
                              : ListView.builder(
                                shrinkWrap: true,
                                itemCount: _filteredBoards.length,
                                itemBuilder: (context, idx) {
                                  final board = _filteredBoards[idx];
                                  return ListTile(
                                    title: Text(board.name),
                                    trailing:
                                        board.isAdmin
                                            ? null
                                            : TextButton(
                                              onPressed:
                                                  () =>
                                                      _toggleBoardFollowStatus(
                                                        board,
                                                      ),
                                              child: Text(
                                                board.isFollowed
                                                    ? 'Unfollow'
                                                    : 'Follow',
                                              ),
                                            ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) => NoticeBoardPage(
                                                initialBoardId:
                                                    board.id.toString(),
                                              ),
                                        ),
                                      );
                                    },
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

class AppUser {
  final String id;
  final String name;
  final String username;
  final String avatarUrl;

  AppUser({
    required this.id,
    required this.name,
    required this.username,
    required this.avatarUrl,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'].toString(),
      name: json['name'],
      username: json['username'],
      avatarUrl: json['avatar_url'] ?? 'https://via.placeholder.com/50',
    );
  }
}

class NoticeBoardData {
  final String id;
  final String name;
  final String admin;
  bool isFollowed;
  final bool isAdmin;

  NoticeBoardData({
    required this.id,
    required this.name,
    required this.admin,
    this.isFollowed = false,
    this.isAdmin = false,
  });

  factory NoticeBoardData.fromJson(Map<String, dynamic> json) {
    return NoticeBoardData(
      id: json['id'].toString(),
      name: json['name'],
      admin: json['admin'] ?? '',
      isFollowed: json['is_followed'] ?? false,
      isAdmin: json['is_admin'] ?? false,
    );
  }

  NoticeBoardData copyWith({bool? isFollowed}) {
    return NoticeBoardData(
      id: id,
      name: name,
      admin: admin,
      isFollowed: isFollowed ?? this.isFollowed,
      isAdmin: isAdmin,
    );
  }
}
