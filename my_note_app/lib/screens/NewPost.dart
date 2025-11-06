import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/drawing_screen.dart' as rt;
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

class NewPostScreen extends StatefulWidget {
  final int userId;           
  final String username;
  final VoidCallback? onPosted; // ถ้ามี => โหมดแท็บ (ไม่ต้องมี AppBar ของตัวเอง)

  const NewPostScreen({
    super.key,
    required this.userId,
    required this.username,
    this.onPosted,
  });

  @override
  State<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends State<NewPostScreen> {
  final TextEditingController _detailController = TextEditingController();

  String _priceType = 'free'; // 'free' | 'paid'
  final TextEditingController _priceCtrl = TextEditingController();

  String _username = '';
  String? _avatarUrl;

  String selectedYear = 'ปี 1';
  String? selectedSubject;

  final ImagePicker _picker = ImagePicker();
  final int _maxImages = 10;
  List<XFile> _images = [];

  File? _file;
  String? _fileName;

  bool _submitting = false;

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
    '01418499 ธนาคาร',
    '01418212 การโปรแกรมภาษาซี',
    '01418213 การโปรแกรมภาษาโคบอล',
    '01418222 ระบบสารสนเทศวิสาหกิจ',
    '01418324 ระบบสนับสนุนการตัดสินใจและอัจฉริยะทางธุรกิจ',
    '01418362 การเรียนรู้ของเครื่องเบื้องต้น',
    '01418441 เว็บเทคโนโลยีและเว็บบริการ'
  ];

  late final Map<String, List<String>> subjectsByYear = {
    'ปี 1': subjects1,
    'ปี 2': subjects2,
    'ปี 3': subjects3,
    'ปี 4': subjects4,
    'วิชาเฉพาะเลือก': subjects5,
  };

  List<String> get subjects => subjectsByYear[selectedYear] ?? const [];

