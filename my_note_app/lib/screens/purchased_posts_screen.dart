import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/widgets/post_card.dart';
import 'package:my_note_app/widgets/purchased_overlay.dart';

class PurchasedPostsScreen extends StatefulWidget {
  final int userId;
  const PurchasedPostsScreen({super.key, required this.userId});

  @override
  State<PurchasedPostsScreen> createState() => _PurchasedPostsScreenState();
}

class _PurchasedPostsScreenState extends State<PurchasedPostsScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getPurchasedPosts(widget.userId);
  }

  Future<void> _reload() async {
    setState(() {
      _future = ApiService.getPurchasedPosts(widget.userId);
    });
  }

  /// แปลงแถวจาก purchased feed -> โครงที่ PostCard ใช้ได้
  Map<String, dynamic> _toPostLike(Map<String, dynamic> p) {
    // id โพสต์
    final postId = (p['post_id'] ?? p['id']);
    final int safePostId =
        postId is int ? postId : int.tryParse('$postId') ?? 0;

    // ราคา (สตางค์ -> บาท)
    final satang = (p['price_amount_satang'] ?? p['amount_satang'] ?? 0);
    final int safeSatang =
        satang is int ? satang : int.tryParse('$satang') ?? 0;

    return {
      'id': safePostId,
      'username': p['username'] ?? p['seller_username'] ?? '',
      'avatar_url': p['avatar_url'],
      'text': p['text'] ?? '',
      'subject': p['subject'] ?? '',
      'year_label': p['year_label'] ?? '',
      'created_at': p['created_at'] ?? p['granted_at'], // เวลาได้สิทธิ์ก็ได้
      'images': (p['images'] ?? []) is List ? p['images'] : [],
      'image_url': p['image_url'],        // support รูปเดี่ยวแบบเก่า
      'file_url': p['file_url'],
      'like_count': p['like_count'] ?? 0,
      'comment_count': p['comment_count'] ?? 0,
      'liked_by_me': p['liked_by_me'] == true,
      'user_id': p['user_id'] ?? p['seller_id'],

      // ใส่ข้อมูลที่อยากโชว์/ใช้ต่อได้
      'price_type': 'paid',
      'price_amount_satang': safeSatang,
      'purchased': true, // flag ภายใน (ไม่บังคับ)
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchased posts')),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('โหลดรายการไม่สำเร็จ — ดึงลงเพื่อรีโหลด')),
                ],
              ),
            );
          }

          final raw = (snap.data ?? []).cast<dynamic>();
          if (raw.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('ยังไม่มีโพสต์ที่ซื้อ')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: raw.length,
              itemBuilder: (_, i) {
                final row = (raw[i] as Map).cast<String, dynamic>();
                final post = _toPostLike(row);

                // ครอบการ์ดด้วยริบบิ้น “ซื้อแล้ว”
                return PurchasedOverlay(
                  child: PostCard(post: post),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
