import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart'; // NEW: Import provider
import 'package:netconnect/screens/websocket_provider.dart'; // NEW: Import your WebSocketProvider
import 'edit_profile.dart';
import 'package:netconnect/screens/chat_screen.dart'; // Make sure this path is correct
import 'package:netconnect/server_config.dart';
import 'package:netconnect/screens/update_password.dart';

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

  // REMOVED: bool _isProfileUserOnline = false; // Status will now come from WebSocketProvider
  // REMOVED: late WebSocketChannel _channel;
  // REMOVED: Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _initUserAndFetchProfile(); // This now only fetches profile data
  }

  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  void _initUserAndFetchProfile() async {
    final prefs = await SharedPreferences.getInstance();
    loggedInUsername = prefs.getString('username');
    setState(() {
      isCurrentUser =
          (widget.username == null || widget.username == loggedInUsername);
    });
    await fetchProfile(); // Fetch profile data
    // REMOVED: _initWebSocket(); // WebSocket initialization is now handled globally by WebSocketProvider
  }

  // REMOVED: _initWebSocket method (its logic is now in WebSocketProvider)
  // REMOVED: _startHeartbeat method
  // REMOVED: _stopHeartbeat method

  Future<void> fetchProfile() async {
    try {
      String? token = await getStoredToken();
      String? usernameToFetch = widget.username ?? loggedInUsername;

      if (usernameToFetch == null || token == null) {
        setState(() {
          isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Please login first')));
        }
        return;
      }

      final serverIp = await ServerConfig.getServerIp();
      if (serverIp == null) {
        setState(() {
          isLoading = false;
        });
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
          // REMOVED: _isProfileUserOnline = profile!['is_online'] ?? false;
          // The WebSocketProvider will manage the real-time status dynamically.
          // The initial fetch no longer sets the UI status directly.
        });
      } else {
        setState(() {
          isLoading = false;
          // REMOVED: _isProfileUserOnline = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        // REMOVED: _isProfileUserOnline = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Network error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // NEW: Get the WebSocketProvider instance
    final webSocketProvider = Provider.of<WebSocketProvider>(context);

    // NEW: Determine the online status of the profile user from the provider
    bool isProfileUserOnline = false;
    if (profile != null && profile!['username'] != null) {
      isProfileUserOnline = webSocketProvider.isUserOnline(
        profile!['username'],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          profile?['name'] ?? 'Profile',
        ), // Set app bar title based on profile name
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
                  fetchProfile(); // Re-fetch profile if updated
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
                      if (!isCurrentUser)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8.0,
                              height: 8.0,
                              decoration: BoxDecoration(
                                color:
                                    isProfileUserOnline
                                        ? Colors.green
                                        : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4.0),
                            Text(
                              isProfileUserOnline ? 'Online' : 'Offline',
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
                      // Only show update password for current user
                      if (isCurrentUser)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => UpdatePasswordScreen(
                                        username: profile!['username'],
                                        requireCurrentPassword: true,
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
                              'Update Password',
                              style: TextStyle(fontSize: 16.0),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16.0),
                      // Only show message button for other users
                      if (!isCurrentUser)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              final username = profile?['username'];
                              final avatarUrl =
                                  (profile?['avatar_url'] as String?)
                                              ?.isNotEmpty ==
                                          true
                                      ? profile!['avatar_url']
                                      : 'https://via.placeholder.com/300/CCCCCC/000000?Text=Employee';

                              if (username == null) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('User data is incomplete'),
                                    ),
                                  );
                                }
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
    // REMOVED: _heartbeatTimer?.cancel();
    // REMOVED: _channel.sink.close();
    // WebSocketProvider manages the connection and timer globally.
    super.dispose();
  }
}
