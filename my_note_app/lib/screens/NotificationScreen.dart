import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/widgets/post_card.dart';

/// ===== helpers =====
String absUrl(String p) {
  if (p.isEmpty) return p;
  if (p.startsWith('http://') || p.startsWith('https://')) return p;
  if (p.startsWith('/')) return '${ApiService.host}$p';
  return '${ApiService.host}/$p';
}

/// ---- แปลง payload จาก endpoint ต่าง ๆ ให้เป็นรูปแบบที่ PostCard ใช้ได้ ----
Map<String, dynamic> normalizePostForCard(Map raw) {
  final Map data = (raw['post'] is Map) ? (raw['post'] as Map) : raw;

  String username = (data['username'] ??
          data['owner_username'] ??
          data['author_name'] ??
          data['user_name'] ??
          data['display_name'] ??
          data['name'] ??
          '')
      .toString();

  String avatarUrl = (data['avatar_url'] ??
          data['owner_avatar_url'] ??
          data['author_avatar_url'] ??
          data['user_avatar_url'] ??
          data['avatar'] ??
          data['profile_image_url'] ??
          data['profile_url'] ??
          data['avatarUrl'] ??
          '')
      .toString();

  // images รองรับ: List<String> | List<Map> | String(JSON)
  List<String> images = <String>[];
  final imgs = data['images'];
  if (imgs is List) {
    if (imgs.isNotEmpty && imgs.first is Map) {
      images = imgs
          .map((e) => (e['image_url'] ?? e['url'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      images = imgs.map((e) => e.toString()).toList();
    }
  } else if (imgs is String && imgs.trim().startsWith('[')) {
    try {
      final parsed = (jsonDecode(imgs) as List)
          .map((e) => e is Map ? (e['image_url'] ?? e['url'] ?? '').toString() : e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
      images = parsed;
    } catch (_) {}
  }

  int? asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  bool asBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    final s = '$v'.toLowerCase();
    return s == 'true' || s == 't' || s == '1' || s == 'yes';
  }

  return <String, dynamic>{
    'id'         : asInt(data['id']),
    'user_id'    : asInt(data['user_id'] ?? data['author_id'] ?? data['owner_id']),
    'username'   : username,
    'avatar_url' : avatarUrl,

    'subject'    : (data['subject'] ?? '').toString(),
    'year_label' : (data['year_label'] ?? '').toString(),
    'text'       : (data['text'] ?? '').toString(),
    'created_at' : (data['created_at'] ?? '').toString(),

    'images'     : images,
    'image_url'  : (data['image_url'] ?? '').toString(), // legacy

    'file_url'   : (data['file_url'] ?? '').toString(),

    'like_count'    : asInt(data['like_count']),
    'comment_count' : asInt(data['comment_count']),
    'liked_by_me'   : asBool(
      data['liked_by_me'] ?? data['like_by_me'] ?? data['likedByMe'] ?? data['is_liked'] ?? data['liked'] ?? false,
    ),
  };
}

/// ===== Post Detail (เปิดจาก noti จะมาอันนี้) =====
/// เปลี่ยนให้ใช้ PostCard โดยส่ง payload ที่ normalize แล้ว
class PostDetailScreen extends StatefulWidget {
  final int postId;
  final int viewerUserId;
  const PostDetailScreen({super.key, required this.postId, required this.viewerUserId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Map<String, dynamic>? _postCardData;
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    // ใช้ ApiService ก่อน ถ้าไม่สำเร็จค่อย fallback ยิงตรง
    try {
      final m = await ApiService.getPostDetail(
        postId: widget.postId,
        viewerUserId: widget.viewerUserId,
      );
      setState(() {
        _postCardData = normalizePostForCard(m as Map);
        _loading = false;
      });
      return;
    } catch (_) {}

    try {
      final uri = Uri.parse('${ApiService.host}/api/posts/${widget.postId}?user_id=${widget.viewerUserId}');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _postCardData = normalizePostForCard(json);
          _loading = false;
        });
      } else {
        setState(() {
          _err = 'โหลดโพสต์ไม่สำเร็จ (${res.statusCode})';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _err = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_err != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('โพสต์')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('เกิดข้อผิดพลาด: $_err'),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: _load, child: const Text('ลองใหม่')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('โพสต์')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          PostCard(post: _postCardData!),
        ],
      ),
    );
  }
}

/// ===== Notifications =====
class NotificationScreen extends StatefulWidget {
  final int userId;
  const NotificationScreen({super.key, required this.userId});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  late Future<List<dynamic>> _future;
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    _future = _fetchNotifications();
  }

  String _timeText(String iso) {
    try {
      final t = DateTime.parse(iso).toLocal();
      return '${t.year}-${t.month.toString().padLeft(2,'0')}-${t.day.toString().padLeft(2,'0')} '
             '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
    } catch (_) {
      return iso;
    }
  }

  Future<List<dynamic>> _fetchNotifications() async {
    final uri = Uri.parse(
      '${ApiService.host}/api/notifications?user_id=${widget.userId}&limit=50',
    );
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final m = jsonDecode(res.body);
      return (m['items'] as List?) ?? <dynamic>[];
    }
    throw Exception('โหลดแจ้งเตือนไม่สำเร็จ (${res.statusCode})');
  }

  Future<void> _markAllRead() async {
    if (_marking) return;
    setState(() => _marking = true);
    try {
      final uri = Uri.parse('${ApiService.host}/api/notifications/mark-all-read');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': widget.userId}),
      );
      if (res.statusCode == 200) {
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ทำเครื่องหมายไม่สำเร็จ (${res.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ผิดพลาด: $e')),
      );
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetchNotifications());
    await _future;
  }

  Future<void> _openItem(Map<String, dynamic> n) async {
    final int? postId = _toInt(n['post_id']);
    final int? notiId = _toInt(n['id']);

    // mark read (ไม่บล็อก)
    if (notiId != null) {
      try {
        await http.post(
          Uri.parse('${ApiService.host}/api/notifications/$notiId/mark-read'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': widget.userId}),
        );
      } catch (_) {}
    }

    if (postId != null) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostDetailScreen(
            postId: postId,
            viewerUserId: widget.userId,
          ),
        ),
      );
      await _refresh();
    }
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _marking ? null : _markAllRead,
            child: _marking
                ? const Text('กำลังทำ...', style: TextStyle(color: Colors.grey))
                : const Text('อ่านทั้งหมด'),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('ยังไม่มีแจ้งเตือน')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final n = (items[i] as Map).cast<String, dynamic>();
                final isRead = (n['is_read'] ?? false) as bool;
                final msg = (n['message'] ?? '').toString();
                final action = (n['action'] ?? '').toString();
                final ts = (n['created_at'] ?? '').toString();
                final actor = (n['actor_name'] ?? '').toString();
                final postText = (n['post_text'] ?? '').toString();
                final avatar = (n['actor_avatar_url'] ?? '').toString();

                return Material(
                  color: isRead
                      ? Theme.of(context).colorScheme.surface
                      : Theme.of(context).colorScheme.surfaceTint.withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: _Avatar(url: avatar, name: actor),
                    title: Text(
                      msg.isNotEmpty ? msg : action,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        if (actor.isNotEmpty) 'โดย: $actor',
                        if (postText.isNotEmpty)
                          'โพสต์: ${postText.length > 30 ? postText.substring(0, 30) + "..." : postText}',
                        _timeText(ts),
                      ].join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openItem(n),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  const _Avatar({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = (name.isNotEmpty ? name.trim()[0].toUpperCase() : '?');
    if (url.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: NetworkImage(absUrl(url)),
        onBackgroundImageError: (_, __) {},
        child: const SizedBox.shrink(),
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.blueGrey.shade100,
      child: Text(initials, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}