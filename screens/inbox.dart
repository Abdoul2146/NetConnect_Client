import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:netconnect/screens/create_group.dart';
import 'home.dart';
import 'settings.dart';
import 'package:netconnect/screens/chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:netconnect/screens/profile.dart';
import 'package:intl/intl.dart';
import 'package:netconnect/server_config.dart';

class ForwardTarget {
  final String name; // username or group name
  final bool isGroup;

  ForwardTarget(this.name, this.isGroup);
}

String formatChatTimestamp(String isoString) {
  final dateTime = DateTime.parse(isoString).toLocal();
  final now = DateTime.now();

  if (dateTime.year == now.year &&
      dateTime.month == now.month &&
      dateTime.day == now.day) {
    // 24-hour format
    return DateFormat('HH:mm').format(dateTime);
  } else {
    return DateFormat('yyyy-MM-dd').format(dateTime);
  }
}

class InboxScreen extends StatefulWidget {
  final bool selectMode;

  const InboxScreen({Key? key, this.selectMode = false}) : super(key: key);

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  late WebSocketChannel _channel;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  late Future<List<ChatMessage>> _chatsFuture;
  List<ChatMessage> _chats = []; // Store fetched chats
  int _selectedIndex = 2; // Default to Inbox tab in bottom navigation
  late String _currentUsername;
  final Set<String> _selectedUsernames = {}; // For selectMode
  Set<String> _activeUsers = {}; // Track active users

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _chatsFuture = fetchChats();

