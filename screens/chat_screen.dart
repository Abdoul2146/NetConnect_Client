import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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
  WebSocketChannel? _channel;
  String? _currentUsername;
  String? _token;
  PlatformFile? _pendingFile;
  String? _pendingFileMimeType;
  Set<String> _activeUsers = {};

  @override
  void initState() {
    super.initState();
    _initCredentialsAndConnect();
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission denied')),
          );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to $filePath')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save file: $e')));
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
    // Debug print to see what messages we're filtering

    int firstUserMsgIdx = _messages.indexWhere((m) {
      // Debug print for each message being checked
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Server IP not set. Please configure network settings.',
          ),
        ),
      );
      return;
    }
    Uri url;
    if (widget.isGroup && widget.groupName != null) {
      url = Uri.parse(
        'http://$serverIp3:8000/groups/${widget.groupName}/messages',
      );
    } else {
      // Fetch only messages between myUsername and widget.username
      final serverIp4 = await ServerConfig.getServerIp();
      if (serverIp4 == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Server IP not set. Please configure network settings.',
            ),
          ),
        );
        return;
      }
      url = Uri.parse(
        'http://$serverIp4:8000/messages/$myUsername/${widget.username}',
      );
      // Refactored:
      // final serverIp = await ServerConfig.getServerIp();
      // url = Uri.parse('http://$serverIp:8000/messages?user1=$myUsername&user2=${widget.username}');
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

            // --- PATCH: Parse forwarded_from from history ---
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
              forwardedInfo: forwardedInfo, // <-- PATCH
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Server IP not set. Please configure network settings.',
            ),
          ),
        );
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

          // --- User active status ---
          if (msg['type'] == 'user_active' || msg['type'] == 'status') {
            setState(() {
              if (msg['status'] == 'online' || msg['active'] == true) {
                _activeUsers.add(msg['username']);
              } else {
                _activeUsers.remove(msg['username']);
              }
            });
          }

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
          // 2. Parse forwarded_from in WebSocket handler for direct and group messages:
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

              // --- PATCH: Parse forwarded_from ---
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
                forwardedInfo: forwardedInfo, // <-- PATCH
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

            // --- PATCH: Parse forwarded_from ---
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
              forwardedInfo: forwardedInfo, // <-- PATCH
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
    // Send the message as JSON over WebSocket
    _channel?.sink.add(json.encode(messagePayload));
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _controller.dispose();
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
          return Align(
            alignment: m.isMe ? Alignment.topRight : Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              margin: const EdgeInsets.symmetric(
                vertical: 4.0,
                horizontal: 8.0,
              ),
              decoration: BoxDecoration(
                color: m.isMe ? Colors.grey[300] : Colors.white,
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
                      onTap: () => _showImageDialog(url),
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
                    leading: Icon(Icons.copy),
                    title: Text('Copy'),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: m.text));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Copied!')));
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.forward),
                    title: Text('Forward'),
                    onTap: () {
                      Navigator.pop(context);
                      _forwardMessage(m);
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
                  color: m.isMe ? Colors.grey[300] : Colors.white,
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
                          Icon(
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
                            icon: Icon(Icons.open_in_new),
                            tooltip: 'Open file',
                            onPressed: () async {
                              await _openFile(url, fileName);
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.save_alt),
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
                  leading: Icon(Icons.copy),
                  title: Text('Copy'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: m.text));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Copied!')));
                  },
                ),
                ListTile(
                  leading: Icon(Icons.forward),
                  title: Text('Forward'),
                  onTap: () {
                    Navigator.pop(context);
                    _forwardMessage(m);
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
            color: m.isMe ? Colors.grey[300] : Colors.white,
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Forwarded',
                          style: const TextStyle(
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
                      if (!normalizedPath.startsWith('/'))
                        normalizedPath = '/$normalizedPath';
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
                            color: m.isMe ? Colors.grey[300] : Colors.white,
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
                                    Icon(
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
                                      icon: Icon(Icons.open_in_new),
                                      tooltip: 'Open file',
                                      onPressed: () async {
                                        await _openFile(url, fileName);
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.save_alt),
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
                  Text(m.text, style: const TextStyle(fontSize: 14)),
                  Text(
                    _formatTime(m.timestamp),
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
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
              child: Text(
                widget.isGroup
                    ? (widget.groupName ?? '')
                    : (widget.username ?? ''),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
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
                              Image.memory(
                                _pendingFile!.bytes!,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                              )
                            else
                              Icon(
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
                  onPressed: _sendMessageOrFile,
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
    );
  }

  String _formatTime(DateTime dt) {
    // If already WAT, don't add another hour
    final isWAT = dt.timeZoneOffset.inHours == 1;
    final watTime = isWAT ? dt : dt.toUtc().add(const Duration(hours: 1));
    return "${watTime.hour.toString().padLeft(2, '0')}:${watTime.minute.toString().padLeft(2, '0')}";
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.black,
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder:
                    (context, error, stackTrace) => const Icon(
                      Icons.broken_image,
                      color: Colors.white,
                      size: 100,
                    ),
              ),
            ),
          ),
    );
  }

  Future<void> _pickFileForSend() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
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

  Future<void> _sendFileWithMessage() async {
    final file = _pendingFile;
    final mimeType = _pendingFileMimeType;
    final message = _controller.text.trim();
    if (file == null) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null) return;

    final serverIp2 = await ServerConfig.getServerIp();
    if (serverIp2 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Server IP not set. Please configure network settings.',
          ),
        ),
      );
      return;
    }
    final uri =
        widget.isGroup && widget.groupName != null
            ? Uri.parse(
              'http://$serverIp2:8000/groups/${widget.groupName}/send_file',
            )
            : Uri.parse('http://$serverIp2:8000/messages/send_file');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token';

    if (widget.isGroup && widget.groupName != null) {
      // nothing extra needed, group_name is in URL
    } else {
      request.fields['to_username'] = widget.username ?? '';
    }

    if (message.isNotEmpty) {
      request.fields['content'] = message;
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: file.name,
        contentType: mimeType != null ? MediaType.parse(mimeType) : null,
      ),
    );

    final response = await request.send();
    if (response.statusCode == 200) {
      setState(() {
        _pendingFile = null;
        _pendingFileMimeType = null;
        _controller.clear();
      });
      // Wait for WebSocket confirmation to add message
    } else {
      print('Failed to send file: ${response.statusCode}');
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Server IP not set. Please configure network settings.',
          ),
        ),
      );
      return;
    }

    for (final target in selectedTargets) {
      final sourceType = widget.isGroup ? 'group' : 'direct'; // <-- PATCH
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
            'source_type': sourceType, // <-- PATCH
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
            'source_type': sourceType, // <-- PATCH
          },
        );
      }
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Message forwarded!')));
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
