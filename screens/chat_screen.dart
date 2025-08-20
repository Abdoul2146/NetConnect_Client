import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart'; // RETAINED: Local WebSocket management
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'inbox.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:netconnect/screens/profile.dart';
import 'package:netconnect/server_config.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart'; // NEW: Import provider
import 'package:netconnect/screens/websocket_provider.dart'; // NEW: Import your WebSocketProvider

class ChatScreen extends StatefulWidget {
  final String? username; // chat partner's username
  final String avatarUrl;
  final String? groupName;
  final bool isGroup;
  final Function(Map<String, dynamic>)? onNewMessage;

  const ChatScreen({
    super.key,
    this.username,
    required this.avatarUrl,
    this.groupName,
    this.isGroup = false,
    this.onNewMessage,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  WebSocketChannel? _channel; // RETAINED: Local WebSocket channel for messaging
  String? _currentUsername; // RETAINED: Current username
  String? _token; // RETAINED: Token
  PlatformFile? _pendingFile;
  String? _pendingFileMimeType;
  bool _showJumpToLatest = false;
  // REMOVED: Set<String> _activeUsers = {}; // Active users now managed by WebSocketProvider

  @override
  void initState() {
    super.initState();
    _initCredentialsAndConnect(); // RETAINED: Calls local WebSocket setup
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // Show FAB if not near the bottom (e.g., more than 100px away)
    final shouldShow = (maxScroll - currentScroll) > 100;
    if (_showJumpToLatest != shouldShow) {
      setState(() {
        _showJumpToLatest = shouldShow;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addMessageAndScroll(ChatMessage message) {
    setState(() {
      _messages.add(message);
    });
    _scrollToBottom();
  }

  Future<void> _deleteMessage(ChatMessage m) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final serverIp = await ServerConfig.getServerIp();
    if (token == null || serverIp == null || m.id == null) return;

    late Uri url;
    if (widget.isGroup && widget.groupName != null) {
      // Use group message endpoint
      url = Uri.parse('http://$serverIp:8000/group_messages/${m.id}/delete');
    } else {
      // Use direct message endpoint
      url = Uri.parse('http://$serverIp:8000/messages/${m.id}/delete');
    }

    final response = await http.delete(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      setState(() {
        _messages.removeWhere((msg) => msg.id == m.id);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message deleted')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete message: ${response.statusCode}'),
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
    // Get downloads directory
    Directory? dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/NetConnect');
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    final filePath = '${dir.path}/$filename';

    try {
      await Dio().download(url, filePath);
      if (mounted) {
        // Added mounted check
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to $filePath')));
      }
    } catch (e) {
      if (mounted) {
        // Added mounted check
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save file: $e')));
      }
    }
  }

  void _removeSystemMessages() {
    setState(() {
      _messages.removeWhere(
        (m) =>
            m.sender.toLowerCase().contains('system') || m.sender == 'System',
      );
    });
  }

  List<ChatMessage> _filteredMessages() {
    int firstUserMsgIdx = _messages.indexWhere((m) {
      bool isNotSystem =
          !(m.sender.toLowerCase().contains('system') || m.sender == 'System');
      bool hasContent =
          m.text.trim().isNotEmpty ||
          (m.filePath != null && m.filePath!.isNotEmpty);

      return isNotSystem && hasContent;
    });

    if (firstUserMsgIdx >= 0) {
      return _messages.sublist(firstUserMsgIdx);
    }
    return _messages;
  }

  Future<void> _fetchMessageHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final myUsername = prefs.getString('username');
    if (myUsername == null || token == null) return;

    final serverIp3 = await ServerConfig.getServerIp();
    if (serverIp3 == null) {
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
    Uri url;
    if (widget.isGroup && widget.groupName != null) {
      url = Uri.parse(
        'http://$serverIp3:8000/groups/${widget.groupName}/messages',
      );
    } else {
      final serverIp4 = await ServerConfig.getServerIp();
      if (serverIp4 == null) {
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
      url = Uri.parse(
        'http://$serverIp4:8000/messages/$myUsername/${widget.username}',
      );
    }
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> messages = data['messages'];
      setState(() {
        _messages.clear();
        _messages.addAll(
          messages.map((msg) {
            String text;
            String? attachedMessage;
            if (msg['file_path'] != null &&
                msg['file_path'].toString().isNotEmpty) {
              final fileName = msg['file_path'].toString().split('/').last;
              String fileType = msg['file_type'] ?? '';
              if (fileType.contains('/')) {
                fileType = fileType.split('/').last.toUpperCase();
              }
              text = '[${fileType.isNotEmpty ? fileType : "File"}] $fileName';
              attachedMessage = msg['content'];
            } else {
              text = msg['content'] ?? '';
              attachedMessage = null;
            }

            final forwardedInfo = ForwardedInfo.fromJson(msg['forwarded_from']);

            return ChatMessage(
              id: msg['id'],
              text: text,
              timestamp: DateTime.parse(msg['timestamp']),
              isMe: msg['from'] == myUsername,
              sender: msg['from'] ?? '',
              filePath: msg['file_path'],
              fileType: msg['file_type'],
              attachedMessage: attachedMessage,
              forwardedInfo: forwardedInfo,
            );
          }),
        );
      });
      _removeSystemMessages();
      _scrollToBottom();
    } else {
      print('Failed to fetch messages: ${response.body}');
    }
  }

  // MODIFIED METHOD: Removed 'user_active' and 'status' handling.
  Future<void> _initCredentialsAndConnect() async {
    print('Initializing credentials and connecting...');
    final prefs = await SharedPreferences.getInstance();
    _currentUsername = prefs.getString('username');
    _token = prefs.getString('access_token');
    print('logged in as $_currentUsername with token $_token');

    if (_currentUsername != null && _token != null) {
      await _fetchMessageHistory();
      await _markChatAsRead();

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

      final wsUrl = Uri.parse(
        'ws://$serverIp:8000/ws/$_currentUsername?token=$_token',
      );
      print('Connecting to WebSocket at $wsUrl');

      _channel = WebSocketChannel.connect(wsUrl);

      _channel!.stream.listen(
        (data) {
          print('Received from WebSocket: $data');
          final msg = json.decode(data);

          // REMOVED: User active status handling from here.
          // This is now handled by the global WebSocketProvider.
          // if (msg['type'] == 'user_active' || msg['type'] == 'status') {
          //   setState(() {
          //     if (msg['status'] == 'online' || msg['active'] == true) {
          //       _activeUsers.add(msg['username']);
          //     } else {
          //       _activeUsers.remove(msg['username']);
          //     }
          //   });
          // }

          // --- Message status (sent/seen) ---
          if (msg['type'] == 'message_status') {
            final id = msg['message_id'];
            final status = msg['status'];
            setState(() {
              final idx = _messages.indexWhere((m) => m.id == id);
              if (idx != -1) {
                _messages[idx] = _messages[idx].copyWith(status: status);
              }
            });
          }

          // --- Direct messages ---
          if (msg['type'] == 'direct_message') {
            if ((msg['from'] == widget.username &&
                    msg['to'] == _currentUsername) ||
                (msg['from'] == _currentUsername &&
                    msg['to'] == widget.username)) {
              String text;
              String? attachedMessage;
              if (msg['file_path'] != null &&
                  msg['file_path'].toString().isNotEmpty) {
                final fileName = msg['file_path'].toString().split('/').last;
                String fileType = msg['file_type'] ?? '';
                if (fileType.contains('/')) {
                  fileType = fileType.split('/').last.toUpperCase();
                }
                text = '[${fileType.isNotEmpty ? fileType : "File"}] $fileName';
                attachedMessage = msg['content'];
              } else {
                text = msg['content'] ?? '';
                attachedMessage = null;
              }

              final forwardedInfo = ForwardedInfo.fromJson(
                msg['forwarded_from'],
              );

              final chatMsg = ChatMessage(
                id: int.tryParse(msg['id']?.toString() ?? ''),
                text: text,
                timestamp:
                    DateTime.tryParse(msg['timestamp'] ?? '') ?? DateTime.now(),
                isMe: msg['from'] == _currentUsername,
                sender: msg['from'] ?? 'Unknown',
                filePath: msg['file_path'],
                fileType: msg['file_type'],
                attachedMessage: attachedMessage,
                forwardedInfo: forwardedInfo,
                status: msg['isMe'] == true ? 'sent' : '',
              );

              _addMessageAndScroll(chatMsg);
            }
          }

          // ...same for group messages...
          if (msg['type'] == 'group_message' &&
              msg['group'] == widget.groupName) {
            String text;
            String? attachedMessage;
            if (msg['file_path'] != null &&
                msg['file_path'].toString().isNotEmpty) {
              String fileType = msg['file_type'] ?? '';
              if (fileType.contains('/')) {
                fileType = fileType.split('/').last.toUpperCase();
              }
              final fileName = msg['file_path'].toString().split('/').last;
              text = '[${fileType.isNotEmpty ? fileType : "File"}] $fileName';
              attachedMessage = msg['content'];
            } else {
              text = msg['content'] ?? '';
              attachedMessage = null;
            }

            final forwardedInfo = ForwardedInfo.fromJson(msg['forwarded_from']);
            print('Received group message: $msg');

            final groupMsg = ChatMessage(
              id: int.tryParse(msg['id']?.toString() ?? ''),
              text: text,
              timestamp:
                  DateTime.tryParse(msg['timestamp'] ?? '') ?? DateTime.now(),
              isMe: msg['from'] == _currentUsername,
              sender: msg['from'] ?? 'Unknown',
              filePath: msg['file_path'],
              fileType: msg['file_type'],
              attachedMessage: attachedMessage,
              forwardedInfo: forwardedInfo,
            );
            _addMessageAndScroll(groupMsg);

            if (widget.onNewMessage != null) {
              widget.onNewMessage!(msg);
            }
          }
          // --- Chat preview updates ---
          else if (msg['type'] == 'chat_preview_update') {
            // TODO: Inbox/chat list UI updates here
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
        },
        onDone: () {
          print('WebSocket closed');
        },
      );
    }
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;
    final content = _controller.text.trim();
    _controller.clear();

    final messagePayload = {
      "content": content,
      "to": widget.isGroup ? null : widget.username,
      "group": widget.isGroup ? widget.groupName : null,
      "file_path": null,
      "file_type": null,
    };
    print("Sending over WebSocket: $messagePayload");
    // RETAINED: Send the message as JSON over local WebSocket
    _channel?.sink.add(json.encode(messagePayload));
  }

  @override
  void dispose() {
    _channel?.sink.close(); // RETAINED: Close local WebSocket
    _controller.dispose();
    _scrollController.removeListener(_handleScroll);
    super.dispose();
  }

  // Helper to segment messages by date
  Map<String, List<ChatMessage>> _segmentMessagesByDate(
    List<ChatMessage> messages,
  ) {
    Map<String, List<ChatMessage>> segments = {};
    final now = DateTime.now().toLocal();
    for (var m in messages) {
      final msgDate = m.timestamp.toLocal();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final msgDay = DateTime(msgDate.year, msgDate.month, msgDate.day);

      String label;
      if (msgDay == today) {
        label = "Today";
      } else if (msgDay == yesterday) {
        label = "Yesterday";
      } else {
        label = "${msgDate.day} ${_monthName(msgDate.month)} ${msgDate.year}";
      }
      segments.putIfAbsent(label, () => []).add(m);
    }
    return segments;
  }

  String _monthName(int month) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month];
  }

  Widget _buildMessageBubble(ChatMessage m) {
    final isFile = m.text.startsWith('[') && m.filePath != null;
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.6;

    // Show image preview for image files
    if (m.filePath != null &&
        m.text.startsWith('[') &&
        m.text.contains(']') &&
        m.fileType != null &&
        m.fileType!.startsWith('image/')) {
      String normalizedPath = m.filePath!.replaceAll('\\', '/');
      if (!normalizedPath.startsWith('/')) normalizedPath = '/$normalizedPath';
      return FutureBuilder<String?>(
        future: ServerConfig.getServerIp(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const CircularProgressIndicator();
          }
          final serverIp = snapshot.data;
          if (serverIp == null) {
            return const Icon(Icons.broken_image, size: 48);
          }
          final url = 'http://$serverIp:8000$normalizedPath';
          final fileName = m.filePath!.split('/').last;
          return Align(
            alignment: m.isMe ? Alignment.topRight : Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              margin: const EdgeInsets.symmetric(
                vertical: 4.0,
                horizontal: 8.0,
              ),
              decoration: BoxDecoration(
                color:
                    m.isMe
                        ? Theme.of(context).colorScheme.surfaceVariant
                        : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isGroup && !m.isMe)
                      Text(
                        m.sender,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                    GestureDetector(
                      onTap: () {
                        _showImageDialog(url, fileName: fileName);
                      },
                      onLongPress: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (context) {
                            return Wrap(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.copy),
                                  title: const Text('Copy'),
                                  onTap: () {
                                    Clipboard.setData(
                                      ClipboardData(text: m.text),
                                    );
                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Copied!'),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.forward),
                                  title: const Text('Forward'),
                                  onTap: () {
                                    if (mounted) {
                                      Navigator.pop(context);
                                      _forwardMessage(m);
                                    }
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  title: const Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    await _deleteMessage(m);
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(
                                    Icons.save_alt_rounded,
                                    color: Colors.blue,
                                  ),
                                  title: const Text('Download'),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    await _saveFile(url, fileName);
                                  },
                                ),
                              ],
                            );
                          },
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          width: 220,
                          height: 220,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (context, error, stackTrace) =>
                                  const Icon(Icons.broken_image, size: 48),
                        ),
                      ),
                    ),
                    if (m.attachedMessage != null &&
                        m.attachedMessage!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          m.attachedMessage!,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(m.timestamp),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                        if (m.isMe)
                          Padding(
                            padding: const EdgeInsets.only(left: 4.0),
                            child: Icon(
                              m.status == 'seen'
                                  ? Icons.done_all
                                  : m.status == 'sent'
                                  ? Icons.check
                                  : Icons.access_time,
                              size: 14,
                              color:
                                  m.status == 'seen'
                                      ? Colors.blue
                                      : Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    // Show PDF thumbnail for PDF files
    if (m.filePath != null &&
        m.text.startsWith('[') &&
        m.text.contains(']') &&
        m.fileType != null &&
        m.fileType!.toLowerCase() == 'application/pdf') {
      String normalizedPath = m.filePath!.replaceAll('\\', '/');
      if (!normalizedPath.startsWith('/')) normalizedPath = '/$normalizedPath';
      return GestureDetector(
        onLongPress: () {
          showModalBottomSheet(
            context: context,
            builder: (context) {
              return Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.copy), // Added const
                    title: const Text('Copy'), // Added const
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: m.text));
                      if (mounted) {
                        // Added mounted check
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied!')),
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.forward), // Added const
                    title: const Text('Forward'), // Added const
                    onTap: () {
                      if (mounted) {
                        // Added mounted check
                        Navigator.pop(context);
                        _forwardMessage(m);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text(
                      'Delete',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _deleteMessage(m);
                    },
                  ),
                ],
              );
            },
          );
        },
        child: FutureBuilder<String?>(
          future: ServerConfig.getServerIp(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            final serverIp = snapshot.data;
            if (serverIp == null) {
              return const Icon(
                Icons.picture_as_pdf,
                color: Colors.red,
                size: 32,
              );
            }
            final url = 'http://$serverIp:8000$normalizedPath';
            final fileName = m.text.replaceFirst(RegExp(r'^\[[^\]]+\] '), '');
            return Align(
              alignment: m.isMe ? Alignment.topRight : Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.all(8.0),
                margin: const EdgeInsets.symmetric(
                  vertical: 4.0,
                  horizontal: 8.0,
                ),
                decoration: BoxDecoration(
                  color:
                      m.isMe
                          ? Theme.of(context).colorScheme.surfaceVariant
                          : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: Column(
                    crossAxisAlignment:
                        m.isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                    children: [
                      if (widget.isGroup && !m.isMe)
                        Text(
                          m.sender,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.blueGrey,
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            // Added const
                            Icons.picture_as_pdf,
                            color: Colors.red,
                            size: 32,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              fileName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                decoration: TextDecoration.underline,
                                color: Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              color: Colors.green,
                              size: 20,
                            ), // Added const
                            tooltip: 'Open file',
                            onPressed: () async {
                              await _openFile(url, fileName);
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.save_alt_rounded,
                              color: Colors.blue,
                              size: 20,
                            ), // Added const
                            tooltip: 'Save to device',
                            onPressed: () async {
                              await _saveFile(url, fileName);
                            },
                          ),
                        ],
                      ),
                      Text(
                        _formatTime(m.timestamp),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    // Default: file or text message
    return GestureDetector(
      onLongPress: () {
        // Show your bottom sheet or popup menu here
        showModalBottomSheet(
          context: context,
          builder: (context) {
            return Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.copy), // Added const
                  title: const Text('Copy'), // Added const
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: m.text));
                    if (mounted) {
                      // Added mounted check
                      Navigator.pop(context);
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Copied!')));
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.forward), // Added const
                  title: const Text('Forward'), // Added const
                  onTap: () {
                    if (mounted) {
                      // Added mounted check
                      Navigator.pop(context);
                      _forwardMessage(m);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _deleteMessage(m);
                  },
                ),
              ],
            );
          },
        );
      },
      child: Align(
        alignment: m.isMe ? Alignment.topRight : Alignment.topLeft,
        child: Container(
          padding: const EdgeInsets.all(8.0),
          margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          decoration: BoxDecoration(
            color:
                m.isMe
                    ? Theme.of(context).colorScheme.surfaceVariant
                    : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isFile ? maxBubbleWidth : double.infinity,
            ),
            child: Column(
              crossAxisAlignment:
                  m.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (widget.isGroup && !m.isMe)
                  Text(
                    m.sender,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.blueGrey,
                    ),
                  ),
                // --- PATCH: Show Forwarded tag ---
                if (m.forwardedInfo != null && m.forwardedInfo!.from != null)
                  const Padding(
                    // Added const
                    padding: EdgeInsets.only(bottom: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Forwarded',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isFile)
                  FutureBuilder<String?>(
                    future: ServerConfig.getServerIp(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }
                      final serverIp = snapshot.data;
                      if (serverIp == null) {
                        return const Icon(
                          Icons.insert_drive_file,
                          color: Colors.blueGrey,
                        );
                      }
                      String normalizedPath = m.filePath!.replaceAll('\\', '/');
                      if (!normalizedPath.startsWith('/')) {
                        normalizedPath = '/$normalizedPath';
                      }
                      final url = 'http://$serverIp:8000$normalizedPath';
                      final fileName = m.text.replaceFirst(
                        RegExp(r'^\[[^\]]+\] '),
                        '',
                      );
                      return Align(
                        alignment:
                            m.isMe ? Alignment.topRight : Alignment.topLeft,
                        child: Container(
                          padding: const EdgeInsets.all(8.0),
                          margin: const EdgeInsets.symmetric(
                            vertical: 4.0,
                            horizontal: 8.0,
                          ),
                          decoration: BoxDecoration(
                            color:
                                m.isMe
                                    ? Theme.of(
                                      context,
                                    ).colorScheme.surfaceVariant
                                    : Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: maxBubbleWidth,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.isGroup && !m.isMe)
                                  Text(
                                    m.sender,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      // Added const
                                      Icons.insert_drive_file,
                                      color: Colors.blueGrey,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        fileName,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          decoration: TextDecoration.underline,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.open_in_new_rounded,
                                        color: Colors.green,
                                        size: 20,
                                      ), // Added const
                                      tooltip: 'Open file',
                                      onPressed: () async {
                                        await _openFile(url, fileName);
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.save_alt_rounded,
                                        color: Colors.blue,
                                        size: 20,
                                      ), // Added const
                                      tooltip: 'Save to device',
                                      onPressed: () async {
                                        await _saveFile(url, fileName);
                                      },
                                    ),
                                  ],
                                ),
                                if (m.attachedMessage != null &&
                                    m.attachedMessage!.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      m.attachedMessage!,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatTime(m.timestamp),
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 10,
                                      ),
                                    ),
                                    if (m.isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 4.0,
                                        ),
                                        child: Icon(
                                          m.status == 'seen'
                                              ? Icons.done_all
                                              : m.status == 'sent'
                                              ? Icons.check
                                              : Icons.access_time,
                                          size: 14,
                                          color:
                                              m.status == 'seen'
                                                  ? Colors.blue
                                                  : Colors.grey,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  )
                else ...[
                  Text(
                    m.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  Row(
                    // Added Row for consistency with other status displays
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(m.timestamp),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                      if (m.isMe)
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: Icon(
                            Icons.check, // Always show "sent" check
                            size: 14,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // NEW: Consume the WebSocketProvider
    final webSocketProvider = Provider.of<WebSocketProvider>(context);

    // NEW: Determine the online status of the chat partner (only for direct chats)
    bool isChatPartnerOnline = false;
    // Only check online status if it's a direct chat (not a group) and username is not null
    if (!widget.isGroup && widget.username != null) {
      isChatPartnerOnline = webSocketProvider.isUserOnline(widget.username!);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed:
              () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const InboxScreen()),
                (route) => false,
              ),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundImage: NetworkImage(widget.avatarUrl),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                if (!widget.isGroup && widget.username != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) =>
                              EmployeeProfileScreen(username: widget.username!),
                    ),
                  );
                }
              },
              child: Column(
                // NEW: Wrap title and status in a Column
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isGroup
                        ? (widget.groupName ?? '')
                        : (widget.username ?? ''),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  // NEW: Display online/offline status only for direct individual chats
                  if (!widget
                      .isGroup) // This condition ensures it's not a group chat
                    Text(
                      isChatPartnerOnline
                          ? 'Online'
                          : 'Offline', // NEW: Use status from provider
                      style: const TextStyle(
                        fontSize: 12.0,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Builder(
              builder: (context) {
                final filteredMessages = _filteredMessages();
                final segments = _segmentMessagesByDate(filteredMessages);
                final List<Widget> segmentedWidgets = [];
                segments.forEach((date, msgs) {
                  segmentedWidgets.add(
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Center(
                        child: Text(
                          date,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  );
                  segmentedWidgets.addAll(
                    msgs.map((m) => _buildMessageBubble(m)).toList(),
                  );
                });
                return ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8.0),
                  children: segmentedWidgets,
                );
              },
            ),
          ),
          if (_isUploadingFile)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: LinearProgressIndicator(value: _uploadProgress),
            ),
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),

            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_pendingFile != null)
                        Row(
                          children: [
                            if (_pendingFileMimeType != null &&
                                _pendingFileMimeType!.startsWith('image/'))
                              _pendingFile!.path != null
                                  ? Image.file(
                                    File(_pendingFile!.path!),
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                  )
                                  : const Icon(
                                    Icons.insert_drive_file,
                                    color: Colors.blueGrey,
                                  ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _pendingFile!.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setState(() {
                                  _pendingFile = null;
                                  _pendingFileMimeType = null;
                                });
                              },
                            ),
                          ],
                        ),
                      TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 50,
                        decoration: const InputDecoration(
                          hintText: 'Type your message here',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendMessageOrFile(),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isUploadingFile ? null : _sendMessageOrFile,
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickFileForSend,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton:
          _showJumpToLatest
              ? Padding(
                padding: const EdgeInsets.only(bottom: 80.0),
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  tooltip: 'Jump to latest',
                  onPressed: () {
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        _scrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: const Icon(Icons.keyboard_double_arrow_down, size: 16),
                ),
              )
              : null,
    );
  }

  String _formatTime(DateTime dt) {
    // If already WAT, don't add another hour
    final isWAT = dt.timeZoneOffset.inHours == 1;
    final watTime = isWAT ? dt : dt.toUtc().add(const Duration(hours: 1));
    return "${watTime.hour.toString().padLeft(2, '0')}:${watTime.minute.toString().padLeft(2, '0')}";
  }

  void _showImageDialog(String imageUrl, {String? fileName}) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      width: MediaQuery.of(context).size.width * 0.9,
                      height: MediaQuery.of(context).size.height * 0.8,
                      errorBuilder:
                          (context, error, stackTrace) => const Icon(
                            Icons.broken_image,
                            color: Colors.white,
                            size: 100,
                          ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: IconButton(
                    icon: const Icon(
                      Icons.save_alt_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                    tooltip: 'Save to device',
                    onPressed: () async {
                      if (fileName != null) {
                        await _saveFile(imageUrl, fileName);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _pickFileForSend() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      String? mimeType;
      if (file.extension != null) {
        final ext = file.extension!.toLowerCase();
        if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
          mimeType = 'image/${ext == 'jpg' ? 'jpeg' : ext}';
        } else {
          mimeType = 'application/$ext';
        }
      }
      setState(() {
        _pendingFile = file;
        _pendingFileMimeType = mimeType;
      });
    }
  }

  Future<void> _sendMessageOrFile() async {
    if (_pendingFile != null) {
      await _sendFileWithMessage();
    } else {
      _sendMessage();
    }
  }

  // Add this state variable:
  bool _isUploadingFile = false;
  double _uploadProgress = 0.0;

  // PATCH: Update _sendFileWithMessage
  Future<void> _sendFileWithMessage() async {
    final file = _pendingFile;
    final mimeType = _pendingFileMimeType;
    final message = _controller.text.trim();
    if (file == null) return;

    // Cap file size to 100MB (or 200MB)
    const maxSize = 100 * 1024 * 1024; // 100MB
    if (file.size > maxSize) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File too large. Max 100MB allowed.')),
      );
      return;
    }

    setState(() {
      _isUploadingFile = true;
      _uploadProgress = 0.0;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null) return;

    final serverIp2 = await ServerConfig.getServerIp();
    if (serverIp2 == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Server IP not set. Please configure network settings.',
            ),
          ),
        );
      }
      setState(() => _isUploadingFile = false);
      return;
    }
    final uri =
        widget.isGroup && widget.groupName != null
            ? Uri.parse(
              'http://$serverIp2:8000/groups/${widget.groupName}/send_file',
            )
            : Uri.parse('http://$serverIp2:8000/messages/send_file');

    final dio = Dio();
    final formData = FormData.fromMap({
      if (!(widget.isGroup && widget.groupName != null))
        'to_username': widget.username ?? '',
      if (message.isNotEmpty) 'content': message,
      'file': await MultipartFile.fromFile(
        file.path!,
        filename: file.name,
        contentType: mimeType != null ? MediaType.parse(mimeType) : null,
      ),
    });

    try {
      final response = await dio.postUri(
        uri,
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          contentType: 'multipart/form-data',
        ),
        onSendProgress: (sent, total) {
          setState(() {
            _uploadProgress = total > 0 ? sent / total : 0.0;
          });
        },
      );
      if (response.statusCode == 200) {
        setState(() {
          _pendingFile = null;
          _pendingFileMimeType = null;
          _controller.clear();
          _isUploadingFile = false;
          _uploadProgress = 0.0;
        });
        // Wait for WebSocket confirmation to add message
      } else {
        setState(() => _isUploadingFile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send file: ${response.statusCode}'),
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploadingFile = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send file: $e')));
    }
  }

  void _forwardMessage(ChatMessage message) async {
    final selectedTargets = await Navigator.push<List<ForwardTarget>>(
      context,
      MaterialPageRoute(builder: (context) => InboxScreen(selectMode: true)),
    );

    if (selectedTargets == null || selectedTargets.isEmpty) return;

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

    for (final target in selectedTargets) {
      final sourceType = widget.isGroup ? 'group' : 'direct';
      if (target.isGroup) {
        // Forward to group
        final uri = Uri.parse(
          'http://$serverIp:8000/groups/${target.name}/forward',
        );
        await http.post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'message_id': message.id.toString(),
            'source_type': sourceType,
          },
        );
      } else {
        // Forward direct message
        final uri = Uri.parse('http://$serverIp:8000/messages/forward');
        await http.post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'message_id': message.id.toString(),
            'to_username': target.name,
            'source_type': sourceType,
          },
        );
      }
    }

    if (mounted) {
      // Added mounted check
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Message forwarded!')));
    }
  }

  Future<void> _markChatAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final serverIp = await ServerConfig.getServerIp();
    if (token == null || serverIp == null) return;

    if (widget.isGroup && widget.groupName != null) {
      await http.post(
        Uri.parse('http://$serverIp:8000/groups/${widget.groupName}/mark_read'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } else if (widget.username != null) {
      await http.post(
        Uri.parse('http://$serverIp:8000/messages/mark_read'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'username': widget.username!},
      );
    }
  }
}

class ForwardedInfo {
  final String? type;
  final String? from;
  final String? content;

  ForwardedInfo({this.type, this.from, this.content});

  factory ForwardedInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ForwardedInfo();
    return ForwardedInfo(
      type: json['type'],
      from: json['from'],
      content: json['content'],
    );
  }
}

class ChatMessage {
  final int? id;
  final String text;
  final String? attachedMessage;
  final DateTime timestamp;
  final bool isMe;
  final String sender;
  final String? filePath;
  final String? fileType;
  final ForwardedInfo? forwardedInfo;
  String status;

  ChatMessage({
    this.id,
    required this.text,
    required this.timestamp,
    required this.isMe,
    required this.sender,
    this.filePath,
    this.fileType,
    this.attachedMessage,
    this.forwardedInfo,
    this.status = 'sent',
  });

  ChatMessage copyWith({String? status}) => ChatMessage(
    id: id,
    text: text,
    timestamp: timestamp,
    isMe: isMe,
    sender: sender,
    filePath: filePath,
    fileType: fileType,
    attachedMessage: attachedMessage,
    forwardedInfo: forwardedInfo,
    status: status ?? this.status,
  );
}
