import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scribble/scribble.dart' as sc;
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'drawing_screen.dart'; // NoteScribblePage
// -----------------------------------------------
// ตั้งค่า server realtime (3000)
// -----------------------------------------------
String get baseServerUrl =>
    Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';

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
              decoration: const InputDecoration(labelText: 'Password (if required)'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Join')),
        ],
      ),
    );
    if (ok != true || roomIdCtrl.text.trim().isEmpty) return;

    // สร้าง socket และลองเชื่อมต่อเข้าห้อง
    final roomId = roomIdCtrl.text.trim();
    final socket = IO.io(
      baseServerUrl,
      IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
    );

    // แสดง loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // รอผลการเชื่อมต่อ
      bool? joinResult;
      String? errorMessage;
      
      socket.onConnect((_) {
        debugPrint('Socket connected, trying to join room: $roomId');
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

      // รอผลลัพธ์ไม่เกิน 10 วินาที
      for (var i = 0; i < 20; i++) {
        if (joinResult != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (!mounted) return;
      Navigator.pop(context); // ปิด loading

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
            ),
          ),
        );
      } else {
        socket.dispose();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage ?? 'Failed to join room')),
        );
      }
    } catch (e) {
      debugPrint('Join room error: $e');
      if (!mounted) return;
      Navigator.pop(context); // ปิด loading
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
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Room name (optional)')),
            TextField(controller: pwdCtrl, decoration: const InputDecoration(labelText: 'Password (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
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
          headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
      debugPrint('POST $baseServerUrl/rooms => ${r.statusCode}');
      debugPrint('POST rooms body: ${r.body}');
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final roomId = j['roomId'] as String? ?? j['id'] as String?;
        if (roomId == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างห้องไม่สำเร็จ (no id)')));
          return;
        }

        // create socket and open NoteScribblePage for the new room
        final socket = IO.io(
          baseServerUrl,
          IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
        );
        socket.connect();
        socket.onConnect((_) => socket.emit('join', {'boardId': roomId, 'password': pwdCtrl.text.trim()}));

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NoteScribblePage(
              boardId: roomId,
              socket: socket,
              documentId: null,
              initialTitle: nameCtrl.text.trim().isEmpty ? 'Untitled' : nameCtrl.text.trim(),
              initialPages: const <sc.Sketch>[],
              initialTextsPerPage: const <List<TextBoxData>>[],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('สร้างห้องไม่สำเร็จ (${r.statusCode})')));
      }
    } catch (e, st) {
      debugPrint('create room error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างห้องไม่สำเร็จ')));
    }
  }

  Future<void> _loadDocs() async {
    setState(() => _loading = true);
    try {
      // ถ้ามี user_id ใน SharedPreferences ให้ส่งเป็น query เพื่อดูเอกสารของผู้ใช้คนนั้นเท่านั้น
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getInt('user_id');
      final uri = (uid != null)
          ? Uri.parse('$baseServerUrl/documents').replace(queryParameters: {'user_id': '$uid'})
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
          ? Uri.parse('$baseServerUrl/documents/${d.id}').replace(queryParameters: {'user_id': '$uid'})
          : Uri.parse('$baseServerUrl/documents/${d.id}');
      final r = await http.delete(uri);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      setState(() => _docs.removeWhere((x) => x.id == d.id));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลบเอกสารไม่สำเร็จ')),
      );
    }
  }

  Future<void> _openDocument(_DocItem d) async {
    try {
      // 1) โหลดรายละเอียดเอกสาร
      final r = await http.get(Uri.parse('$baseServerUrl/documents/${d.id}'));
      debugPrint('GET $baseServerUrl/documents/${d.id} => ${r.statusCode}');
      debugPrint('GET body: ${r.body}');
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final data = jsonDecode(r.body) as Map<String, dynamic>;

      final boardId = (data['board_id'] as String?)?.trim();
      final title = (data['title'] as String?) ?? 'Untitled';

      // 2) แปลง pages -> Sketch/TextBoxData
      final rawPages = (data['pages'] as List)
          .map((p) => Map<String, dynamic>.from((p as Map)['data'] as Map))
          .toList();

      final pagesSketch = rawPages.map<sc.Sketch>((m) {
        final mm = Map<String, dynamic>.from(m);
        final lines = (mm['lines'] is List) ? (mm['lines'] as List) : const [];
        return sc.Sketch.fromJson({'lines': lines});
      }).toList();

      final pagesTexts = rawPages.map<List<TextBoxData>>((m) {
        final mm = Map<String, dynamic>.from(m);
        final arr = (mm['texts'] as List?) ?? const [];
        return arr
            .map((e) =>
                TextBoxData.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }).toList();

      // 3) ถ้ามี boardId -> พยายาม join ห้องก่อน (live)
      if (boardId != null && boardId.isNotEmpty) {
        final socket = IO.io(
          baseServerUrl,
          IO.OptionBuilder()
              .setTransports(['websocket'])
              .disableAutoConnect()
              .build(),
        );

        // show a connecting spinner while attempting to join
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );

        void closeSpinnerSafe() {
          if (mounted) {
            // try to pop the spinner dialog if it's still active
            try {
              Navigator.of(context, rootNavigator: true).pop();
            } catch (_) {}
          }
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
              ),
            ),
          );
          socket.dispose();
          if (reason != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('เปิดแบบออฟไลน์: $reason')),
            );
          }
        }

        // Handle successful join
        socket.on('join_ok', (_) {
          openLive();
        });

        // Handle join errors: if password required, prompt user and retry
        socket.on('join_error', (data) async {
          final msg = (data is Map && data['message'] is String)
              ? data['message'] as String
              : 'เข้าห้องไม่สำเร็จ';

          // If server says password required (heuristic), prompt for password
          if (msg.toLowerCase().contains('password')) {
            if (!mounted) return;
            // prompt for password
            final pwdCtrl = TextEditingController();
            final retry = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('รหัสผ่านห้อง'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ห้องนี้ต้องการรหัสผ่านเพื่อเข้าร่วม'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: pwdCtrl,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      autofocus: true,
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ส่ง')),
                ],
              ),
            );

            if (retry == true && pwdCtrl.text.trim().isNotEmpty) {
              // retry join with password
              socket.emit('join', {'boardId': boardId, 'password': pwdCtrl.text.trim()});
              return; // wait for join_ok / join_error
            }
            // user cancelled or didn't enter password -> open offline
            openOffline(msg);
            return;
          }

          // default fallback: open offline with message
          openOffline(msg);
        });

        socket.onConnectError((_) => openOffline('เชื่อมต่อไม่ได้'));
        // initial attempt to join
        socket.onConnect((_) => socket.emit('join', {'boardId': boardId}));
        socket.connect();
        return;
      }

      // 4) ไม่มี boardId -> เปิดแบบ offline
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
          // Join Room
          IconButton(
            tooltip: 'Join Room',
            onPressed: _joinRoomDialog,
            icon: const Icon(Icons.input),
          ),
          // Create Room
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
        boardId: j['board_id'] as String?,
        coverPng: j['cover_png'] as String?,
        updatedAt: j['updated_at'] != null
            ? DateTime.parse(j['updated_at'] as String)
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
    final img = (item.coverPng != null && item.coverPng!.isNotEmpty)
        ? Image.memory(
            base64Decode(item.coverPng!),
            fit: BoxFit.cover,
          )
        : Container(color: Colors.grey.shade200);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Material(
        elevation: 1,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            // cover
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                child: img,
              ),
            ),
            // meta
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
