// lib/screens/deleted_posts_screen.dart
import 'package:flutter/material.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/widgets/post_card.dart'; // แก้ path ให้ตรงโปรเจกต์

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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ยืนยัน')),
        ],
      ),
    );
    if (ok != true) return;

    final success = await ApiService().unarchivePost(post['id'] as int, widget.userId);
    if (success && mounted) {
      setState(() => _items.removeAt(index));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กู้คืนแล้ว')));
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบถาวร'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final success = await ApiService().deletePost(post['id'] as int);
    if (success && mounted) {
      setState(() => _items.removeAt(index));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ลบถาวรแล้ว')));
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
                    // ใช้ PostCard เหมือนหน้า Home
                    PostCard(
                      post: p,
                      // ถ้าใน PostCard มี popup “Delete post” จะกลายเป็น archive อีกครั้ง
                      // เราไม่ใช้ callbackนี้ในหน้า Deleted ก็ไม่เป็นไร
                      onDeleted: () {}, 
                    ),
                    // แถวปุ่ม Restore / Delete ใต้การ์ด
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Row(
                        children: [
                          OutlinedButton(
                            onPressed: () => _restore(i),
                            child: const Text('Restore'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: () => _hardDelete(i),
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
