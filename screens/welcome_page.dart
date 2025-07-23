import 'package:flutter/material.dart';
import 'package:netconnect/screens/login_page.dart';
import 'package:netconnect/server_config.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NetChatSplashScreen extends StatefulWidget {
  const NetChatSplashScreen({super.key});

  @override
  State<NetChatSplashScreen> createState() => _NetChatSplashScreenState();
}

class _NetChatSplashScreenState extends State<NetChatSplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkFirstTime();
    _requestStoragePermission();
    _checkServerIp();
  }

  Future<void> _checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    bool? seen = prefs.getBool('welcome_seen');
    if (seen == true) {
      // If already seen, go directly to login
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
    // If not seen, do nothing and show welcome page
  }

  Future<void> _requestStoragePermission() async {
    if (await Permission.manageExternalStorage.isGranted) return;
    await Permission.manageExternalStorage.request();
  }

  void _checkServerIp() async {
    String? ip = await ServerConfig.getServerIp();
    if (ip == null) {
      _promptForIp();
    } else {
      // Proceed to app (e.g., navigate to login or home)
    }
  }

  void _promptForIp() async {
    String? ip = await showDialog<String>(
      context: context,
      builder: (context) {
        String input = '';
        return AlertDialog(
          title: Text('Enter Server IP'),
          content: TextField(
            onChanged: (value) => input = value,
            decoration: InputDecoration(hintText: 'e.g. 192.168.1.100'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, input),
              child: Text('Save'),
            ),
          ],
        );
      },
    );
    if (ip != null && ip.isNotEmpty) {
      await ServerConfig.setServerIp(ip);
      // Proceed to app (e.g., navigate to login or home)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 150.0,
              height: 150.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade300, width: 2.0),
              ),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(0.5),
                  child: Image.asset('asset/welcome.png'),
                ),
              ),
            ),
            const SizedBox(height: 24.0),
            const Text(
              'NetConnect',
              style: TextStyle(
                fontSize: 32.0,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8.0),
            Text(
              'Your communication solution for\norganizations',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16.0, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 32.0),
            SizedBox(
              width: 200.0,
              child: ElevatedButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('welcome_seen', true); // Mark as seen
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: const Text(
                  'Start',
                  style: TextStyle(
                    fontSize: 18.0,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
