import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'edit_profile.dart';
import 'package:netconnect/screens/chat_screen.dart';
import 'package:netconnect/server_config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class EmployeeProfileScreen extends StatefulWidget {
  final String?
  username; // If null, fetch current user. If provided, fetch that user.

  const EmployeeProfileScreen({super.key, this.username});

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  Map<String, dynamic>? profile;
  bool isLoading = true;
  bool isCurrentUser = false;
  String? loggedInUsername;
  Set<String> _activeUsers = {};
  late WebSocketChannel _channel;

  @override
  void initState() {
    super.initState();
    _initUser();
    _initWebSocket();
  }

  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  void _initUser() async {
    final prefs = await SharedPreferences.getInstance();
    loggedInUsername = prefs.getString('username');
    setState(() {
      isCurrentUser =
          (widget.username == null || widget.username == loggedInUsername);
    });
    fetchProfile();
  }

  void _initWebSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    final token = prefs.getString('access_token');
    final serverIp = await ServerConfig.getServerIp();
    if (username != null && token != null && serverIp != null) {
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://$serverIp:8000/ws/$username?token=$token'),
      );
      _channel.stream.listen((data) {
        final msg = json.decode(data);
        if (msg['type'] == 'user_active' || msg['type'] == 'status') {
          setState(() {
            if (msg['status'] == 'online' || msg['active'] == true) {
              _activeUsers.add(msg['username']);
            } else {
              _activeUsers.remove(msg['username']);
            }
          });
        }
      });
    }
  }

  Future<void> fetchProfile() async {
    try {
      String? token = await getStoredToken();
      String? usernameToFetch = widget.username ?? loggedInUsername;

      if (usernameToFetch == null || token == null) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please login first')));
        return;
      }

      final serverIp = await ServerConfig.getServerIp();
      if (serverIp == null) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Server IP not set. Please configure network settings.',
            ),
          ),
        );
        return;
      }
      final response = await http.get(
        Uri.parse('http://$serverIp:8000/profile/$usernameToFetch'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          profile = json.decode(response.body);
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response.statusCode}')),
        );
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Network error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          // Only show edit button for current user
          if (isCurrentUser)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final updated = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => EditProfileScreen(
                          profile: profile!,
                          isCurrentUser: true,
                        ),
                  ),
                );
                if (updated == true) {
                  fetchProfile();
                }
              },
            ),
        ],
      ),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : profile == null
              ? const Center(child: Text('Profile not found'))
              : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      const SizedBox(height: 24.0),
                      CircleAvatar(
                        radius: 60.0,
                        backgroundImage:
                            profile!['avatar_url'] != null
                                ? NetworkImage(profile!['avatar_url'])
                                : const NetworkImage(
                                  'https://via.placeholder.com/300/CCCCCC/000000?Text=Employee',
                                ),
                      ),
                      const SizedBox(height: 16.0),
                      Text(
                        profile!['name'] ?? 'Employee Name',
                        style: const TextStyle(
                          fontSize: 20.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8.0,
                            height: 8.0,
                            decoration: BoxDecoration(
                              color:
                                  _activeUsers.contains(profile!['username'])
                                      ? Colors.green
                                      : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4.0),
                          Text(
                            _activeUsers.contains(profile!['username'])
                                ? 'Online'
                                : 'Offline',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24.0),
                      _buildInfoRow('Job role', profile!['job_title'] ?? ''),
                      _buildInfoRow('Contact email', profile!['email'] ?? ''),
                      _buildInfoRow('Contact', profile!['contact'] ?? ''),
                      _buildInfoRow('username', profile!['username'] ?? ''),
                      const SizedBox(height: 32.0),
                      // Only show message button for other users
                      if (!isCurrentUser)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              final username = profile?['username'];
                              // Provide a default avatar if missing
                              final avatarUrl =
                                  (profile?['avatar_url'] as String?)
                                              ?.isNotEmpty ==
                                          true
                                      ? profile!['avatar_url']
                                      : 'https://via.placeholder.com/300/CCCCCC/000000?Text=Employee';

                              if (username == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('User data is incomplete'),
                                  ),
                                );
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => ChatScreen(
                                        username: username,
                                        avatarUrl: avatarUrl,
                                        isGroup: false,
                                        groupName: null,
                                      ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 16.0,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                            ),
                            child: const Text(
                              'Message',
                              style: TextStyle(fontSize: 16.0),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _channel.sink.close();
    super.dispose();
  }
}
