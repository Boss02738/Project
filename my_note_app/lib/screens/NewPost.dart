import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:my_note_app/screens/home_screen.dart';
import 'package:my_note_app/screens/Drawing_Screen.dart';

class NewPostScreen extends StatefulWidget {
  final String username;
  const NewPostScreen({super.key, required this.username});

  @override
  State<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends State<NewPostScreen> {
  final TextEditingController _detailController = TextEditingController();
  String selectedYear = 'ปี 1';
  String selectedSubject = 'รายวิชา 1';
  File? _image;
  File? _file;

  final List<String> years = ['ปี 1', 'ปี 2', 'ปี 3', 'ปี 4'];
  final List<String> subjects = [
    'รายวิชา 1',
    'รายวิชา 2',
    'รายวิชา 3',
    'รายวิชา 4',
  ];

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  Future<void> _pickFile() async {
    // ใช้ file_picker package ถ้าต้องการรองรับไฟล์ทุกชนิด
    // ตัวอย่างนี้ใช้ imagePicker รองรับเฉพาะรูปภาพ
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _file = File(pickedFile.path);
      });
    }
  }

  void _handlePost() {
    // TODO: ส่งข้อมูลไป backend หรือเพิ่มในหน้า Home
    Navigator.pop(context, {
      'detail': _detailController.text,
      'year': selectedYear,
      'subject': selectedSubject,
      'image': _image,
      'file': _file,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Newpost'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              radius: 18,
              backgroundImage: AssetImage(
                'assets/profile.png',
              ), // เปลี่ยนเป็นรูปโปรไฟล์จริง
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(15.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.username,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: selectedYear,
                    items: years
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) => setState(() => selectedYear = val!),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: selectedSubject,
                    items: subjects
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) => setState(() => selectedSubject = val!),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _handlePost,
                    child: const Text('โพสต์'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image),
                    onPressed: _pickImage,
                  ),
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _pickFile,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _detailController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'รายละเอียดโพสต์',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_image != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  height: 120,
                  child: Image.file(_image!),
                ),
              if (_file != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file),
                      const SizedBox(width: 8),
                      Text(_file!.path.split('/').last),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NoteDrawingPage(),
                      ),
                    );
                  },
                  child: const Text('เขียนโน้ตด้วยลายมือ'),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        selectedItemColor: const Color.fromARGB(255, 31, 102, 160),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const homescreen()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Add'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle_outlined),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
