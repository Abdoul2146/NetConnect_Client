// lib/providers/websocket_provider.dart
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:netconnect/server_config.dart'; // Make sure this path is correct

class WebSocketProvider with ChangeNotifier {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  String? _loggedInUsername;

  final Set<String> _activeUsers = {};
  Set<String> get activeUsers => _activeUsers;

  // NEW: StreamController to broadcast incoming messages to listeners
  final StreamController<Map<String, dynamic>> _messageStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Expose the stream for widgets to listen to
  Stream<Map<String, dynamic>> get incomingMessages =>
      _messageStreamController.stream;

  WebSocketProvider() {
    _loadLoggedInUser();
  }

  void _loadLoggedInUser() async {
    final prefs = await SharedPreferences.getInstance();
    _loggedInUsername = prefs.getString('username');
    if (_loggedInUsername != null) {
      connect();
    }
  }

  Future<void> connect() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    final token = prefs.getString('access_token');
    final serverIp = await ServerConfig.getServerIp();

    if (username == null || token == null || serverIp == null) {
      print(
        'WebSocketProvider: Cannot connect. Missing username, token, or server IP.',
      );
      return;
    }

    if (_channel != null && _channel!.closeCode == null) {
      print(
        'WebSocketProvider: Closing existing WebSocket connection before reconnecting.',
      );
      await _channel!.sink.close();
      _heartbeatTimer?.cancel();
    }

    try {
      _loggedInUsername = username;
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://$serverIp:8000/ws/$username?token=$token'),
      );
      print(
        'WebSocketProvider: Attempting to connect to ws://$serverIp:8000/ws/$username',
      );

      await _channel!.ready;

      _channel!.stream.listen(
        (data) {
          final msg = json.decode(data);
          // print('WebSocketProvider: Received message: $msg');

          if (msg['type'] == 'status') {
            final String user = msg['username'];
            final String status = msg['status'];
            _updateUserStatus(user, status == 'online');
          } else {
            // NEW: Add any non-status message to the stream for listeners
            _messageStreamController.add(msg);
          }
        },
        onDone: () {
          print('WebSocketProvider: Connection closed for $_loggedInUsername.');
          _handleDisconnection();
        },
        onError: (error) {
          print(
            'WebSocketProvider: Connection error for $_loggedInUsername: $error',
          );
          _handleDisconnection();
        },
      );

      _startHeartbeat();
      print(
        'WebSocketProvider: Connection established and heartbeat started for $_loggedInUsername.',
      );
    } catch (e) {
      print('WebSocketProvider: Failed to connect WebSocket: $e');
      _handleDisconnection();
    }
  }

  Future<void> disconnect() async {
    if (_channel != null) {
      print('WebSocketProvider: Disconnecting $_loggedInUsername.');
      _heartbeatTimer?.cancel();
      await _channel!.sink.close();
      _channel = null;
    }
    _handleDisconnection();
    _activeUsers.clear();
    _loggedInUsername = null;
    notifyListeners();
  }

  void _handleDisconnection() {
    if (_loggedInUsername != null) {
      _updateUserStatus(_loggedInUsername!, false);
    }
    // Any other global disconnection handling logic
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (_channel != null && _channel!.closeCode == null) {
        _channel!.sink.add(json.encode({"type": "heartbeat"}));
      } else {
        print(
          'WebSocketProvider: Heartbeat: Channel not open, stopping timer.',
        );
        _stopHeartbeat();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _updateUserStatus(String username, bool isOnline) {
    if (isOnline) {
      _activeUsers.add(username);
      // print('WebSocketProvider: $username is online. Active users: $_activeUsers');
    } else {
      _activeUsers.remove(username);
      // print('WebSocketProvider: $username is offline. Active users: $_activeUsers');
    }
    notifyListeners();
  }

  bool isUserOnline(String username) {
    return _activeUsers.contains(username);
  }

  // NEW METHOD: sendJson to send messages through the WebSocket
  void sendJson(Map<String, dynamic> data) {
    if (_channel != null && _channel!.closeCode == null) {
      _channel!.sink.add(json.encode(data));
      print('WebSocketProvider: Sent JSON message: $data');
    } else {
      print('WebSocketProvider: Failed to send JSON. WebSocket not connected.');
      // Handle error, e.g., show a snackbar or store message to retry
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _messageStreamController.close(); // NEW: Close the stream controller
    super.dispose();
    print('WebSocketProvider: Disposed.');
  }
}
