// lib/screens/documents_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scribble/scribble.dart' as sc;
import 'package:socket_io_client/socket_io_client.dart' as IO;

// ใช้ของที่ประกาศใน drawing_screen
import 'drawing_screen.dart'
    show NoteScribblePage, TextBoxData, ImageLayerData, baseServerUrl;

/* ----------------------------------------------------------
 * Utils
 * ---------------------------------------------------------- */
String _cleanB64(String? s) {
  if (s == null) return '';
  return s.replaceFirst(RegExp(r'^data:image/[^;]+;base64,'), '');
}

Future<int?> _getUserId() async {
  final sp = await SharedPreferences.getInstance();
  return sp.getInt('user_id');
}

IO.Socket _newSocket() => IO.io(
      baseServerUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

/* ==========================================================
 * Documents Screen
 * ========================================================== */
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  bool _loading = true;
  List<_DocItem> _docs = [];

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  /* ---------------- Spinner helpers ---------------- */
  void _showSpinner() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _hideSpinner() {
    if (!mounted) return;
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /* ---------------- Central join flow (fixes owner->viewer) ----------------
   * บังคับลำดับ identify → join และ "รอ join_ok/joined_board" ก่อน push หน้าถัดไป
   */
  Future<void> _connectAndOpenRoom({
    required String roomId,
    String? password,
    required String? documentId,
    required String title,
    required List<sc.Sketch> pagesSketch,
    required List<List<TextBoxData>> pagesTexts,
    required List<List<ImageLayerData>> pagesImages,
    List<String>? pageTitles,
    List<int?>? pageOwners,
  }) async {
    final socket = _newSocket();
    var finished = false;

    void finishError(String msg) {
      if (finished) return;
      finished = true;
      _hideSpinner();
      socket.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    }

    void openLive() {
      if (finished) return;
      finished = true;
      _hideSpinner();
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoteScribblePage(
            boardId: roomId,
            socket: socket,
            documentId: documentId,
            initialTitle: title,
            initialPages: pagesSketch,
            initialTextsPerPage: pagesTexts,
            initialImagesPerPage: pagesImages,
            initialPageTitles: pageTitles,
            initialPageOwners: pageOwners,
          ),
        ),
      );
    }

    // ---------- Events ----------
    socket.onConnect((_) async {
      final uid = await _getUserId();

      final payload = <String, dynamic>{
        'boardId': roomId,
        if (uid != null) 'userId': uid,
        if (password != null && password.isNotEmpty) 'password': password,
      };

      if (uid != null) {
        socket.emit('identify', {'userId': uid});
      }

      // รองรับทั้งชื่อ event แบบใหม่และแบบเก่า
      socket.emit('join_board', payload); // ฝั่ง server ปัจจุบันใช้ตัวนี้
      socket.emit('join', payload); // เผื่อโค้ดเก่าที่ยังฟัง 'join'
    });

    // สำเร็จ: รองรับทั้ง 'join_ok' และ 'joined_board'
    socket.on('join_ok', (_) => openLive());
    socket.on('joined_board', (_) => openLive());

    socket.on('join_error', (data) async {
      final msg = (data is Map && data['message'] is String)
          ? data['message'] as String
          : 'เข้าห้องไม่สำเร็จ';
      final needsPassword =
          msg.toLowerCase().contains('password') ||
              msg.toLowerCase().contains('require');

      if (needsPassword) {
        if (!mounted) return;
        final pwCtrl = TextEditingController();
        final retry = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ต้องใช้รหัสผ่าน'),
            content: TextField(
              controller: pwCtrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ส่ง'),
              ),
            ],
          ),
        );

        if (retry == true && pwCtrl.text.trim().isNotEmpty) {
          final uid = await _getUserId();
          final payload = {
            'boardId': roomId,
            if (uid != null) 'userId': uid,
            'password': pwCtrl.text.trim(),
          };
          socket.emit('join_board', payload);
          socket.emit('join', payload);
          return; // รอผลรอบใหม่
        }
      }

      finishError(msg);
    });

    socket.onConnectError((_) => finishError('เชื่อมต่อไม่ได้'));

    // ---------- Start ----------
    _showSpinner();
    socket.connect();
  }

  /* ======================= Join via dialog ======================= */
  Future<void> _joinRoomDialog() async {
    final roomIdCtrl = TextEditingController();
    final pwdCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Room'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: roomIdCtrl,
              decoration: const InputDecoration(labelText: 'Room ID'),
              autofocus: true,
            ),
            TextField(
              controller: pwdCtrl,
              decoration:
                  const InputDecoration(labelText: 'Password (ถ้ามี)'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('เข้าร่วม'),
          ),
        ],
      ),
    );

    if (ok != true || roomIdCtrl.text.trim().isEmpty) return;

    await _connectAndOpenRoom(
      roomId: roomIdCtrl.text.trim(),
      password: pwdCtrl.text.trim(),
      documentId: null,
      title: 'Joined Room',
      pagesSketch: const <sc.Sketch>[],
      pagesTexts: const <List<TextBoxData>>[],
      pagesImages: const <List<ImageLayerData>>[],
      pageTitles: const <String>[],
      pageOwners: const <int?>[],
    );
  }

  /* ======================= Create Room ======================= */
  Future<void> _createRoomDialog() async {
    final nameCtrl = TextEditingController();
    final pwdCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Room'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Room name (optional)',
              ),
            ),
            TextField(
              controller: pwdCtrl,
              decoration: const InputDecoration(
                labelText: 'Password (optional)',
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('สร้าง'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final uid = await _getUserId();
      final body = <String, dynamic>{
        if (nameCtrl.text.trim().isNotEmpty) 'name': nameCtrl.text.trim(),
        if (pwdCtrl.text.trim().isNotEmpty) 'password': pwdCtrl.text.trim(),
        if (uid != null) 'owner_id': uid, // บันทึกเจ้าของตั้งแต่สร้าง
      };

      _showSpinner();
      final r = await http.post(
        Uri.parse('$baseServerUrl/rooms'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      _hideSpinner();

      if (r.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('สร้างห้องไม่สำเร็จ (${r.statusCode})')),
        );
        return;
      }

      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final roomId = (j['roomId'] ?? j['id'])?.toString();
      if (roomId == null || roomId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('สร้างห้องไม่สำเร็จ (no id)')),
        );
        return;
      }

      await _connectAndOpenRoom(
        roomId: roomId,
        password: pwdCtrl.text.trim(),
        documentId: null,
        title:
            nameCtrl.text.trim().isEmpty ? 'Untitled' : nameCtrl.text.trim(),
        pagesSketch: const <sc.Sketch>[],
        pagesTexts: const <List<TextBoxData>>[],
        pagesImages: const <List<ImageLayerData>>[],
        pageTitles: const <String>[],
        pageOwners: const <int?>[],
      );
    } catch (_) {
      if (!mounted) return;
      _hideSpinner();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('สร้างห้องไม่สำเร็จ')));
    }
  }

  /* ======================= Load/Delete/Open docs ======================= */
  Future<void> _loadDocs() async {
    setState(() => _loading = true);
    try {
      final uid = await _getUserId();
      final uri = (uid != null)
          ? Uri.parse('$baseServerUrl/documents')
              .replace(queryParameters: {'user_id': '$uid'})
          : Uri.parse('$baseServerUrl/documents');

      final r = await http.get(uri);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');

      final list = (jsonDecode(r.body) as List).cast<Map>();
      setState(() {
        _docs = list
            .map((e) => _DocItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('โหลดรายการเอกสารไม่สำเร็จ')),
      );
    }
  }

  Future<void> _delete(_DocItem d) async {
    try {
      final uid = await _getUserId();
      final uri = (uid != null)
          ? Uri.parse('$baseServerUrl/documents/${d.id}')
              .replace(queryParameters: {'user_id': '$uid'})
          : Uri.parse('$baseServerUrl/documents/${d.id}');

      final r = await http.delete(uri);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      setState(() => _docs.removeWhere((x) => x.id == d.id));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลบเอกสารไม่สำเร็จ')),
      );
    }
  }

  Future<void> _openDocument(_DocItem d) async {
    try {
      final r = await http.get(Uri.parse('$baseServerUrl/documents/${d.id}'));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final data = jsonDecode(r.body) as Map<String, dynamic>;

      final rawBoard = data['boardId'] ?? data['board_id'];
      final boardId =
          (rawBoard is String) ? rawBoard.trim() : rawBoard?.toString();
      final title = (data['title'] as String?) ?? 'Untitled';

      // raw pages
      final rawPages = (data['pages'] as List? ?? const [])
          .map((p) => Map<String, dynamic>.from((p as Map)['data'] as Map))
          .toList();

      // เตรียม list ทั้งหมด
      final List<sc.Sketch> pagesSketch = [];
      final List<List<TextBoxData>> pagesTexts = [];
      final List<List<ImageLayerData>> pagesImages = [];
      final List<String> pageTitles = [];
      final List<int?> pageOwners = [];

      for (final m in rawPages) {
        final mm = Map<String, dynamic>.from(m);

        // lines -> Sketch
        final lines = (mm['lines'] is List) ? (mm['lines'] as List) : const [];
        pagesSketch.add(sc.Sketch.fromJson({'lines': lines}));

        // texts
        final arrTexts = (mm['texts'] as List?) ?? const [];
        pagesTexts.add(
          arrTexts
              .map(
                (e) =>
                    TextBoxData.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList(),
        );

        // images
        final arrImages = (mm['images'] as List?) ?? const [];
        pagesImages.add(
          arrImages.map((e) {
            final map = Map<String, dynamic>.from(e as Map);
            final b64 = map['bytesB64'] as String?;
            if (b64 != null) map['bytesB64'] = _cleanB64(b64);
            return ImageLayerData.fromJson(map);
          }).toList(),
        );

        // meta: title & owner
        pageTitles.add((mm['page_title'] as String?) ?? '');
        final ownerDyn = mm['page_owner_id'];
        int? owner;
        if (ownerDyn is int) {
          owner = ownerDyn;
        } else if (ownerDyn is String) {
          owner = int.tryParse(ownerDyn);
        }
        pageOwners.add(owner);
      }

      final hasRealBoard = boardId != null &&
          boardId.isNotEmpty &&
          boardId.toLowerCase() != 'offline';

      if (!hasRealBoard) {
        // เปิดแบบออฟไลน์
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NoteScribblePage(
              boardId: 'offline',
              socket: null,
              documentId: d.id,
              initialTitle: title,
              initialPages: pagesSketch,
              initialTextsPerPage: pagesTexts,
              initialImagesPerPage: pagesImages,
              initialPageTitles: pageTitles,
              initialPageOwners: pageOwners,
            ),
          ),
        );
        return;
      }

      // Live: ใช้ flow กลาง (identify → join → join_ok/joined_board)
      await _connectAndOpenRoom(
        roomId: boardId!,
        password: null,
        documentId: d.id,
        title: title,
        pagesSketch: pagesSketch,
        pagesTexts: pagesTexts,
        pagesImages: pagesImages,
        pageTitles: pageTitles,
        pageOwners: pageOwners,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปิดเอกสารไม่สำเร็จ')),
      );
    }
  }

  /* ======================= UI ======================= */
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _joinRoomDialog,
                icon: const Icon(Icons.input),
                label: const Text('เข้าห้อง'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _createRoomDialog,
                icon: const Icon(Icons.meeting_room),
                label: const Text('สร้างห้อง'),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'รีเฟรช',
                onPressed: _loadDocs,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: _docs.isEmpty
              ? const Center(child: Text('ยังไม่มีเอกสาร'))
              : RefreshIndicator(
                  onRefresh: _loadDocs,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: GridView.builder(
                      itemCount: _docs.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.9,
                        crossAxisSpacing: 12,
                      ),
                      itemBuilder: (_, i) {
                        final d = _docs[i];
                        return _DocCard(
                          item: d,
                          onTap: () => _openDocument(d),
                          onDelete: () => _delete(d),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/* ==========================================================
 * Models & Card
 * ========================================================== */
class _DocItem {
  final String id;
  final String? title;
  final String? boardId;
  final String? coverPng;
  final DateTime? updatedAt;

  _DocItem({
    required this.id,
    this.title,
    this.boardId,
    this.coverPng,
    this.updatedAt,
  });

  factory _DocItem.fromJson(Map<String, dynamic> j) => _DocItem(
        id: j['id'] as String,
        title: j['title'] as String?,
        boardId: (j['board_id'] ?? j['boardId']) as String?,
        coverPng: (j['cover_png'] ?? j['coverPng']) as String?,
        updatedAt: j['updated_at'] != null
            ? DateTime.tryParse(j['updated_at'].toString())
            : null,
      );
}

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final _DocItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Widget cover;
    if (item.coverPng != null && item.coverPng!.isNotEmpty) {
      try {
        final b = base64Decode(_cleanB64(item.coverPng));
        cover = Image.memory(b, fit: BoxFit.cover);
      } catch (_) {
        cover = Container(color: Colors.grey.shade200);
      }
    } else {
      cover = Container(color: Colors.grey.shade200);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Material(
        elevation: 1,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                child: cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title ?? 'Untitled',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.updatedAt != null
                              ? 'อัปเดตล่าสุด: ${item.updatedAt!.toLocal()}'
                              : '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'ลบ',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
