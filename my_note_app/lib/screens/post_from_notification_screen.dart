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

    // 1) พยายามใช้ ApiService ก่อน
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
      // ถ้า fail ค่อย fallback ด้านล่าง
    }

    // 2) fallback ยิง REST ตรง
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

  /// ทำให้โครงสร้างข้อมูลจาก endpoint ต่างๆ กลายเป็นรูปแบบที่ PostCard ใช้ได้
  Map<String, dynamic> _normalizeToPostCard(Map raw) {
    final Map data = (raw['post'] is Map) ? (raw['post'] as Map) : raw;

    // ---- Owner name/username (ลองหลายคีย์) ----
    final username = (data['username'] ??
            data['owner_username'] ??
            data['owner_name'] ??
            data['author_name'] ??
            data['user_name'] ??
            data['display_name'] ??
            data['name'] ??
            '')
        .toString();

    // ---- Avatar url (ลองหลายคีย์) ----
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

    // ---- Images รองรับหลายรูปแบบ ----
    // 1) List<String>
    // 2) String (เป็น JSON array)
    // 3) List<Map> ที่มี key 'image_url'
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

    // ---- legacy single image ----
    final legacyImg = (data['image_url'] ?? '').toString();

    // ---- counts & states ----
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

      // รูปหลายรูป + เผื่อ legacy รูปเดี่ยว
      'images'    : images,
      'image_url' : legacyImg,

      // ไฟล์แนบ
      'file_url'  : fileUrl,

      // ตัวนับ/สถานะ
      'like_count'    : likeCount,       // ถ้า null PostCard จะไปโหลดเอง
      'comment_count' : commentCount,    // เช่นกัน
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

// post_from_notification_screen.dart
// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'package:my_note_app/api/api_service.dart';
// import 'package:my_note_app/widgets/post_card.dart';

// class PostFromNotificationScreen extends StatefulWidget {
//   final int postId;
//   final int viewerUserId;
//   const PostFromNotificationScreen({
//     super.key,
//     required this.postId,
//     required this.viewerUserId,
//   });

//   @override
//   State<PostFromNotificationScreen> createState() => _PostFromNotificationScreenState();
// }

// class _PostFromNotificationScreenState extends State<PostFromNotificationScreen> {
//   Map<String, dynamic>? _postForCard; // รูปแบบที่ PostCard ใช้ได้ทันที
//   bool _loading = true;
//   String? _err;

//   @override
//   void initState() {
//     super.initState();
//     _load();
//   }

//   Future<void> _load() async {
//     setState(() {
//       _loading = true;
//       _err = null;
//     });

//     // 1) ลองใช้ ApiService ก่อน (ถ้ามี)
//     try {
//       final m = await ApiService.getPostDetail(
//         postId: widget.postId,
//         viewerUserId: widget.viewerUserId,
//       );
//       setState(() {
//         _postForCard = _normalizeToPostCard(m);
//         _loading = false;
//       });
//       return;
//     } catch (_) {}

//     // 2) fallback ยิง REST ตรง
//     try {
//       final uri = Uri.parse(
//         '${ApiService.host}/api/posts/${widget.postId}?user_id=${widget.viewerUserId}',
//       );
//       final res = await http.get(uri);
//       if (res.statusCode == 200) {
//         final json = jsonDecode(res.body);
//         setState(() {
//           _postForCard = _normalizeToPostCard(json);
//           _loading = false;
//         });
//       } else {
//         setState(() {
//           _err = 'โหลดโพสต์ไม่สำเร็จ (${res.statusCode})';
//           _loading = false;
//         });
//       }
//     } catch (e) {
//       setState(() {
//         _err = '$e';
//         _loading = false;
//       });
//     }
//   }

//   // ---- ทำให้ข้อมูลจาก endpoint ต่างๆ กลายเป็น Map ที่ PostCard ต้องการ ----
//   Map<String, dynamic> _normalizeToPostCard(Map raw) {
//     final data = (raw['post'] is Map) ? (raw['post'] as Map) : raw;

//     // ผู้เขียนโพสต์ (รองรับหลาย key ที่ backend อาจให้มา)
//     final username = (data['username'] ??
//             data['owner_name'] ??
//             data['author_name'] ??
//             data['user_name'] ??
//             '')
//         .toString();

//     final avatarUrl = (data['avatar_url'] ??
//             data['owner_avatar_url'] ??
//             data['author_avatar_url'] ??
//             data['user_avatar_url'] ??
//             '')
//         .toString();

//     final subject = (data['subject'] ?? '').toString();
//     final yearLabel = (data['year_label'] ?? '').toString();
//     final text = (data['text'] ?? '').toString();
//     final createdAt = (data['created_at'] ?? '').toString();
//     final fileUrl = (data['file_url'] ?? '').toString();

//     // รูปหลายรูป (รองรับ list แท้ หรือ string JSON)
//     List<String> images = <String>[];
//     final imgs = data['images'];
//     if (imgs is List) {
//       images = imgs.map((e) => e.toString()).toList();
//     } else if (imgs is String && imgs.trim().startsWith('[')) {
//       try {
//         images = (jsonDecode(imgs) as List).map((e) => e.toString()).toList();
//       } catch (_) {}
//     }

//     // รูปเดี่ยว legacy
//     final legacyImg = (data['image_url'] ?? '').toString();

//     // นับ like/comment + สถานะ liked_by_me (พยายามรับได้หลายแบบ)
//     final likeCount = _asInt(data['like_count']) ?? 0;
//     final commentCount = _asInt(data['comment_count']) ?? 0;
//     final likedByMe = _asBool(
//       data['liked_by_me'] ??
//           data['like_by_me'] ??
//           data['likedByMe'] ??
//           data['is_liked'] ??
//           data['liked'],
//     );

//     return {
//       'id': _asInt(data['id']),
//       'user_id': _asInt(data['user_id'] ?? data['author_id']),
//       'username': username,
//       'avatar_url': avatarUrl,
//       'subject': subject,
//       'year_label': yearLabel,
//       'text': text,
//       'created_at': createdAt,
//       'images': images,          // PostCard จะเติม host เอง
//       'image_url': legacyImg,    // ถ้า images ว่าง PostCard จะใช้ตัวนี้
//       'file_url': fileUrl,
//       'like_count': likeCount,       // ให้ค่าเริ่มต้น 0 เพื่อ “แสดงทันที”
//       'comment_count': commentCount, // แล้ว PostCard จะ sync เพิ่มด้วย getCounts อีกรอบ
//       'liked_by_me': likedByMe,
//     };
//   }

//   int? _asInt(dynamic v) {
//     if (v == null) return null;
//     if (v is int) return v;
//     if (v is num) return v.toInt();
//     return int.tryParse('$v');
//   }

//   bool _asBool(dynamic v) {
//     if (v is bool) return v;
//     if (v is int) return v != 0;
//     final s = '$v'.toLowerCase();
//     return s == 'true' || s == 't' || s == '1' || s == 'yes';
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (_loading) {
//       return const Scaffold(body: Center(child: CircularProgressIndicator()));
//     }
//     if (_err != null) {
//       return Scaffold(
//         appBar: AppBar(title: const Text('โพสต์')),
//         body: Center(
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Text('เกิดข้อผิดพลาด: $_err'),
//               const SizedBox(height: 8),
//               ElevatedButton(onPressed: _load, child: const Text('ลองใหม่')),
//             ],
//           ),
//         ),
//       );
//     }

//     final post = _postForCard!;
//     return Scaffold(
//       appBar: AppBar(title: const Text('โพสต์')),
//       body: RefreshIndicator(
//         onRefresh: _load,
//         child: ListView(
//           padding: const EdgeInsets.symmetric(vertical: 8),
//           children: [
//             PostCard(
//               post: post,
//               onDeleted: () => Navigator.pop(context, true),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
