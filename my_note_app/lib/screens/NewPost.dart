import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/home_screen.dart';
import 'package:my_note_app/screens/Drawing_Screen.dart';

class NewPostScreen extends StatefulWidget {
  final int userId;         // ✅ เพิ่ม: ใช้ดึงข้อมูลจาก API
  final String username;    // ใช้เป็นค่าเริ่มต้นระหว่างรอโหลด
  const NewPostScreen({
    super.key,
    required this.userId,
    required this.username,
  });

  @override
  State<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends State<NewPostScreen> {
  final TextEditingController _detailController = TextEditingController();

  // ----- header user state -----
  String _username = '';
  String? _avatarUrl; // path จาก server เช่น /uploads/avatars/xxx.jpg
  bool _loadingUser = true;

  // ----- post form state -----
  String selectedYear = 'ปี 1';
  String? selectedSubject; 
  File? _image;
  File? _file;

  final List<String> years = ['ปี 1', 'ปี 2', 'ปี 3', 'ปี 4'];

  final List<String> subjects1 = [
    '01418111 วิทยาการคอมพิวเตอร์เบื้องต้น',
    '01418112 แนวคิดการโปรแกรมเบื้องต้น',
    '01418141 ทรัพย์สินทางปัญญาและจรรยาบรรณวิชาชีพ',
    '01418113 การโปรแกรมคอมพิวเตอร์',
    '01418131 การโปรแกรมทางสถิติ',
    '01418132 หลักมูลการคณนา',
  ];
  final List<String> subjects2 = [
    '01418211 การสร้างซอฟต์แวร์',
    '01418231 โครงสร้างข้อมูลและขั้นตอนวิธี',
    '01418233 สถาปัตยกรรมคอมพิวเตอร์',
    '01418221 ระบบฐานข้อมูลเบื้องต้น',
    '01418232 การออกแบบและการวิเคราะห์ขั้นตอนวิธี',
    '01418236 ระบบปฏิบัติงาน',
    '01418261 หลักพื้นฐานของปัญญาประดิษฐ์',
  ];
  final List<String> subjects3 = [
    '01418321 การวิเคราะห์และการออกแบบระบบ',
    '01418331 ทฤษฏีการคำนวณ',
    '01418351 หลักการการสื่อสารคอมพิวเตอร์และการประมวลผลบนคลาวด์',
    '01418390 การเตรียมความพร้อมสหกิจศึกษา',
    '01418332 ความมั่นคงในระบบสารสนเทศ',
    '01418371 การบริหารโครงการและสตาร์ทอัพดิจิทัล',
    '01418497 สัมมนา',
  ];
  final List<String> subjects4 = [
    '01418490 สหกิจศึกษา',
    '01418499 โครงงานวิทยาการคอมพิวเตอร์',
  ];

  late final Map<String, List<String>> subjectsByYear = {
    'ปี 1': subjects1,
    'ปี 2': subjects2,
    'ปี 3': subjects3,
    'ปี 4': subjects4,
  };

  List<String> get subjects => subjectsByYear[selectedYear] ?? const [];

  @override
  void initState() {
    super.initState();
    // ค่าเริ่มต้นระหว่างรอโหลดจาก API
    _username = widget.username;
    selectedSubject = subjects.isNotEmpty ? subjects.first : null;
    _loadUserHeader();
  }

  Future<void> _loadUserHeader() async {
    try {
      final data = await ApiService.getUserBrief(widget.userId);
      if (!mounted) return;
      setState(() {
        _username = (data['username'] as String?)?.trim().isNotEmpty == true
            ? data['username'] as String
            : widget.username;
        _avatarUrl = data['avatar_url'] as String?;
        _loadingUser = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingUser = false; // ใช้ค่าจาก constructor ไปก่อน
      });
      // จะโชว์ snackBar ก็ได้ แต่ไม่บังคับ
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('โหลดข้อมูลผู้ใช้ไม่สำเร็จ')),
      // );
    }
  }

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _image = File(pickedFile.path));
  }

  Future<void> _pickFile() async {
    // เดโมยังใช้ image picker; ถ้าจะรองรับเอกสารให้เปลี่ยนเป็น file_picker
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _file = File(pickedFile.path));
  }

  void _handlePost() {
    if (selectedSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกรายวิชา')),
      );
      return;
    }

    Navigator.pop(context, {
      'detail': _detailController.text,
      'year': selectedYear,
      'subject': selectedSubject,
      'image': _image,
      'file': _file,
    });
  }

  ImageProvider _avatarProvider() {
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      // รวม host + path จาก server
      return NetworkImage('${ApiService.host}${_avatarUrl!}');
    }
    return const AssetImage('assets/default_avatar.png');
  }

  @override
  Widget build(BuildContext context) {
    final subjectItems = subjects
        .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('NewPost'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              radius: 18,
              backgroundImage: _avatarProvider(),
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
              // แถวบน: username + dropdown ปี/วิชา + ปุ่มโพสต์
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ชื่อผู้ใช้ (ซ้ำกับ appbar ได้ แต่เผื่อ Boss อยากโชว์ตรง body ด้วย)
                  Flexible(
                    child: Text(
                      _username,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Dropdown ปี
                  Flexible(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFFFBFBFB),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedYear,
                          items: years
                              .map((e) =>
                                  DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            setState(() {
                              selectedYear = val;
                              selectedSubject =
                                  subjects.isNotEmpty ? subjects.first : null;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Dropdown วิชา
                  Flexible(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFFFBFBFB),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: subjects.contains(selectedSubject)
                              ? selectedSubject
                              : null,
                          hint: const Text('รายวิชา'),
                          items: subjectItems,
                          selectedItemBuilder: (context) => subjects.map((e) {
                            return Text(
                              e,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => selectedSubject = val),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // ปุ่มโพสต์
                  ElevatedButton(
                    onPressed: _handlePost,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('โพสต์'),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ปุ่มแนบรูป/ไฟล์
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image),
                    onPressed: _pickImage,
                    tooltip: 'เลือกรูปภาพ',
                  ),
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _pickFile,
                    tooltip: 'แนบไฟล์',
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // เนื้อหาโพสต์
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

              // Preview รูป/ไฟล์ที่แนบ
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
                      Expanded(
                        child: Text(
                          _file!.path.split(Platform.pathSeparator).last,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => NoteScribblePage()),
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
              MaterialPageRoute(builder: (_) => const homescreen()),
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
