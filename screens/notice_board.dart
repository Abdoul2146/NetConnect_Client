import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:netconnect/server_config.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io'; // Import for File
import 'package:dio/dio.dart'; // Import Dio for downloading
import 'package:open_file/open_file.dart'; // Import for opening files
import 'package:path_provider/path_provider.dart'; // Import for file path
import 'package:permission_handler/permission_handler.dart'; // Import for permissions
import 'package:netconnect/screens/home.dart';
import 'package:netconnect/screens/settings.dart';
import 'package:netconnect/screens/inbox.dart';
import 'package:netconnect/screens/create_group.dart';
import 'package:netconnect/screens/create_post.dart';
import 'package:provider/provider.dart';
import 'package:netconnect/screens/websocket_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

class NoticeBoard {
  final String id;
  final String name;
  final String admin;
  bool isFollowed;
  final bool isAdmin;

  NoticeBoard({
    required this.id,
    required this.name,
    required this.admin,
    this.isFollowed = false,
    this.isAdmin = false,
  });

  factory NoticeBoard.fromJson(Map<String, dynamic> json) {
    return NoticeBoard(
      id: json['id'].toString(),
      name: json['name'],
      admin: json['admin'] ?? '',
      isFollowed: json['is_followed'] ?? false,
      isAdmin: json['is_admin'] ?? false,
    );
  }

  NoticeBoard copyWith({
    String? id,
    String? name,
    String? admin,
    bool? isFollowed,
    bool? isAdmin,
  }) {
    return NoticeBoard(
      id: id ?? this.id,
      name: name ?? this.name,
      admin: admin ?? this.admin,
      isFollowed: isFollowed ?? this.isFollowed,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }
}

class NoticePost {
  final String id;
  String title;
  String description;
  final String timestamp;
  final String postedBy;
  final String? attachmentPath;

  NoticePost({
    required this.id,
    required this.title,
    required this.description,
    required this.timestamp,
    required this.postedBy,
    this.attachmentPath,
  });

  factory NoticePost.fromJson(Map<String, dynamic> json) {
    return NoticePost(
      id: json['id'].toString(),
      title: json['title'],
      description: json['description'],
      timestamp: json['timestamp'],
      postedBy: json['posted_by'],
      attachmentPath: json['attachment_path'],
    );
  }
}

class NoticeBoardPage extends StatefulWidget {
  final String? initialBoardId;
  const NoticeBoardPage({super.key, this.initialBoardId});

  @override
  State<NoticeBoardPage> createState() => _NoticeBoardPageState();
}

class _NoticeBoardPageState extends State<NoticeBoardPage> {
  List<NoticeBoard> _boards = [];
  final Map<String, List<NoticePost>> _posts = {};
  bool _isLoading = true;
  String? _selectedBoardId;
  String? _loggedInUsername;
  NoticeBoard? _currentSelectedBoard;

  // State variables for download management
  final Map<String, bool> _isDownloading = {};
  final Map<String, String?> _downloadedFilePaths = {};

  @override
  void initState() {
    super.initState();
    _fetchLoggedInUsername();
    _fetchBoards().then((_) {
      if (widget.initialBoardId != null) {
        setState(() {
          _selectedBoardId = widget.initialBoardId;
          _currentSelectedBoard = _boards.firstWhereOrNull(
            (b) => b.id == _selectedBoardId,
          );
          if (_selectedBoardId != null) {
            _fetchPosts(_selectedBoardId!);
          }
        });
      }
    });
    _initNoticeBoardWebSocket();
  }