    Future.microtask(() async {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      final username = prefs.getString('username');
      if (token != null && username != null) {
        _currentUsername = username;
        final serverIp = await ServerConfig.getServerIp();
        if (serverIp == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Server IP not set. Please configure network settings.',
              ),
            ),
          );
          return;
        }
        _channel = WebSocketChannel.connect(
          Uri.parse('ws://$serverIp:8000/ws/$username?token=$token'),
        );
        _channel.stream.listen(
          (data) {
            try {
              final msg = json.decode(data);
              if (msg['type'] == 'chat_preview_update' ||
                  msg['type'] == 'direct_message' ||
                  msg['type'] == 'group_message') {
                onNewMessage(msg);
              } else if (msg['type'] == 'user_active' ||
                  msg['type'] == 'status') {
                setState(() {
                  if (msg['status'] == 'online' || msg['active'] == true) {
                    _activeUsers.add(msg['username']);
                  } else {
                    _activeUsers.remove(msg['username']);
                  }
                });
              } else if (msg['type'] == 'message_status') {
                // Update status for the relevant chat
                final status = msg['status'];
                setState(() {
                  for (var chat in _chats) {
                    // You may need to map message_id to chat here if you have that info
                    if (chat.username == msg['to'] ||
                        chat.username == msg['from']) {
                      chat.status = status;
                    }
                  }
                });
              }
            } catch (e, stack) {
              debugPrint('WebSocket message error: $e\n$stack');
            }
          },
          onError: (error) {
            debugPrint('WebSocket error: $error');
            // Optionally show a snackbar or dialog
          },
          onDone: () {
            debugPrint('WebSocket connection closed');
            // Optionally try to reconnect here
          },
          cancelOnError: true,
        );
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _channel.sink.close();
    super.dispose();
  }

  Future<void> markChatAsRead(String username, bool isGroup) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null) return;

    final serverIp = await ServerConfig.getServerIp();
    if (serverIp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Server IP not set. Please configure network settings.',
          ),
        ),
      );
      return;
    }

    if (isGroup) {
      // For group chats, group name in the URL
      final url = 'http://$serverIp:8000/groups/$username/mark_read';
      await http.post(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );
    } else {
      // For direct chats, username in the form body
      final url = 'http://$serverIp:8000/messages/mark_read';
      await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'username': username},
      );
    }
  }

  Future<List<ChatMessage>> fetchChats() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null) {
      throw Exception('No access token found');
    }
    final serverIp = await ServerConfig.getServerIp();
    if (serverIp == null) {
      throw Exception('Server IP not set. Please configure network settings.');
    }
    final response = await http.get(
      Uri.parse('http://$serverIp:8000/chats'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data as List).map((chat) => ChatMessage.fromJson(chat)).toList();
    } else {
      throw Exception('Failed to load chats');
    }
  }

  List<ChatMessage> filterChats(List<ChatMessage> chats, bool isGroup) {
    return chats.where((chat) => chat.isGroup == isGroup).toList();
  }

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
        print('New Group Tapped');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const CreateGroupScreen()),
        );
      } else if (index == 2) {
        print('Inbox Tapped');
        // Already on Inbox screen
      } else if (index == 3) {
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

  void onNewMessage(Map<String, dynamic> msg) {
    print('🔄 WebSocket message received: $msg');
    setState(() {
      bool isGroup =
          msg['chat_type'] == 'group' ||
          msg['is_group'] == true ||
          msg['type'] == 'group_message'; // extra check for group_message type

      String identifier;
      String displayName;

      if (isGroup) {
        // Always use the group name as identifier and display name
        identifier = (msg['group'] ?? msg['chat_id'] ?? '').toString();
        displayName = identifier;
      } else {
        // For direct messages, use the other user's username
        if (msg['from'] == _currentUsername) {
          identifier = (msg['to'] ?? '');
        } else {
          identifier = (msg['from'] ?? '');
        }
        displayName = identifier;
      }

      int idx = _chats.indexWhere(
        (c) => c.isGroup == isGroup && c.username == identifier,
      );

      String preview =
          msg['last_message'] ??
          msg['content'] ??
          (msg['file_path'] != null
              ? "[File] ${msg['file_path'].toString().split('/').last}"
              : "[New Message]");

      String timestamp = msg['timestamp'] ?? DateTime.now().toIso8601String();
      String? status = msg['status'];

      if (idx != -1) {
        _chats[idx].lastMessage = preview;
        _chats[idx].unreadCount =
            msg['unread_count'] ?? (_chats[idx].unreadCount + 1);
        _chats[idx].isRead = _chats[idx].unreadCount == 0;
        _chats[idx].timeAgo = timestamp;
        if (status != null) _chats[idx].status = status;
      } else {
        _chats.insert(
          0,
          ChatMessage(
            name: displayName,
            username: identifier,
            lastMessage: preview,
            timeAgo: timestamp,
            avatarUrl: 'https://via.placeholder.com/50',
            isGroup: isGroup,
            isRead: false,
            unreadCount: msg['unread_count'] ?? 1,
            status: status,
          ),
        );
      }

      // Sort chats by latest timestamp
      _chats.sort((a, b) => b.timeAgo.compareTo(a.timeAgo));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Inbox',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (widget.selectMode)
            TextButton(
              child: const Text(
                'Forward',
                style: TextStyle(color: Colors.blue),
              ),
              onPressed: () {
                // --- PATCH: Return ForwardTarget list instead of just usernames ---
                final selectedTargets =
                    _chats
                        .where(
                          (chat) => _selectedUsernames.contains(chat.username),
                        )
                        .map(
                          (chat) => ForwardTarget(chat.username, chat.isGroup),
                        )
                        .toList();
                Navigator.pop(context, selectedTargets);
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110.0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Type here to search messages',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {}); // trigger rebuild for search filter
                  },
                ),
              ),
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'Groups'),
                  Tab(text: 'Single'),
                ],
                indicatorColor: Colors.black,
                labelColor: Colors.black,
              ),
            ],
          ),
        ),
      ),
      body: FutureBuilder<List<ChatMessage>>(
        future: _chatsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            final chats = snapshot.data!;
            if (_chats.isEmpty) {
              _chats = chats; // Only assign once!
            }
            final filteredChats = _filterBySearch(
              _chats,
              _searchController.text,
            );
            return TabBarView(
              controller: _tabController,
              children: [
                _buildChatList(filteredChats),
                _buildChatList(filterChats(filteredChats, true)),
                _buildChatList(filterChats(filteredChats, false)),
              ],
            );
          }
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'New Group',
          ),
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

  List<ChatMessage> _filterBySearch(List<ChatMessage> chats, String query) {
    if (query.isEmpty) return chats;
    final lowerQuery = query.toLowerCase();
    return chats.where((chat) {
      return chat.name.toLowerCase().contains(lowerQuery) ||
          chat.lastMessage.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  Widget _buildChatList(List<ChatMessage> chats) {
    if (chats.isEmpty) {
      return const Center(child: Text('No chats found.'));
    }
    return ListView.builder(
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final chat = chats[index];
        final isSelected = _selectedUsernames.contains(chat.username);

        return ListTile(
          leading: GestureDetector(
            onTap: () {
              if (!chat.isGroup) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) =>
                            EmployeeProfileScreen(username: chat.username),
                  ),
                );
              }
            },
            child: Stack(
              children: [
                CircleAvatar(backgroundImage: NetworkImage(chat.avatarUrl)),
                if (_activeUsers.contains(chat.username))
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          title: Text(
            chat.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Row(
            children: [
              // Only show status icon if this is a direct chat and I am the sender of the last message
              if (!chat.isGroup &&
                  chat.status != null &&
                  chat.lastMessage.isNotEmpty &&
                  chat.username != _currentUsername)
                Padding(
                  padding: const EdgeInsets.only(right: 2.0),
                  child: Icon(
                    chat.status == 'seen'
                        ? Icons.done_all
                        : chat.status == 'sent'
                        ? Icons.check
                        : Icons.access_time,
                    size: 16,
                    color: chat.status == 'seen' ? Colors.blue : Colors.grey,
                  ),
                ),
              if (chat.lastMessage.toLowerCase().contains('.png') ||
                  chat.lastMessage.toLowerCase().contains('.jpg') ||
                  chat.lastMessage.toLowerCase().contains('.jpeg') ||
                  chat.lastMessage.toLowerCase().contains('.gif') ||
                  chat.lastMessage.toLowerCase().contains('.bmp') ||
                  chat.lastMessage.toLowerCase().contains('.webp'))
                Padding(
                  padding: const EdgeInsets.only(right: 4.0),
                  child: Icon(Icons.image, size: 16, color: Colors.blueGrey),
                )
              else if (chat.lastMessage.toLowerCase().contains('.pdf') ||
                  chat.lastMessage.toLowerCase().contains('.docx') ||
                  chat.lastMessage.toLowerCase().contains('.doc') ||
                  chat.lastMessage.toLowerCase().contains('.xls') ||
                  chat.lastMessage.toLowerCase().contains('.ppt') ||
                  chat.lastMessage.toLowerCase().contains('.zip') ||
                  chat.lastMessage.toLowerCase().contains('.rar'))
                Padding(
                  padding: const EdgeInsets.only(right: 4.0),
                  child: Icon(
                    Icons.insert_drive_file,
                    size: 16,
                    color: Colors.blueGrey,
                  ),
                ),
              Expanded(
                child: Text(chat.lastMessage, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          trailing:
              widget.selectMode
                  ? Checkbox(
                    value: isSelected,
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedUsernames.add(chat.username);
                        } else {
                          _selectedUsernames.remove(chat.username);
                        }
                      });
                    },
                  )
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        formatChatTimestamp(chat.timeAgo),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12.0,
                        ),
                      ),
                      if (chat.unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${chat.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
          onTap:
              widget.selectMode
                  ? () {
                    setState(() {
                      if (isSelected) {
                        _selectedUsernames.remove(chat.username);
                      } else {
                        _selectedUsernames.add(chat.username);
                      }
                    });
                  }
                  : () async {
                    await markChatAsRead(chat.username, chat.isGroup);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => ChatScreen(
                              username: chat.username,
                              avatarUrl: chat.avatarUrl,
                              groupName: chat.name,
                              isGroup: chat.isGroup,
                              onNewMessage: (msg) => onNewMessage(msg),
                            ),
                      ),
                    );
                    setState(() {
                      chat.isRead = true;
                      chat.unreadCount = 0;
                    });
                  },
        );
      },
    );
  }
}

class ChatMessage {
  final String name;
  final String username;
  String lastMessage;
  String timeAgo;
  final String avatarUrl;
  final bool isGroup;
  bool isRead;
  int unreadCount;
  String? status;

  ChatMessage({
    required this.name,
    required this.username,
    required this.lastMessage,
    required this.timeAgo,
    required this.avatarUrl,
    required this.isGroup,
    this.isRead = false,
    this.unreadCount = 0,
    this.status,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      name: json['name'],
      username: json['username'],
      lastMessage: json['last_message'],
      timeAgo: json['time_ago'],
      avatarUrl: json['avatar_url'],
      isGroup: json['is_group'],
      isRead: json['is_read'] ?? false,
      unreadCount: json['unread_count'] ?? 0,
      status: json['status'],
    );
  }
}
