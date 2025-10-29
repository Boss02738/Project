import 'package:flutter/material.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/widgets/post_card.dart';
import 'package:my_note_app/widgets/purchased_overlay.dart';

/// ใช้ PostCard + ป้าย “ซื้อแล้ว”
class PurchasedPostsFeedScreen extends StatefulWidget {
  final int userId;
  const PurchasedPostsFeedScreen({super.key, required this.userId});

  @override
  State<PurchasedPostsFeedScreen> createState() => _PurchasedPostsFeedScreenState();
}

class _PurchasedPostsFeedScreenState extends State<PurchasedPostsFeedScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getPurchasedPosts(widget.userId);
  }

  Future<void> _reload() async {
    setState(() => _future = ApiService.getPurchasedPosts(widget.userId));
  }

  Map<String, dynamic> _toPostLike(Map<String, dynamic> p) {
    final dynamic pidRaw = p['post_id'] ?? p['id'] ?? 0;
    final int postId = (pidRaw is int) ? pidRaw : int.tryParse('$pidRaw') ?? 0;

    String? imageUrl;
    final dynamic imgsRaw =
        p['images'] ?? p['post_images'] ?? p['postImages'] ?? p['image_urls'];
    if (imgsRaw is List && imgsRaw.isNotEmpty) {
      final first = imgsRaw.first;
      if (first is Map && first['url'] is String) {
        imageUrl = '${ApiService.host}${first['url']}';
      } else if (first is String) {
        imageUrl = '${ApiService.host}$first';
      }
    } else if (p['image_url'] is String) {
      imageUrl = '${ApiService.host}${p['image_url']}';
    }

    final dynamic priceRaw = p['price_amount_satang'] ?? 0;
    final int priceSatang =
        (priceRaw is int) ? priceRaw : int.tryParse('$priceRaw') ?? 0;

    final sellerName =
        (p['seller_name'] as String?) ?? (p['username'] as String?) ?? 'ผู้ขาย';

    return <String, dynamic>{
      'id': postId,
      'text': (p['text'] as String?) ?? (p['title'] as String?) ?? '',
      'subject': (p['subject'] as String?) ?? '',
      'username': sellerName,
      'user_id': p['seller_id'] ?? p['user_id'],
      'created_at': p['created_at'] ?? p['granted_at'],
      'image_url': imageUrl,
      'images': imgsRaw,
      'price_type': 'paid',
      'price_amount_satang': priceSatang,
      // กันพังถ้า PostCard อ้างถึง
      'likes_count': p['likes_count'] ?? 0,
      'comments_count': p['comments_count'] ?? 0,
      'saves_count': p['saves_count'] ?? 0,
      'avatar_url': p['seller_avatar'] ?? p['avatar_url'],
      'year_label': p['year_label'],
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchased posts (cards)')), // เปลี่ยนชื่อชัด ๆ
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
                  Center(child: Text('โหลดไม่สำเร็จ — ดึงลงเพื่อรีโหลด')),
                ],
              ),
            );
          }

          final raw = (snap.data ?? []).cast<Map<String, dynamic>>();
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

          final items = raw.map(_toPostLike).toList();

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 20),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final postLike = items[i];
                final card = PostCard(post: postLike);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PurchasedOverlay(child: card),
                    const SizedBox(height: 8),
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
