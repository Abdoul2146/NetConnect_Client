import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:netconnect/server_config.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  final bool isCurrentUser;

  const EditProfileScreen({
    super.key, 
    required this.profile, 
    required this.isCurrentUser
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late String name;
  late String jobRole;
  late String email;
  late String contact;
  late String username;

  @override
  void initState() {
    super.initState();
    name = widget.profile['name'] ?? '';
    jobRole = widget.profile['job_title'] ?? '';
    email = widget.profile['email'] ?? '';
    contact = widget.profile['contact'] ?? '';
    username = widget.profile['username'] ?? '';
  }

  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<void> saveProfile() async {
    if (!widget.isCurrentUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only edit your own profile')),
      );
      return;
    }

    String? token = await getStoredToken();
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first')),
      );
      return;
    }

    final serverIp = await ServerConfig.getServerIp();
    if (serverIp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server IP not set. Please configure network settings.')),
      );
      return;
    }
    final response = await http.put(
      Uri.parse('http://$serverIp:8000/profile/$username'),
      headers: {
        'Authorization': 'Bearer $token',
      },
      body: {
        'name': name,
        'job_title': jobRole,
        'email': email,
        'contact': contact,
      },
    );
    
    if (response.statusCode == 200) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile: ${response.statusCode}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                initialValue: name,
                decoration: const InputDecoration(labelText: 'Name'),
                onSaved: (value) => name = value ?? '',
              ),
              TextFormField(
                initialValue: jobRole,
                decoration: const InputDecoration(labelText: 'Job Role'),
                onSaved: (value) => jobRole = value ?? '',
              ),
              TextFormField(
                initialValue: email,
                decoration: const InputDecoration(labelText: 'Email'),
                onSaved: (value) => email = value ?? '',
              ),
              TextFormField(
                initialValue: contact,
                decoration: const InputDecoration(labelText: 'Contact'),
                onSaved: (value) => contact = value ?? '',
              ),
              TextFormField(
                initialValue: username,
                decoration: const InputDecoration(labelText: 'Username'),
                enabled: false, // Username cannot be changed
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  _formKey.currentState?.save();
                  saveProfile();
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}