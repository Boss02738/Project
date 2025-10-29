import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/widgets/post_card.dart';

class LikedPostsScreen extends StatefulWidget {
  const LikedPostsScreen({super.key, required int userId});

  @override
  State<LikedPostsScreen> createState() => _LikedPostsScreenState();
}

class _LikedPostsScreenState extends State<LikedPostsScreen> {
  bool _loading = true;
  int? _userId;
  List<dynamic> _posts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sp = await SharedPreferences.getInstance();
      _userId = sp.getInt('user_id');

      if (_userId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรุณาเข้าสู่ระบบ')),
        );
        setState(() => _loading = false);
        return;
      }

      // ✅ ดึงฟีดของเรา แล้วกรองเอาเฉพาะโพสต์ที่เรากดไลก์ไว้
      final feed = await ApiService.getFeed(_userId!);
      final liked = feed.where((p) => p['liked_by_me'] == true).toList();

      if (!mounted) return;
      setState(() {
        _posts = liked;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('โหลดโพสต์ที่ถูกใจไม่สำเร็จ')),
      );
    }
  }

  Future<void> _refresh() => _load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Likes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
              ? const Center(child: Text('ยังไม่มีโพสต์ที่ถูกใจ'))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: _posts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => PostCard(post: _posts[i]),
                  ),
                ),
    );
  }
}
