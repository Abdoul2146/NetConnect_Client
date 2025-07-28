import 'package:flutter/material.dart';
import 'package:netconnect/screens/theme_provider.dart';
import 'package:provider/provider.dart';
import 'home.dart';
import 'inbox.dart';
import 'create_group.dart';
import 'login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile.dart';
import 'package:http/http.dart' as http;
import '../server_config.dart';
import 'package:netconnect/screens/notice_board.dart';

class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({super.key});
  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  int _selectedIndex = 4; // Set initial index to Settings

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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const InboxScreen()),
        );
      } else if (index == 4) {
        print('Settings Tapped');
        // This is the current screen, no need to navigate
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundImage: NetworkImage(
                  'https://via.placeholder.com/150/808080/FFFFFF?Text=UA',
                ),
              ),
              title: const Text('User Details'),
              subtitle: const Text('Edit Profile Details'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                final currentUsername = prefs.getString('username');

                if (currentUsername != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) =>
                              EmployeeProfileScreen(username: currentUsername),
                    ),
                  );
                } else {
                  // Handle case where username is not found
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User not logged in')),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 12.0),
          Card(
            child: ListTile(
              title: const Text('Language Preferences'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                // Navigate to language preferences
                print('Language Preferences tapped');
              },
            ),
          ),
          const SizedBox(height: 12.0),
          Card(
            child: ListTile(
              title: const Text('Notification Preferences'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                // Navigate to notification preferences
                print('Notification Preferences tapped');
              },
            ),
          ),
          const SizedBox(height: 12.0),
          Card(
            child: ListTile(
              title: const Text('App Settings'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                // Navigate to app settings
                print('App Settings tapped');
              },
            ),
          ),
          const SizedBox(height: 12.0),
          Card(
            child: ListTile(
              title: const Text('Help & Support'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                // Navigate to help & support
                print('Help & Support tapped');
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: isDark,
            onChanged: (value) {
              themeProvider.setDarkMode(value);
              print('Dark Mode toggled: $value');
            },
          ),
          const SizedBox(height: 24.0),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                print('Log out tapped');
                final prefs = await SharedPreferences.getInstance();
                final username = prefs.getString('username');
                final serverIp = await ServerConfig.getServerIp();

                if (username != null && serverIp != null) {
                  // Call backend logout
                  await http.post(
                    Uri.parse('http://$serverIp:8000/logout'),
                    headers: {
                      'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: {'username': username},
                  );
                }

                await prefs.remove('access_token');
                await prefs.remove('username');
                await prefs.setBool('is_online', false);

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              child: const Text('Log out', style: TextStyle(fontSize: 18.0)),
            ),
          ),
        ],
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
}
