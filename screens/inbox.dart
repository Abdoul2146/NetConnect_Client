import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:netconnect/screens/create_group.dart';
import 'home.dart';
import 'settings.dart';
import 'package:netconnect/screens/chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
// REMOVED: import 'package:web_socket_channel/web_socket_channel.dart'; // WebSocket management moved to Provider
import 'package:netconnect/screens/profile.dart';
import 'package:intl/intl.dart';
import 'package:netconnect/server_config.dart';
import 'package:netconnect/screens/notice_board.dart';
import 'package:provider/provider.dart'; // NEW: Import provider
import 'package:netconnect/screens/websocket_provider.dart'; // NEW: Import your WebSocketProvider

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
  // REMOVED: late WebSocketChannel _channel; // WebSocket management moved to Provider
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  late Future<List<ChatMessage>> _chatsFuture;
  List<ChatMessage> _chats = []; // Store fetched chats
  int _selectedIndex = 3; // Default to Inbox tab in bottom navigation
  late String
  _currentUsername; // RETAINED: Used for determining 'isMe' for last message status
  final Set<String> _selectedUsernames = {}; // For selectMode
  // REMOVED: Set<String> _activeUsers = {}; // Active users now managed by WebSocketProvider

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _chatsFuture = fetchChats();

    // The entire WebSocket connection and status listener logic moved out.
    // The global WebSocketProvider handles this now.
    Future.microtask(() async {
      final prefs = await SharedPreferences.getInstance();
      _currentUsername = prefs.getString('username') ?? 'Unknown';
      // No WebSocket connection setup here, it's done once in main.dart / splash screen.
      // This is primarily for the _currentUsername for message status display.
    });

    // NEW: Listen to the WebSocketProvider's stream for message updates
    // This is crucial for updating chat previews in real-time
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<WebSocketProvider>(
        context,
        listen: false,
      ).incomingMessages.listen((msg) {
        // This listener will now receive all messages (direct, group, status, etc.)
        // from the central WebSocketProvider.
        // We only care about chat preview updates here.
        if (msg['type'] == 'chat_preview_update' ||
            msg['type'] == 'direct_message' ||
            msg['type'] == 'group_message' ||
            msg['type'] == 'message_status') {
          // message_status for sender's status
          onNewMessage(msg); // Use the existing onNewMessage logic
        }
        // User active/status messages are handled by the WebSocketProvider itself,
        // and InboxScreen will get status via Provider.of<WebSocketProvider>(context) in build.
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    // REMOVED: _channel.sink.close(); // WebSocket management moved to Provider
    super.dispose();
  }

  Future<void> markChatAsRead(String username, bool isGroup) async {
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
      } else if (index == 4) {
        print('Settings Tapped');
        // This is the current screen, no need to navigate
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const NetworkSettingsScreen(),
          ),
        );
      }
    });
  }

  // MODIFIED: onNewMessage to also handle 'status' messages if needed, and ensure correct sorting
  void onNewMessage(Map<String, dynamic> msg) {
    print('🔄 WebSocket message received in Inbox: $msg');
    setState(() {
      // Handle message status updates for sender's last message status icon
      if (msg['type'] == 'message_status') {
        final status = msg['status'];
        final String? fromUser =
            msg['from']; // The sender of the original message
        final String? toUser =
            msg['to']; // The receiver of the original message

        // Find the chat affected by this status change
        int chatIdx = _chats.indexWhere((chat) {
          // If it's a direct chat and the sender or receiver of the status update matches this chat
          return !chat.isGroup &&
              (chat.username == fromUser || chat.username == toUser);
        });

        if (chatIdx != -1) {
          // If it's *my* message that received a status update
          if (_chats[chatIdx].username == toUser &&
              _currentUsername == fromUser) {
            // I sent, they received
            _chats[chatIdx].status = status; // Update chat preview status
          }
        }
        // For incoming messages to this chat (where I am receiver and they send)
        // the status will be implicitly updated when I read the chat.
      } else {
        // Handle 'chat_preview_update', 'direct_message', 'group_message' types for previews
        bool isGroup =
            msg['chat_type'] == 'group' ||
            msg['is_group'] == true ||
            msg['type'] ==
                'group_message'; // extra check for group_message type

        String identifier;
        String displayName;

        if (isGroup) {
          identifier = (msg['group'] ?? msg['chat_id'] ?? '').toString();
          displayName = identifier;
        } else {
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
        DateTime lastMessageTime =
            DateTime.tryParse(timestamp) ?? DateTime.now();
        String? status = msg['status']; // Status of the last message in chat

        if (idx != -1) {
          _chats[idx].lastMessage = preview;
          _chats[idx].unreadCount =
              msg['unread_count'] ?? (_chats[idx].unreadCount + 1);
          _chats[idx].isRead = _chats[idx].unreadCount == 0;
          _chats[idx].timeAgo = timestamp;
          _chats[idx].lastMessageTime = lastMessageTime; // NEW
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
              lastMessageTime: lastMessageTime, // NEW
            ),
          );
        }
      } // End of message type check

      // Sort chats by latest DateTime, not string
      _chats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    });
  }

  @override
  Widget build(BuildContext context) {
    // NEW: Consume the WebSocketProvider
    final webSocketProvider = Provider.of<WebSocketProvider>(context);

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
              _chats = chats; // Only assign once on initial load
              // Important: _chats can be mutated by onNewMessage, so no direct `snapshot.data!` usage after first assignment
            }
            final filteredChats = _filterBySearch(
              _chats, // Use the mutable _chats list here
              _searchController.text,
            );
            return TabBarView(
              controller: _tabController,
              children: [
                _buildChatList(
                  filteredChats,
                  webSocketProvider,
                ), // Pass provider
                _buildChatList(
                  filterChats(filteredChats, true),
                  webSocketProvider,
                ), // Pass provider
                _buildChatList(
                  filterChats(filteredChats, false),
                  webSocketProvider,
                ), // Pass provider
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

  List<ChatMessage> _filterBySearch(List<ChatMessage> chats, String query) {
    if (query.isEmpty) return chats;
    final lowerQuery = query.toLowerCase();
    return chats.where((chat) {
      return chat.name.toLowerCase().contains(lowerQuery) ||
          chat.lastMessage.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  // MODIFIED: _buildChatList to accept WebSocketProvider
  Widget _buildChatList(
    List<ChatMessage> chats,
    WebSocketProvider webSocketProvider,
  ) {
    if (chats.isEmpty) {
      return const Center(child: Text('No chats found.'));
    }
    return ListView.builder(
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final chat = chats[index];
        final isSelected = _selectedUsernames.contains(chat.username);
        // NEW: Determine if the chat partner is online using the provider
        final isChatPartnerOnline =
            !chat.isGroup && webSocketProvider.isUserOnline(chat.username);

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
                // NEW: Show online indicator based on provider status
                if (isChatPartnerOnline) // Use the new variable
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
              // RETAINED: Existing message status logic
              if (!chat.isGroup &&
                  chat.status != null &&
                  chat.lastMessage.isNotEmpty &&
                  chat.username !=
                      _currentUsername) // Ensure it's not a message FROM ME
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
  DateTime lastMessageTime; // NEW FIELD

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
    required this.lastMessageTime, // NEW
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final timeString = json['time_ago'] ?? DateTime.now().toIso8601String();
    return ChatMessage(
      name: json['name'],
      username: json['username'],
      lastMessage: json['last_message'],
      timeAgo: timeString,
      avatarUrl: json['avatar_url'],
      isGroup: json['is_group'],
      isRead: json['is_read'] ?? false,
      unreadCount: json['unread_count'] ?? 0,
      status: json['status'],
      lastMessageTime: DateTime.tryParse(timeString) ?? DateTime.now(), // NEW
    );
  }
}
