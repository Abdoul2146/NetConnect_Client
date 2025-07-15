import 'package:shared_preferences/shared_preferences.dart';

class ServerConfig {
  static const _key = 'server_ip';

  static Future<String?> getServerIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> setServerIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, ip);
  }
}