  // ===== loading dialog on root navigator =====
  bool _loadingVisible = false;
  Future<void> _showLoading() async {
    _loadingVisible = true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true, // << สำคัญ
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }
  void _safePopDialog() {
    if (_loadingVisible) {
      _loadingVisible = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  void initState() {
    super.initState();
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
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _detailController.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  int _parseBahtToSatang(String input) {
    final normalized = input.trim().replaceAll(',', '');
    if (normalized.isEmpty) return 0;
    final d = double.tryParse(normalized);
    if (d == null) return 0;
    return (d * 100).round();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickImages() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    final merged = [..._images, ...files];
    if (merged.length > _maxImages) {
      _toast('เลือกรูปได้สูงสุด $_maxImages รูป');
    }
    if (!mounted) return;
    setState(() => _images = merged.take(_maxImages).toList());
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'zip', 'ppt', 'xls', 'xlsx'],
    );
    if (!mounted) return;
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _file = File(result.files.single.path!);
        _fileName = result.files.single.name;
      });
    }
  }

  Future<void> _handlePost() async {
    if (_submitting) return;

    if (selectedSubject == null) {
      _toast('กรุณาเลือกรายวิชา');
      return;
    }

    if (_priceType == 'paid') {
      final satang = _parseBahtToSatang(_priceCtrl.text);
      if (satang <= 0) {
        _toast('กรุณาใส่ราคามากกว่า 0 บาท');
        return;
      }
    }

    setState(() => _submitting = true);
    _showLoading();

    try {
      final res = await ApiService.createPost(
        userId: widget.userId,
        text: _detailController.text.trim(),
        yearLabel: selectedYear,
        subject: selectedSubject,
        images: _images.map((x) => File(x.path)).toList(),
        file: _file,
        priceType: _priceType,
        priceBaht: _priceType == 'paid'
            ? (_priceCtrl.text.trim().isEmpty
                ? null
                : double.tryParse(_priceCtrl.text.replaceAll(',', '')))
            : null,
      );

      if (!mounted) return;
      _safePopDialog();

      if (res.statusCode == 201 || res.statusCode == 200) {
        _toast('โพสต์สำเร็จ');
        setState(() {
          _detailController.clear();
          _priceType = 'free';
          _priceCtrl.clear();
          _images = [];
          _file = null;
          _fileName = null;
          selectedYear = 'ปี 1';
          selectedSubject = subjects.isNotEmpty ? subjects.first : null;
        });

        // โหมดแท็บ => มี onPosted
        if (widget.onPosted != null) {
          widget.onPosted!.call();
        } else {
          // โหมด push => ปิดหน้านี้
          if (Navigator.canPop(context)) Navigator.pop(context, true);
        }
      } else {
        _toast('โพสต์ไม่สำเร็จ (${res.statusCode})');
      }
    } catch (_) {
      if (!mounted) return;
      _safePopDialog();
      _toast('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้');
    } finally {
      if (!mounted) return;
      setState(() => _submitting = false);
    }
  }

  ImageProvider _avatarProvider() {
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      return NetworkImage('${ApiService.host}${_avatarUrl!}');
    }
    return const AssetImage('assets/default_avatar.png');
  }

  String _slugify(String s) {
    final t = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (t.isEmpty) return 'room-${DateTime.now().millisecondsSinceEpoch}';
    return t.length <= 64 ? t : t.substring(0, 64);
  }

  Future<void> _openHandwriteRealtime() async {
    final title = 'handnote-${DateTime.now().millisecondsSinceEpoch}';
    final roomId = _slugify(title);

    try {
      final r = await http.post(
        Uri.parse('${ApiService.host}/rooms'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'roomId': roomId, 'name': title}),
      );
      if (r.statusCode != 200) {
        _toast('สร้างห้องไม่สำเร็จ (${r.statusCode})');
        return;
      }

      String createdRoomId = roomId;
      try {
        final Map<String, dynamic> j =
            jsonDecode(r.body) as Map<String, dynamic>;
        if (j['roomId'] is String && (j['roomId'] as String).isNotEmpty) {
          createdRoomId = j['roomId'] as String;
        }
      } catch (_) {}

      final socket = IO.io(
        ApiService.host,
        IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
      );
      socket.connect();
      socket.onConnect((_) => socket.emit('join', {'boardId': createdRoomId}));

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => rt.NoteScribblePage(
            boardId: createdRoomId,
            initialTitle: title,
            socket: socket,
            documentId: null,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _toast('เชื่อมต่อเซิร์ฟเวอร์ realtime ไม่ได้');
    }
  }

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
    final cs = Theme.of(context).colorScheme;
    final subjectItems = subjects
        .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
        .toList();

    // โหมดแสดง AppBar ของตัวเอง = ถูก push (ไม่มี onPosted)
    final bool showOwnAppBar = (widget.onPosted == null);

    return Scaffold(
      appBar: showOwnAppBar
          ? AppBar(
              title: const Text('สร้างโพสต์'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'ปิด',
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: CircleAvatar(radius: 18, backgroundImage: _avatarProvider()),
                ),
              ],
            )
          : null,

      body: Padding(
        padding: const EdgeInsets.all(15.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 96,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                        color: cs.surface,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedYear,
                          items: years
                              .map((e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                      e,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: cs.onSurface),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            setState(() {
                              selectedYear = val;
                              selectedSubject =
                                  subjects.isNotEmpty ? subjects.first : null;
                            });
                          },
                          dropdownColor: cs.surface,
                          style: TextStyle(color: cs.onSurface),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                        color: cs.surface,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: subjects.contains(selectedSubject)
                              ? selectedSubject
                              : null,
                          hint: Text('รายวิชา',
                              style: TextStyle(color: cs.onSurfaceVariant)),
                          items: subjectItems,
                          selectedItemBuilder: (context) => subjects.map((e) {
                            return Text(
                              e,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: cs.onSurface),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => selectedSubject = val),
                          dropdownColor: cs.surface,
                          style: TextStyle(color: cs.onSurface),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _handlePost,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('โพสต์'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  const Text('ราคา:'),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('ฟรี'),
                    selected: _priceType == 'free',
                    onSelected: (_) => setState(() => _priceType = 'free'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('เสียเงิน'),
                    selected: _priceType == 'paid',
                    onSelected: (_) => setState(() => _priceType = 'paid'),
                  ),
                  const SizedBox(width: 12),
                  // if (_priceType == 'paid')
                  //   Text(
                  //     '→ ${_priceCtrl.text.trim().isEmpty ? '' : _parseBahtToSatang(_priceCtrl.text)} สต.',
                  //     style: TextStyle(color: Colors.grey.shade700),
                  //   ),
                ],
              ),
              if (_priceType == 'paid') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'ใส่ราคา (บาท)',
                    prefixText: '฿ ',
                    border: OutlineInputBorder(),
                    hintText: 'เช่น 29 หรือ 29.00',
                  ),
                ),
              ],

              const SizedBox(height: 16),

              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image),
                    onPressed: _submitting ? null : _pickImages,
                    tooltip: 'เลือกรูปภาพ (หลายรูป)',
                  ),
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _submitting ? null : _pickFile,
                    tooltip: 'แนบไฟล์',
                  ),
                  const SizedBox(width: 8),
                  Text('รูป ${_images.length}/$_maxImages',
                      style: TextStyle(color: Colors.grey.shade700)),
                ],
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _detailController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'รายละเอียดโพสต์',
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),

              _imagesPreview(),

              if (_file != null && _fileName != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  onPressed: _submitting ? null : _openHandwriteRealtime,
                  child: const Text('เขียนโน้ตด้วยลายมือ'),
                ),
              ),
            ],
          ),
        ),
      ),

      // ไม่ใส่ bottomNavigationBar ตรงนี้ — ให้ homescreen ถือ navbar เสมอ
    );
  }
}