  Future<void> _fetchLoggedInUsername() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _loggedInUsername = prefs.getString('username');
      });
    }
  }

  Future<void> _deletePost(NoticePost post) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final serverIp = await ServerConfig.getServerIp();
    if (token == null || serverIp == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Post'),
            content: const Text('Are you sure you want to delete this post?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
    if (confirm != true) return;

    final url = Uri.parse(
      'http://$serverIp:8000/notice_posts/${post.id}/delete',
    );
    final response = await http.delete(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      setState(() {
        _posts[_selectedBoardId!]?.removeWhere((p) => p.id == post.id);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Post deleted')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete post: ${response.statusCode}'),
          ),
        );
      }
    }
  }

  Future<void> _editPost(NoticePost post) async {
    final titleController = TextEditingController(text: post.title);
    final descController = TextEditingController(text: post.description);

    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Edit Post'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    if (result != true) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final serverIp = await ServerConfig.getServerIp();
    if (token == null || serverIp == null) return;

    final url = Uri.parse('http://$serverIp:8000/notice_posts/${post.id}/edit');
    final response = await http.put(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'title': titleController.text.trim(),
        'description': descController.text.trim(),
      }),
    );

    if (response.statusCode == 200) {
      setState(() {
        post.title = titleController.text.trim();
        post.description = descController.text.trim();
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Post updated')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update post: ${response.statusCode}'),
          ),
        );
      }
    }
  }

  Future<void> _openFile(String url, String filename) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$filename';
    await Dio().download(url, filePath);
    await OpenFile.open(filePath);
  }

  Future<void> _saveFile(String url, String filename) async {
    // Request storage permission
    if (Platform.isAndroid) {
      // For Android 11+ (API 30+), request MANAGE_EXTERNAL_STORAGE
      if (await Permission.manageExternalStorage.isGranted == false) {
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          if (mounted) {
            // Added mounted check
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission denied')),
            );
          }
          return;
        }
      }
    }
    Directory? dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/NetConnect/NoticeBoards');
      await dir.create(recursive: true);
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    final filePath = '${dir.path}/$filename';

    try {
      await Dio().download(url, filePath);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to $filePath')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save file: $e')));
      }
    }
  }

  int _selectedIndex = 2;

  void _onItemTapped(int index) {
    if (mounted) {
      setState(() {
        _selectedIndex = index;
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const UsersScreen()),
          );
        } else if (index == 1) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const CreateGroupScreen()),
          );
        } else if (index == 2) {
          // Current screen
        } else if (index == 3) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const InboxScreen()),
          );
        } else if (index == 4) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const NetworkSettingsScreen(),
            ),
          );
        }
      });
    }
  }

  Future<void> _fetchBoards() async {
    if (mounted) setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final serverIp = await ServerConfig.getServerIp();
    if (token == null || serverIp == null) {
      if (mounted) setState(() => _isLoading = false);
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
          _boards = data.map((json) => NoticeBoard.fromJson(json)).toList();
          _isLoading = false;
          if (widget.initialBoardId != null) {
            _selectedBoardId = widget.initialBoardId;
            _currentSelectedBoard = _boards.firstWhereOrNull(
              (b) => b.id == _selectedBoardId,
            );
            if (_selectedBoardId != null) {
              _fetchPosts(_selectedBoardId!);
            }
          } else {
            // Always default to "Select Board" (null)
            _selectedBoardId = null;
            _currentSelectedBoard = null;
          }
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchPosts(String boardId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final serverIp = await ServerConfig.getServerIp();
    if (token == null || serverIp == null) return;
    final response = await http.get(
      Uri.parse('http://$serverIp:8000/notice_boards/$boardId/posts'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      if (mounted) {
        setState(() {
          _posts[boardId] =
              data.map((json) => NoticePost.fromJson(json)).toList();
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _posts.remove(boardId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select a board to view posts.')),
        );
      }
    }
  }

  void _showCreateBoardDialog() {
    final boardNameController = TextEditingController();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Create Notice Board'),
            content: TextField(
              controller: boardNameController,
              decoration: const InputDecoration(hintText: 'Board Name'),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final name = boardNameController.text.trim();
                  if (name.isNotEmpty) {
                    final prefs = await SharedPreferences.getInstance();
                    final token = prefs.getString('access_token');
                    final serverIp = await ServerConfig.getServerIp();
                    if (token == null || serverIp == null) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Not authenticated or server IP missing.',
                            ),
                          ),
                        );
                      }
                      return;
                    }
                    final response = await http.post(
                      Uri.parse('http://$serverIp:8000/notice_boards'),
                      headers: {
                        'Authorization': 'Bearer $token',
                        'Content-Type': 'application/x-www-form-urlencoded',
                      },
                      body: {'name': name},
                    );
                    if (response.statusCode == 200) {
                      if (mounted) Navigator.pop(context);
                      _fetchBoards();
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to create board: ${response.body}',
                            ),
                          ),
                        );
                      }
                    }
                  }
                },
                child: const Text('Create'),
              ),
            ],
          ),
    );
  }

  void _initNoticeBoardWebSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    final token = prefs.getString('access_token');
    final serverIp = await ServerConfig.getServerIp();
    if (username != null && token != null && serverIp != null) {
      final wsUrl = Uri.parse('ws://$serverIp:8000/ws/$username?token=$token');
      final noticeBoardChannel = WebSocketChannel.connect(wsUrl);

      noticeBoardChannel.stream.listen(
        (data) {
          try {
            final msg = json.decode(data);
            if (msg['type'] == 'notice_post') {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('New Notice: ${msg['title']}')),
                );
              }
              final boardName = msg['board'];
              final board = _boards.firstWhereOrNull(
                (b) => b.name == boardName,
              );
              if (board != null && board.id == _selectedBoardId) {
                _fetchPosts(board.id);
              }
            }
          } catch (e, stack) {
            debugPrint('NoticeBoard WebSocket message error: $e\n$stack');
          }
        },
        onError: (error) => debugPrint('NoticeBoard WebSocket error: $error'),
        onDone: () => debugPrint('NoticeBoard WebSocket connection closed'),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webSocketProvider = Provider.of<WebSocketProvider>(context);
    final NoticeBoard? currentBoard = _currentSelectedBoard;

    // Add this before DropdownButtonFormField in your build method:

    final availableBoards =
        _boards.where((b) => b.isFollowed || b.isAdmin).toList();
    if (_selectedBoardId != null &&
        !availableBoards.any((b) => b.id == _selectedBoardId)) {
      // The selected board is not in the dropdown, reset selection
      _selectedBoardId = null;
      _currentSelectedBoard = null;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notice Board',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        // centerTitle: false,
        // // backgroundColor: Colors.white,
        // // elevation: 1,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SizedBox(
                      // <--- Add SizedBox here
                      width: 300.0, // <--- Set your desired fixed width
                      child: DropdownButtonFormField<String>(
                        value: _selectedBoardId,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Select Board'),
                          ),
                          ..._boards
                              .where((b) => b.isFollowed || b.isAdmin)
                              .map(
                                (b) => DropdownMenuItem(
                                  value: b.id,
                                  child: Row(
                                    children: [
                                      Text(b.name),
                                      const SizedBox(width: 8),
                                      if (b.isFollowed)
                                        const Icon(
                                          Icons.check,
                                          color: Colors.green,
                                          size: 16,
                                        ),
                                      if (b.isAdmin)
                                        const Icon(
                                          Icons.star,
                                          color: Colors.amber,
                                          size: 16,
                                        ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedBoardId = val;
                            _currentSelectedBoard = _boards.firstWhereOrNull(
                              (b) => b.id == _selectedBoardId,
                            );
                            if (val != null) _fetchPosts(val);
                          });
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Select Board',
                        ),
                      ),
                    ),
                  ),
                  if (_selectedBoardId != null &&
                      currentBoard != null &&
                      !currentBoard.isAdmin)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: Icon(
                            currentBoard.isFollowed
                                ? Icons.remove_circle
                                : Icons.add_circle,
                            color: Colors.blue,
                          ),
                          label: Text(
                            currentBoard.isFollowed ? 'Unfollow' : 'Follow',
                          ),
                          onPressed: () async {
                            final boardToToggle = currentBoard;
                            final prefs = await SharedPreferences.getInstance();
                            final token = prefs.getString('access_token');
                            final serverIp = await ServerConfig.getServerIp();
                            if (token == null || serverIp == null) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Authentication or server IP missing.',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
                            final url =
                                boardToToggle.isFollowed
                                    ? 'http://$serverIp:8000/notice_boards/${boardToToggle.id}/unfollow'
                                    : 'http://$serverIp:8000/notice_boards/${boardToToggle.id}/follow';
                            final response = await http.post(
                              Uri.parse(url),
                              headers: {'Authorization': 'Bearer $token'},
                            );
                            if (response.statusCode == 200) {
                              await _fetchBoards();
                              if (mounted) {
                                setState(() {
                                  _selectedBoardId = boardToToggle.id;
                                  _currentSelectedBoard = _boards
                                      .firstWhereOrNull(
                                        (b) => b.id == _selectedBoardId,
                                      );
                                });
                                final refreshedBoard = _boards.firstWhereOrNull(
                                  (b) => b.id == boardToToggle.id,
                                );
                                if (refreshedBoard != null &&
                                    refreshedBoard.isFollowed) {
                                  _fetchPosts(boardToToggle.id);
                                } else {
                                  if (mounted) {
                                    setState(
                                      () => _posts.remove(boardToToggle.id),
                                    );
                                  }
                                }
                              }
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Failed to update follow status',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  Expanded(
                    child:
                        _selectedBoardId == null
                            ? const Center(
                              child: Text('Please select a board.'),
                            )
                            : (_currentSelectedBoard != null &&
                                !_currentSelectedBoard!.isFollowed &&
                                !_currentSelectedBoard!.isAdmin)
                            ? const Center(
                              child: Text(
                                'You are not following this board.',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                            : (_posts[_selectedBoardId!] == null ||
                                _posts[_selectedBoardId!]!.isEmpty)
                            ? const Center(child: Text('No posts found.'))
                            : ListView.builder(
                              padding: const EdgeInsets.only(
                                bottom: 80,
                              ), // Add padding for FAB
                              itemCount: _posts[_selectedBoardId!]!.length,
                              itemBuilder: (context, idx) {
                                final post = _posts[_selectedBoardId!]![idx];
                                final bool isAuthorOnline = webSocketProvider
                                    .isUserOnline(post.postedBy);
                                final bool isFileDownloaded =
                                    _downloadedFilePaths[post.id] != null;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 12,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              post.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              onSelected: (value) async {
                                                if (value == 'edit') {
                                                  await _editPost(post);
                                                } else if (value == 'delete') {
                                                  await _deletePost(post);
                                                }
                                              },
                                              itemBuilder:
                                                  (context) => [
                                                    const PopupMenuItem(
                                                      value: 'edit',
                                                      child: Text('Edit'),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text('Delete'),
                                                    ),
                                                  ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(post.description),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Text('By: ${post.postedBy}'),
                                            const SizedBox(width: 8),
                                            if (isAuthorOnline)
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: Colors.green,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white,
                                                    width: 1.5,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        Text(
                                          'At: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.tryParse(post.timestamp)?.toLocal() ?? DateTime.now())}',
                                        ),
                                        // MODIFIED: Attachment buttons section
                                        if (post.attachmentPath != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 12.0,
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.attach_file,
                                                  color: Colors.grey,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    p.basename(
                                                      post.attachmentPath
                                                              ?.replaceAll(
                                                                '\\',
                                                                '/',
                                                              ) ??
                                                          '',
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.black54,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),

                                                // Spinner or Download/Open buttons
                                                _isDownloading[post.id] == true
                                                    ? const SizedBox(
                                                      height: 24,
                                                      width: 24,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2.5,
                                                          ),
                                                    )
                                                    : Row(
                                                      children: [
                                                        // Download Button
                                                        InkWell(
                                                          onTap:
                                                              isFileDownloaded
                                                                  ? null
                                                                  : () async {
                                                                    final serverIp =
                                                                        await ServerConfig.getServerIp();
                                                                    if (serverIp ==
                                                                        null) {
                                                                      return;
                                                                    }
                                                                    final url =
                                                                        'http://$serverIp:8000/${post.attachmentPath}';
                                                                    final filename = p.basename(
                                                                      post.attachmentPath!
                                                                          .replaceAll(
                                                                            '\\',
                                                                            '/',
                                                                          ),
                                                                    );
                                                                    await _saveFile(
                                                                      url,
                                                                      filename,
                                                                    ); // Save to device storage
                                                                  },
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                20,
                                                              ),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  8,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  isFileDownloaded
                                                                      ? Colors
                                                                          .grey
                                                                          .withOpacity(
                                                                            0.1,
                                                                          )
                                                                      : Colors
                                                                          .blue
                                                                          .withOpacity(
                                                                            0.1,
                                                                          ),
                                                              shape:
                                                                  BoxShape
                                                                      .circle,
                                                            ),
                                                            child: Icon(
                                                              Icons
                                                                  .download_rounded,
                                                              color:
                                                                  isFileDownloaded
                                                                      ? Colors
                                                                          .grey
                                                                      : Colors
                                                                          .blue,
                                                              size: 20,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        // Open Button
                                                        InkWell(
                                                          onTap: () async {
                                                            final serverIp =
                                                                await ServerConfig.getServerIp();
                                                            if (serverIp ==
                                                                null)
                                                              return;
                                                            final url =
                                                                'http://$serverIp:8000/${post.attachmentPath}';
                                                            final filename = p
                                                                .basename(
                                                                  post.attachmentPath!,
                                                                );
                                                            await _openFile(
                                                              url,
                                                              filename,
                                                            ); // Open file (downloads to temp, then opens)
                                                          },
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                20,
                                                              ),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  8,
                                                                ),
                                                            decoration:
                                                                BoxDecoration(
                                                                  color: Colors
                                                                      .green
                                                                      .withOpacity(
                                                                        0.1,
                                                                      ),
                                                                  shape:
                                                                      BoxShape
                                                                          .circle,
                                                                ),
                                                            child: const Icon(
                                                              Icons
                                                                  .open_in_new_rounded,
                                                              color:
                                                                  Colors.green,
                                                              size: 20,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                  ),
                ],
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Allow board creation if no board is selected (neutral ground)
          if (_selectedBoardId == null) {
            final result = await showDialog(
              context: context,
              builder:
                  (context) => SimpleDialog(
                    title: const Text('Actions'),
                    children: [
                      SimpleDialogOption(
                        child: const Text('Create Board'),
                        onPressed: () => Navigator.pop(context, 'board'),
                      ),
                    ],
                  ),
            );
            if (result == 'board') {
              _showCreateBoardDialog();
            }
            return;
          }

          // Existing logic for when a board is selected
          if (!_isAdmin()) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Select a board and ensure you are its admin to create content.',
                  ),
                ),
              );
            }
            return;
          }
          final result = await showDialog(
            context: context,
            builder:
                (context) => SimpleDialog(
                  title: const Text('Actions'),
                  children: [
                    SimpleDialogOption(
                      child: const Text('Create Board'),
                      onPressed: () => Navigator.pop(context, 'board'),
                    ),
                    SimpleDialogOption(
                      child: const Text('Create Post'),
                      onPressed: () => Navigator.pop(context, 'post'),
                    ),
                  ],
                ),
          );
          if (result == 'board') {
            _showCreateBoardDialog();
          } else if (result == 'post') {
            final created = await Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) => CreatePostPage(boardId: _selectedBoardId!),
              ),
            );
            if (created == true && _selectedBoardId != null) {
              _fetchPosts(_selectedBoardId!);
            }
          }
        },
        backgroundColor: Colors.black,
        child: const Icon(Icons.add),
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

  bool _isAdmin() {
    if (_selectedBoardId == null || _loggedInUsername == null) return false;
    final board = _boards.firstWhereOrNull((b) => b.id == _selectedBoardId);
    return board != null && board.isAdmin;
  }
}

extension IterableExtension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
