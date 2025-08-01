import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:netconnect/server_config.dart';

class CreatePostPage extends StatefulWidget {
  final String boardId;
  const CreatePostPage({Key? key, required this.boardId}) : super(key: key);

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  PlatformFile? pickedFile;
  bool _isPosting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Post', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
            SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      withData: true,
                    );
                    if (result != null && result.files.isNotEmpty) {
                      setState(() {
                        pickedFile = result.files.first;
                      });
                    }
                  },
                  icon: Icon(Icons.attach_file),
                  label: Text('Attach File'),
                ),
                if (pickedFile != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Row(
                      children: [
                        Text(
                          pickedFile!.name,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blueGrey,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.cancel, color: Colors.red, size: 18),
                          tooltip: 'Remove file',
                          onPressed: () {
                            setState(() {
                              pickedFile = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed:
                    _isPosting
                        ? null
                        : () async {
                          final title = _titleController.text.trim();
                          final desc = _descController.text.trim();
                          if (title.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Title is required'),
                              ),
                            );
                            return;
                          }
                          setState(() => _isPosting = true);

                          final prefs = await SharedPreferences.getInstance();
                          final token = prefs.getString('access_token');
                          final serverIp = await ServerConfig.getServerIp();
                          if (token == null || serverIp == null) {
                            setState(() => _isPosting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Missing server IP or token'),
                              ),
                            );
                            return;
                          }

                          final uri = Uri.parse(
                            'http://$serverIp:8000/notice_boards/${widget.boardId}/posts',
                          );
                          final request =
                              http.MultipartRequest('POST', uri)
                                ..headers['Authorization'] = 'Bearer $token'
                                ..fields['title'] = title
                                ..fields['description'] = desc;

                          if (pickedFile != null) {
                            request.files.add(
                              http.MultipartFile.fromBytes(
                                'attachment', // <-- matches backend
                                pickedFile!.bytes!,
                                filename: pickedFile!.name,
                              ),
                            );
                          }

                          final response = await request.send();
                          setState(() => _isPosting = false);

                          if (response.statusCode == 200 ||
                              response.statusCode == 201) {
                            Navigator.pop(context, true); // Signal success
                          } else {
                            final respStr =
                                await response.stream.bytesToString();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to create post: $respStr',
                                ),
                              ),
                            );
                          }
                        },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child:
                    _isPosting
                        ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : Text('Post'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
