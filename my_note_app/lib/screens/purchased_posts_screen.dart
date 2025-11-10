import 'package:flutter/material.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/widgets/post_card.dart';

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

  String _abs(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('/')) return '${ApiService.host}$url';
    return '${ApiService.host}/$url';
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }

  Map<String, dynamic> _toPostCardData(Map r) {
    final List imgs = (r['images'] is List) ? r['images'] : const [];
    final List<String> fixedImgs = imgs.map((e) => _abs('$e')).cast<String>().toList();
    final ownerId = _asInt(r['user_id'] ?? r['author_id'] ?? r['owner_id'] ?? r['created_by']);

    final priceType = (r['price_type'] ?? 'free').toString().toLowerCase().trim();

    return <String, dynamic>{
      'id': _asInt(r['id']) ?? r['id'],
      'user_id': ownerId,
      'username': (r['username'] ?? '').toString(),
      'avatar_url': _abs(r['avatar_url'] ?? r['avatar'] ?? r['profile_image'] ?? r['photo']),
      'text': (r['text'] ?? '').toString(),
      'subject': (r['subject'] ?? '').toString(),
      'year_label': (r['year_label'] ?? '').toString(),
      'created_at': (r['created_at'] ?? r['granted_at'])?.toString(),
      'images': fixedImgs,
      'image_url': _abs('${r['image_url'] ?? ''}'),
      'file_url': _abs('${r['file_url'] ?? ''}'),
      'like_count': r['like_count'] ?? 0,
      'comment_count': r['comment_count'] ?? 0,
      'liked_by_me': r['liked_by_me'] == true,
      'price_type': priceType,
      'price_amount_satang': r['price_amount_satang'] ?? 0,
      'purchased': true,
      'is_purchased': true,
      'purchased_by_me': true,
      'granted_at': r['granted_at'],
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

          final data = snap.data ?? const [];
          if (data.isEmpty) {
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

          final rows = <Map<String, dynamic>>[];
          for (final it in data) {
            if (it is Map) {
              rows.add(_toPostCardData(it));
            }
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: rows.length,
              itemBuilder: (_, i) => PostCard(post: rows[i]),
            ),
          );
        },
      ),
    );
  }
}
