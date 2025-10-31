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

  /// เติม host ให้ path ที่ขึ้นต้นด้วย / หรือไม่มี http
  String _abs(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('/')) return '${ApiService.host}$url';
    return '${ApiService.host}/$url';
  }

  /// แปลงแถวจาก API -> โครงสำหรับ PostCard
  Map<String, dynamic> _toPostCardData(Map<String, dynamic> r) {
    // รูปภาพ (บางเคส api ส่งมาเป็น relative path)
    final List imgs = (r['images'] is List) ? r['images'] : const [];
    final fixedImgs = imgs.map((e) => _abs('$e')).toList();

    // normalize ชนิดราคา
    final priceType = (r['price_type'] ?? 'free').toString().toLowerCase().trim();

    return <String, dynamic>{
      'id': r['id'],
      'user_id': r['user_id'],                       // เจ้าของโพสต์ (owner)
      'username': (r['username'] ?? '').toString(),
      'avatar_url': _abs(r['avatar_url']),
      'text': (r['text'] ?? '').toString(),
      'subject': (r['subject'] ?? '').toString(),
      'year_label': (r['year_label'] ?? '').toString(),
      'created_at': (r['created_at'] ?? r['granted_at'])?.toString(),
      'granted_at': r['granted_at'],                 // เผื่อ PostCard ใช้ตรวจ purchased
      'images': fixedImgs,
      'image_url': _abs(r['image_url']),             // legacy single img
      'file_url': _abs(r['file_url']),
      'like_count': r['like_count'] ?? 0,
      'comment_count': r['comment_count'] ?? 0,
      'liked_by_me': r['liked_by_me'] == true,
      'price_type': priceType,
      'price_amount_satang': r['price_amount_satang'] ?? 0,

      // สำคัญ: บอกการ์ดว่า "โพสต์นี้ซื้อแล้ว"
      'purchased': true,
      'purchased_by_me': true,
      'is_purchased': true,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchased posts')),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          // กำลังโหลด
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // โหลดพลาด
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

          // ข้อมูลว่าง
          final raw = (snap.data ?? const []);
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

          // สร้างลิสต์การ์ด
          final rows = raw.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final post = _toPostCardData(rows[i]);

                // ครอบด้วยป้าย "ซื้อแล้ว" และส่งให้ PostCard
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
