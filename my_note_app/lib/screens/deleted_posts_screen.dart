// lib/screens/deleted_posts_screen.dart
import 'package:flutter/material.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/widgets/post_card.dart';

class DeletedPostsScreen extends StatefulWidget {
  final int userId;
  const DeletedPostsScreen({super.key, required this.userId});

  @override
  State<DeletedPostsScreen> createState() => _DeletedPostsScreenState();
}

class _DeletedPostsScreenState extends State<DeletedPostsScreen> {
  late Future<List<dynamic>> _future;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final list = await ApiService().getArchived(widget.userId);
    _items = List<dynamic>.from(list);
    return _items;
  }

  Future<void> _refresh() async {
    final list = await ApiService().getArchived(widget.userId);
    if (!mounted) return;
    setState(() => _items = List<dynamic>.from(list));
  }

  Future<void> _restore(int index) async {
    final post = _items[index] as Map<String, dynamic>;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('กู้คืนโพสต์'),
        content: const Text('ต้องการกู้คืนโพสต์นี้กลับไปที่ฟีดหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final success = await ApiService().unarchivePost(post['id'] as int, widget.userId);
    if (!mounted) return;
    if (success) {
      setState(() => _items.removeAt(index));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กู้คืนแล้ว')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กู้คืนไม่สำเร็จ')));
    }
  }

Future<void> _hardDelete(int index) async {
  final post = _items[index] as Map<String, dynamic>;

  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('ลบถาวร'),
      content: const Text('ลบโพสต์นี้ออกจากฐานข้อมูลถาวร (กู้คืนไม่ได้) ?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('ลบถาวร'),
        ),
      ],
    ),
  );

  if (ok != true) return;

  // 👇 ให้แน่ใจว่าเป็น int จริง ๆ
  final int postId = (post['id'] is int)
      ? post['id'] as int
      : int.parse(post['id'].toString());

final result = await ApiService().deletePost(postId, userId: widget.userId);
if (!mounted) return;

if (result['ok'] == true) {
  setState(() => _items.removeAt(index));
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('ลบถาวรแล้ว')));
} else {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(result['message'] ?? 'ลบไม่สำเร็จ')));
}

}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deleted')),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('โหลดล้มเหลว: ${snap.error}'));
          }
          if (_items.isEmpty) {
            return const Center(child: Text('ไม่มีรายการที่ถูกลบ'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final p = _items[i] as Map<String, dynamic>;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PostCard(
                      post: p,
                      onDeleted: () {}, // เหมือนเดิม ไม่ใช้ callback นี้ในหน้า Deleted
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Row(
                        children: [
                          OutlinedButton(
                            onPressed: () => _restore(i),
                            child: const Text('Restore'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _hardDelete(i),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
