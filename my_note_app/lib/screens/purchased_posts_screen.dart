import 'package:flutter/material.dart';
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

  // เติม host ให้ path ที่เป็น /uploads/...
  String _abs(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    // ป้องกัน //uploads
    if (url.startsWith('/')) return '${ApiService.host}$url';
    return '${ApiService.host}/$url';
  }

  Map<String, dynamic> _toPostCardData(Map<String, dynamic> r) {
    final List imgs = (r['images'] is List) ? r['images'] : const [];
    final fixedImgs = imgs.map((e) => _abs('$e')).toList();

    return {
      'id': r['id'],
      'user_id': r['user_id'],                 // เจ้าของโพสต์
      'username': r['username'] ?? '',
      'avatar_url': _abs(r['avatar_url']),
      'text': r['text'] ?? '',
      'subject': r['subject'] ?? '',
      'year_label': r['year_label'] ?? '',
      'created_at': r['created_at'] ?? r['granted_at'],
      'images': fixedImgs,
      'image_url': _abs(r['image_url']),
      'file_url': _abs(r['file_url']),
      'like_count': r['like_count'] ?? 0,
      'comment_count': r['comment_count'] ?? 0,
      'liked_by_me': r['liked_by_me'] == true,
      'price_type': r['price_type'] ?? 'free',
      'price_amount_satang': r['price_amount_satang'] ?? 0,
      'purchased': true, // flag เฉพาะจอนี้
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
                children: [
                  const SizedBox(height: 160),
                  Center(
                    child: Column(
                      children: [
                        const Text('โหลดรายการไม่สำเร็จ — ดึงลงเพื่อรีโหลด'),
                        const SizedBox(height: 8),
                        Text(
                          '${snap.error}',
                          style: const TextStyle(fontSize: 12, color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          final rows = (snap.data ?? const []).cast<Map>();
          if (rows.isEmpty) {
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
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final post = _toPostCardData(rows[i].cast<String, dynamic>());
                return PurchasedOverlay(child: PostCard(post: post));
              },
            ),
          );
        },
      ),
    );
  }
}
