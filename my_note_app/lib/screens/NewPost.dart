import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/home_screen.dart';
import 'package:my_note_app/screens/Drawing_Screen.dart';
import 'package:my_note_app/screens/search_screen.dart';

class NewPostScreen extends StatefulWidget {
  final int userId; // id_user จริงจาก login
  final String username;

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

  // header user
  String _username = '';
  String? _avatarUrl;
  // bool _loadingUser = true; // ไม่ได้ใช้

  // form state
  String selectedYear = 'ปี 1';
  String? selectedSubject;

  // รูปหลายรูป (สูงสุด 10)
  final ImagePicker _picker = ImagePicker();
  List<XFile> _images = []; // preview
  // แนบไฟล์เอกสาร (pdf/doc/zip)
  File? _file;
  String? _fileName;

  final List<String> years = ['ปี 1', 'ปี 2', 'ปี 3', 'ปี 4', 'วิชาเฉพาะเลือก'];

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
  final List<String> subjects5 = [
    '01418490 เว็บ',
    '01418499 ธนาคาร',
  ];

  late final Map<String, List<String>> subjectsByYear = {
    'ปี 1': subjects1,
    'ปี 2': subjects2,
    'ปี 3': subjects3,
    'ปี 4': subjects4,
    'วิชาเฉพาะเลือก': subjects5,
  };

  List<String> get subjects => subjectsByYear[selectedYear] ?? const [];

  @override
  void initState() {
    super.initState();
    _username = widget.username; // ค่าเริ่มต้นระหว่างรอโหลด
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
      });
    } catch (_) {
      if (!mounted) return;
  setState(() {});
    }
  }

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  // --------- Pickers ----------
  Future<void> _pickImages() async {
  final files = await _picker.pickMultiImage(imageQuality: 85);
  // Dart 3.0+ ไม่คืนค่า null แล้ว
  final merged = [..._images, ...files];
  setState(() => _images = merged.take(10).toList());
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'zip', 'ppt', 'xls', 'xlsx'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _file = File(result.files.single.path!);
        _fileName = result.files.single.name;
      });
    }
  }

  Future<void> _handlePost() async {
    if (selectedSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกรายวิชา')),
      );
      return;
    }

    // loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final res = await ApiService.createPost(
        userId: widget.userId,
        text: _detailController.text.trim(),
        yearLabel: selectedYear,
        subject: selectedSubject,
        images: _images.map((x) => File(x.path)).toList(),
        file: _file,
      );

      if (!mounted) return;
      Navigator.pop(context); // ปิด loading

      if (res.statusCode == 201 || res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('โพสต์สำเร็จ')),
        );
        setState(() {
          _detailController.clear();
          _images = [];
          _file = null;
          selectedYear = 'ปี 1';
          selectedSubject = subjects.isNotEmpty ? subjects.first : null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('โพสต์ไม่สำเร็จ (${res.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้')),
      );
    }
  }

  ImageProvider _avatarProvider() {
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      return NetworkImage('${ApiService.host}${_avatarUrl!}');
    }
    return const AssetImage('assets/default_avatar.png');
  }

  // preview รูปแบบ Grid
  Widget _imagesPreview() {
    if (_images.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemBuilder: (_, i) {
        final img = _images[i];
        return Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(File(img.path), fit: BoxFit.cover),
              ),
            ),
            Positioned(
              right: 2,
              top: 2,
              child: InkWell(
                onTap: () => setState(() => _images.removeAt(i)),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjectItems =
        subjects.map((e) => DropdownMenuItem<String>(value: e, child: Text(e))).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('NewPost'),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(radius: 18, backgroundImage: _avatarProvider()),
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _username,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // ปี
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
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            setState(() {
                              selectedYear = val;
                              selectedSubject = subjects.isNotEmpty ? subjects.first : null;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // วิชา
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
                          value: subjects.contains(selectedSubject) ? selectedSubject : null,
                          hint: const Text('รายวิชา'),
                          items: subjectItems,
                          selectedItemBuilder: (context) => subjects.map((e) {
                            return Text(e, maxLines: 1, overflow: TextOverflow.ellipsis);
                          }).toList(),
                          onChanged: (val) => setState(() => selectedSubject = val),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _handlePost,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('โพสต์'),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image),
                    onPressed: _pickImages,
                    tooltip: 'เลือกรูปภาพ (หลายรูป)',
                  ),
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _pickFile,
                    tooltip: 'แนบไฟล์',
                  ),
                ],
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _detailController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'รายละเอียดโพสต์',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),

              _imagesPreview(),

              if (_file != null && _fileName != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFFFBFBFB),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _fileName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.check_circle, color: Colors.green),
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
        onTap: (index) async {
          if (index == 0) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const homescreen()));
          } else if (index == 1) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Add'),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle_outlined), label: 'Profile'),
        ],
      ),
    );
  }
}
