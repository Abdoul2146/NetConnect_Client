import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'inbox.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:netconnect/screens/profile.dart';
import 'package:netconnect/server_config.dart';

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


  Future<void> _sendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null) return;

    final serverIp2 = await ServerConfig.getServerIp();
    if (serverIp2 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server IP not set. Please configure network settings.')),
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

    // --- MIME type fix for images ---
    String? mimeType;
    if (file.extension != null) {
      final ext = file.extension!.toLowerCase();
      if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
        mimeType = 'image/${ext == 'jpg' ? 'jpeg' : ext}';
      } else {
        mimeType = 'application/$ext';
      }
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
      // Do NOT add the message locally here; wait for WebSocket confirmation
    } else {
      print('Failed to send file: ${response.statusCode}');
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
        const SnackBar(content: Text('Server IP not set. Please configure network settings.')),
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
          const SnackBar(content: Text('Server IP not set. Please configure network settings.')),
        );
        return;
      }
      url = Uri.parse('http://$serverIp4:8000/messages/$myUsername/${widget.username}');
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
            if (msg['file_path'] != null &&
                msg['file_path'].toString().isNotEmpty) {
              final fileName = msg['file_path'].toString().split('/').last;
              text = '[File] $fileName';
            } else {
              text = msg['content'] ?? '';
            }
            return ChatMessage(
              text: text,
              timestamp: DateTime.parse(msg['timestamp']),
              isMe: msg['from'] == myUsername,
              sender: msg['from'] ?? '',
              filePath: msg['file_path'],
              fileType: msg['file_type'],
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
      await _fetchMessageHistory(); // <-- Fetch history first

      final serverIp = await ServerConfig.getServerIp();
      if (serverIp == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server IP not set. Please configure network settings.')),
        );
        return;
      }
      final wsUrl = Uri.parse(
        'ws://$serverIp:8000/ws/$_currentUsername?token=$_token',
      );
      print('Connecting to WebSocket at $wsUrl');
      // Connect to the WebSocket server
      _channel = WebSocketChannel.connect(wsUrl);
      _channel!.stream.listen(
        (data) {
          print('Received from WebSocket: $data');
          final msg = json.decode(data);

          // --- Direct messages ---
          if (msg['type'] == 'direct_message') {
            if ((msg['from'] == widget.username &&
                    msg['to'] == _currentUsername) ||
                (msg['from'] == _currentUsername &&
                    msg['to'] == widget.username)) {
              String text;
              if (msg['file_path'] != null &&
                  msg['file_path'].toString().isNotEmpty) {
                String fileType = msg['file_type'] ?? '';
                if (fileType.contains('/')) {
                  fileType = fileType.split('/').last.toUpperCase();
                }
                final fileName = msg['file_path'].toString().split('/').last;
                text = '[${fileType.isNotEmpty ? fileType : "File"}] $fileName';
              } else {
                text = msg['content'] ?? '';
              }
              _addMessageAndScroll(
                ChatMessage(
                  text: text,
                  timestamp: DateTime.parse(msg['timestamp']),
                  isMe: msg['from'] == _currentUsername,
                  sender: msg['from'] ?? '',
                  filePath: msg['file_path'],
                  fileType: msg['file_type'],
                ),
              );
            }
          }

          // --- Group messages ---
          if (msg['type'] == 'group_message' &&
              msg['group'] == widget.groupName) {
            String text;
            if (msg['file_path'] != null &&
                msg['file_path'].toString().isNotEmpty) {
              String fileType = msg['file_type'] ?? '';
              if (fileType.contains('/')) {
                fileType = fileType.split('/').last.toUpperCase();
              }
              final fileName = msg['file_path'].toString().split('/').last;
              text = '[${fileType.isNotEmpty ? fileType : "File"}] $fileName';
            } else {
              text = msg['content'] ?? '';
            }
            _addMessageAndScroll(
              ChatMessage(
                text: text,
                timestamp: DateTime.parse(msg['timestamp']),
                isMe: msg['from'] == _currentUsername,
                sender: msg['from'] ?? '',
                filePath: msg['file_path'],
                fileType: msg['file_type'],
              ),
            );
            // <<< CALL THE CALLBACK HERE >>>
            if (widget.onNewMessage != null) {
              widget.onNewMessage!(msg);
            }
          } else if (msg['type'] == 'chat_preview_update') {
            // TODO: Update inbox/chat list UI in real time
            // You may need to use a callback or state management to notify the inbox screen
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
          // print('fileType: ${m.fileType}, filePath: ${m.filePath}, url: $url');
          return Align(
            alignment: m.isMe ? Alignment.topRight : Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
              decoration: BoxDecoration(
                color: m.isMe ? Colors.grey[300] : Colors.white,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
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
                    GestureDetector(
                      onTap: () async {
                        if (await canLaunchUrl(Uri.parse(url))) {
                          await launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              url,
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (context, error, stackTrace) =>
                                      Icon(Icons.broken_image, size: 48),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            m.text.replaceFirst(RegExp(r'^\[[^\]]+\] '), ''),
                            style: const TextStyle(
                              decoration: TextDecoration.underline,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formatTime(m.timestamp),
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
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
      return FutureBuilder<String?>(
        future: ServerConfig.getServerIp(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const CircularProgressIndicator();
          }
          final serverIp = snapshot.data;
          if (serverIp == null) {
            return const Icon(Icons.picture_as_pdf, color: Colors.red, size: 32);
          }
          final url = 'http://$serverIp$normalizedPath';
          final fileName = m.text.replaceFirst(RegExp(r'^\[[^\]]+\] '), '');
          return Align(
            alignment: m.isMe ? Alignment.topRight : Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
              decoration: BoxDecoration(
                color: m.isMe ? Colors.grey[300] : Colors.white,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
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
                    GestureDetector(
                      onTap: () async {
                        if (await canLaunchUrl(Uri.parse(url))) {
                          await launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.picture_as_pdf, color: Colors.red, size: 32),
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
                          Icon(Icons.download, size: 20, color: Colors.blueGrey),
                        ],
                      ),
                    ),
                    Text(
                      _formatTime(m.timestamp),
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    // Default: file or text message
    return Align(
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
              if (isFile)
                FutureBuilder<String?>(
                  future: ServerConfig.getServerIp(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    final serverIp = snapshot.data;
                    if (serverIp == null) {
                      return const Icon(Icons.insert_drive_file, color: Colors.blueGrey);
                    }
                    return GestureDetector(
                      onTap: () async {
                        final url = await _getUrlForFile(m);
                        if (url != null && await canLaunchUrl(Uri.parse(url))) {
                          await launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.insert_drive_file, color: Colors.blueGrey),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              m.text.replaceFirst(RegExp(r'^\[[^\]]+\] '), ''),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                decoration: TextDecoration.underline,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.download, size: 16, color: Colors.blueGrey),
                        ],
                      ),
                    );
                  },
                )
              else
                Text(m.text),
              Text(
                _formatTime(m.timestamp),
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
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
                      builder: (context) => EmployeeProfileScreen(username: widget.username!),
                    ),
                  );
                }
              },
              child: Text(
                widget.isGroup
                    ? (widget.groupName ?? '')
                    : (widget.username ?? ''),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                IconButton(icon: const Icon(Icons.menu), onPressed: () {}),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 50, // Allow up to 50 lines
                    decoration: const InputDecoration(
                      hintText: 'Type your message here',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _sendFile,
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

  Future<String?> _getUrlForFile(ChatMessage m) async {
    final serverIp6 = await ServerConfig.getServerIp();
    if (serverIp6 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server IP not set. Please configure network settings.')),
      );
      return null;
    }
    return m.filePath != null && m.filePath!.isNotEmpty
        ? 'http://$serverIp6:8000${m.filePath}'
        : 'http://$serverIp6:8000/${m.filePath}';
  }
}

class ChatMessage {
  final String text;
  final DateTime timestamp;
  final bool isMe;
  final String sender;
  final String? filePath;
  final String? fileType;

  ChatMessage({
    required this.text,
    required this.timestamp,
    required this.isMe,
    required this.sender,
    this.filePath,
    this.fileType,
  });
}
