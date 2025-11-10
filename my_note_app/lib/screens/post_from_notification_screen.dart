import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/widgets/post_card.dart';

class PostFromNotificationScreen extends StatefulWidget {
  final int postId;
  final int viewerUserId;
  const PostFromNotificationScreen({
    super.key,
    required this.postId,
    required this.viewerUserId,
  });

  @override
  State<PostFromNotificationScreen> createState() => _PostFromNotificationScreenState();
}

class _PostFromNotificationScreenState extends State<PostFromNotificationScreen> {
  bool _loading = true;
  String? _err;
  Map<String, dynamic>? _postForCard;

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

    try {
      final m = await ApiService.getPostDetail(
        postId: widget.postId,
        viewerUserId: widget.viewerUserId,
      );
      setState(() {
        _postForCard = _normalizeToPostCard(m as Map);
        _loading = false;
      });
      return;
    } catch (_) {
    }

    try {
      final uri = Uri.parse(
        '${ApiService.host}/api/posts/${widget.postId}?user_id=${widget.viewerUserId}',
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _postForCard = _normalizeToPostCard(json);
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

  Map<String, dynamic> _normalizeToPostCard(Map raw) {
    final Map data = (raw['post'] is Map) ? (raw['post'] as Map) : raw;

    final username = (data['username'] ??
            data['owner_username'] ??
            data['owner_name'] ??
            data['author_name'] ??
            data['user_name'] ??
            data['display_name'] ??
            data['name'] ??
            '')
        .toString();

    final avatarUrl = (data['avatar_url'] ??
            data['owner_avatar_url'] ??
            data['author_avatar_url'] ??
            data['user_avatar_url'] ??
            data['avatar'] ??
            data['profile_image_url'] ??
            data['profile_url'] ??
            data['avatarUrl'] ??
            '')
        .toString();

    final subject   = (data['subject'] ?? '').toString();
    final yearLabel = (data['year_label'] ?? '').toString();
    final text      = (data['text'] ?? '').toString();
    final createdAt = (data['created_at'] ?? '').toString();
    final fileUrl   = (data['file_url'] ?? '').toString();

    List<String> images = <String>[];
    final imgs = data['images'];
    if (imgs is List) {
      if (imgs.isNotEmpty && imgs.first is Map) {
        images = imgs.map((e) => (e['image_url'] ?? e['url'] ?? '').toString()).where((e) => e.isNotEmpty).toList();
      } else {
        images = imgs.map((e) => e.toString()).toList();
      }
    } else if (imgs is String && imgs.trim().startsWith('[')) {
      try {
        final parsed = (jsonDecode(imgs) as List).map((e) {
          if (e is Map) return (e['image_url'] ?? e['url'] ?? '').toString();
          return e.toString();
        }).where((e) => e.isNotEmpty).toList();
        images = parsed;
      } catch (_) {}
    }

    final legacyImg = (data['image_url'] ?? '').toString();

    final likeCount    = _asInt(data['like_count']);
    final commentCount = _asInt(data['comment_count']);
    final likedByMe = _asBool(
      data['liked_by_me'] ??
      data['like_by_me'] ??
      data['likedByMe'] ??
      data['is_liked'] ??
      data['liked'],
    );

    return <String, dynamic>{
      'id'         : _asInt(data['id']),
      'user_id'    : _asInt(data['user_id'] ?? data['author_id'] ?? data['owner_id']),
      'username'   : username,
      'avatar_url' : avatarUrl,
      'subject'    : subject,
      'year_label' : yearLabel,
      'text'       : text,
      'created_at' : createdAt,
      'images'    : images,
      'image_url' : legacyImg,
      'file_url'  : fileUrl,
      'like_count'    : likeCount,      
      'comment_count' : commentCount,    
      'liked_by_me'   : likedByMe,
    };
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    final s = '$v'.toLowerCase();
    return s == 'true' || s == 't' || s == '1' || s == 'yes';
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
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            PostCard(
              post: _postForCard!,
              onDeleted: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
  }
}
