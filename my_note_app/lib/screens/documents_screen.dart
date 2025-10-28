// lib/screens/documents_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scribble/scribble.dart' as sc;
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'drawing_screen.dart'; // NoteScribblePage, TextBoxData, ImageLayerData

// -----------------------------------------------
// ตั้งค่า server realtime (3000)
// -----------------------------------------------
String get baseServerUrl =>
    Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';

// ล้าง prefix data:image/...;base64, ถ้ามี
String _cleanB64(String? s) {
  if (s == null) return '';
  return s.replaceFirst(RegExp(r'^data:image/[^;]+;base64,'), '');
}

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
                  const InputDecoration(labelText: 'Password (if required)'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Join')),
        ],
      ),
    );
    if (ok != true || roomIdCtrl.text.trim().isEmpty) return;

    final roomId = roomIdCtrl.text.trim();
    final socket = IO.io(
      baseServerUrl,
      IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
    );

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      bool? joinResult;
      String? errorMessage;

      socket.onConnect((_) {
        socket.emit('join', {
          'boardId': roomId,
          if (pwdCtrl.text.isNotEmpty) 'password': pwdCtrl.text
        });
      });

      socket.on('join_ok', (_) => joinResult = true);
      socket.on('join_error', (data) {
        joinResult = false;
        errorMessage = (data is Map && data['message'] is String)
            ? data['message'] as String
            : 'Could not join room';
      });

      socket.connect();

      for (var i = 0; i < 20; i++) {
        if (joinResult != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (joinResult == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NoteScribblePage(
              boardId: roomId,
              socket: socket,
              documentId: null,
              initialTitle: 'Joined Room',
              initialPages: const <sc.Sketch>[],
              initialTextsPerPage: const <List<TextBoxData>>[],
              initialImagesPerPage: const <List<ImageLayerData>>[],
            ),
          ),
        );
      } else {
        socket.dispose();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage ?? 'Failed to join room')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context); // close loading
      socket.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not connect to server')),
      );
    }
  }

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
                decoration:
                    const InputDecoration(labelText: 'Room name (optional)')),
            TextField(
                controller: pwdCtrl,
                decoration:
                    const InputDecoration(labelText: 'Password (optional)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final body = {
        if (nameCtrl.text.trim().isNotEmpty) 'name': nameCtrl.text.trim(),
        if (pwdCtrl.text.trim().isNotEmpty) 'password': pwdCtrl.text.trim(),
      };
      final r = await http.post(Uri.parse('$baseServerUrl/rooms'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final roomId = j['roomId'] as String? ?? j['id'] as String?;
        if (roomId == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('สร้างห้องไม่สำเร็จ (no id)')));
          return;
        }

        final socket = IO.io(
          baseServerUrl,
          IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
        );
        socket.connect();
        socket.onConnect((_) => socket.emit('join',
            {'boardId': roomId, 'password': pwdCtrl.text.trim()}));

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NoteScribblePage(
              boardId: roomId,
              socket: socket,
              documentId: null,
              initialTitle: nameCtrl.text.trim().isEmpty
                  ? 'Untitled'
                  : nameCtrl.text.trim(),
              initialPages: const <sc.Sketch>[],
              initialTextsPerPage: const <List<TextBoxData>>[],
              initialImagesPerPage: const <List<ImageLayerData>>[],
            ),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('สร้างห้องไม่สำเร็จ (${r.statusCode})')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('สร้างห้องไม่สำเร็จ')));
    }
  }

  Future<void> _loadDocs() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getInt('user_id');
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
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getInt('user_id');
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
  final boardId = (rawBoard is String) ? rawBoard.trim() : null;
      final title = (data['title'] as String?) ?? 'Untitled';

      // 1) raw pages
      final rawPages = (data['pages'] as List)
          .map((p) => Map<String, dynamic>.from((p as Map)['data'] as Map))
          .toList();

      // 2) lines -> Sketch
      final pagesSketch = rawPages.map<sc.Sketch>((m) {
        final mm = Map<String, dynamic>.from(m);
        final lines = (mm['lines'] is List) ? (mm['lines'] as List) : const [];
        return sc.Sketch.fromJson({'lines': lines});
      }).toList();

      // 3) texts
      final pagesTexts = rawPages.map<List<TextBoxData>>((m) {
        final mm = Map<String, dynamic>.from(m);
        final arr = (mm['texts'] as List?) ?? const [];
        return arr
            .map((e) => TextBoxData.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }).toList();

      // 4) images (สำคัญ: map + ล้าง prefix base64)
      final pagesImages = rawPages.map<List<ImageLayerData>>((m) {
        final mm = Map<String, dynamic>.from(m);
        final arr = (mm['images'] as List?) ?? const [];
        return arr.map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          final b64 = map['bytesB64'] as String?;
          if (b64 != null) {
            map['bytesB64'] = _cleanB64(b64);
          }
          return ImageLayerData.fromJson(map);
        }).toList();
      }).toList();

  // 5) ถ้ามี boardId (และไม่ใช่ sentinel 'offline') -> พยายาม join live room ก่อน
  final hasRealBoard = boardId != null && boardId.isNotEmpty && boardId.toLowerCase() != 'offline';
  if (hasRealBoard) {
        final socket = IO.io(
          baseServerUrl,
          IO.OptionBuilder()
              .setTransports(['websocket'])
              .disableAutoConnect()
              .build(),
        );

        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );

        void closeSpinnerSafe() {
          if (!mounted) return;
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (_) {}
        }

        void openLive() {
          if (!mounted) return;
          closeSpinnerSafe();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NoteScribblePage(
                boardId: boardId,
                socket: socket,
                documentId: d.id,
                initialTitle: title,
                initialPages: pagesSketch,
                initialTextsPerPage: pagesTexts,
                initialImagesPerPage: pagesImages, // ✅
              ),
            ),
          );
        }

        void openOffline([String? reason]) {
          if (!mounted) return;
          closeSpinnerSafe();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NoteScribblePage(
                boardId: boardId,
                socket: null,
                documentId: d.id,
                initialTitle: title,
                initialPages: pagesSketch,
                initialTextsPerPage: pagesTexts,
                initialImagesPerPage: pagesImages, // ✅
              ),
            ),
          );
          socket.dispose();
          if (reason != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('เปิดแบบออฟไลน์: $reason')));
          }
        }

        socket.on('join_ok', (_) => openLive());

        socket.on('join_error', (data) async {
          final msg = (data is Map && data['message'] is String)
              ? data['message'] as String
              : 'เข้าห้องไม่สำเร็จ';

          if (msg.toLowerCase().contains('password')) {
            if (!mounted) return;
            final pwdCtrl = TextEditingController();
            final retry = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('รหัสผ่านห้อง'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('ห้องนี้ต้องการรหัสผ่านเพื่อเข้าร่วม'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: pwdCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      autofocus: true,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('ยกเลิก')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('ส่ง')),
                ],
              ),
            );

            if (retry == true && pwdCtrl.text.trim().isNotEmpty) {
              socket.emit(
                  'join', {'boardId': boardId, 'password': pwdCtrl.text.trim()});
              return; // wait for join_ok / join_error
            }
            openOffline(msg);
            return;
          }

          openOffline(msg);
        });

        socket.onConnectError((_) => openOffline('เชื่อมต่อไม่ได้'));
        socket.onConnect((_) => socket.emit('join', {'boardId': boardId}));
        socket.connect();
        return;
      }

      // 6) ไม่มี boardId ที่ใช้ join ได้ -> เปิดออฟไลน์
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
            initialImagesPerPage: pagesImages, // ✅
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปิดเอกสารไม่สำเร็จ')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          IconButton(
            tooltip: 'Join Room',
            onPressed: _joinRoomDialog,
            icon: const Icon(Icons.input),
          ),
          IconButton(
            tooltip: 'Create Room',
            onPressed: _createRoomDialog,
            icon: const Icon(Icons.meeting_room),
          ),
          IconButton(onPressed: _loadDocs, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _docs.isEmpty
              ? const Center(child: Text('ยังไม่มีเอกสาร'))
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: GridView.builder(
                    itemCount: _docs.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.9,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
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
    );
  }
}

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
                              fontWeight: FontWeight.w600, fontSize: 14),
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
