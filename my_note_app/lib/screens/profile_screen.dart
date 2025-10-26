import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/widgets/post_card.dart';

class ProfileScreen extends StatefulWidget {
  /// โปรไฟล์ที่ต้องการเปิดดู; ถ้าไม่ส่งมา จะเปิดโปรไฟล์ตนเอง
  final int? userId;

  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int? _viewerId;          // id ของคนที่กำลังดู
  int? _profileUserId;     // id ของโปรไฟล์ที่เปิด
  bool _loading = true;

  Map<String, dynamic>? _profile; // username, avatar_url, bio, ...
  List<dynamic> _posts = [];

  bool get _isMe => _viewerId != null && _viewerId == _profileUserId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final sp = await SharedPreferences.getInstance();
    final viewerId = sp.getInt('user_id');
    final targetId = widget.userId ?? viewerId;

    if (targetId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบ')),
      );
      return;
    }

    setState(() {
      _viewerId = viewerId;
      _profileUserId = targetId;
    });

    await _loadAll();
  }

Future<void> _loadAll() async {
  if (_profileUserId == null) return;
  setState(() => _loading = true);

  Map<String, dynamic>? p;
  List<dynamic> posts = [];

  // 1) โหลดโปรไฟล์ (ต้องพยายามให้สำเร็จก่อน)
  try {
    p = await ApiService.getUserProfile(_profileUserId!);
  } catch (e) {
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('โหลดโปรไฟล์ไม่สำเร็จ: $e')),
    );
    return; // ไม่มีโปรไฟล์ แสดงผลต่อไม่ได้
  }

  // 2) โหลดโพสต์ (ถ้าพัง ให้ผ่านไปก่อน)
  try {
    posts = await ApiService.getPostsByUser(
      profileUserId: _profileUserId!,
      viewerId: _viewerId ?? 0,
    );
  } catch (e) {
    // แจ้งเตือนแบบเบา ๆ แล้วไปต่อ
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('โหลดโพสต์ไม่สำเร็จ')),
      );
    }
  }

  if (!mounted) return;
  setState(() {
    _profile = p;
    _posts = posts;
    _loading = false;
  });
}

  Future<void> _refresh() async => _loadAll();

  @override
  Widget build(BuildContext context) {
     final avatar = (_profile?['avatar_url'] as String?) ?? '';
  final bio = (_profile?['bio'] as String?) ?? '';
  final username = (_profile?['username'] as String?) ?? '';

  // ใช้ count จาก backend ถ้ามี ไม่งั้น fallback เป็นที่โหลดมา
  final postCount = (_profile?['post_count'] as int?) ?? _posts.length;
  final friendCount = (_profile?['friends_count'] as int?) ?? 0;

    return Scaffold(
  body: _loading
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              if (_posts.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('ยังไม่มีโพสต์')),
                )
              else
                SliverList.separated(
                  itemCount: _posts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => PostCard(post: _posts[i]),
                ),
            ],
          ),
        ),
);
  }

  Widget _buildHeader() {
    final avatar = (_profile?['avatar_url'] as String?) ?? '';
    final bio = (_profile?['bio'] as String?) ?? '';
    final username = (_profile?['username'] as String?) ?? '';

    // นับโพสต์จากที่โหลดมา (หรือให้ backend ส่ง count มาก็ได้)
    final postCount = _posts.length;
    // เพื่อน (ยังไม่ทำระบบ friend จริง ๆ ใส่ 0 ไว้ก่อนหรือรับจาก backend)
    final friendCount = _profile?['friend_count'] as int? ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // username มุมซ้ายบน
          Text(
            username,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),

          // avatar + counters
          Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: avatar.isNotEmpty
                    ? NetworkImage('${ApiService.host}$avatar')
                    : const AssetImage('assets/default_avatar.png')
                        as ImageProvider,
              ),
              const SizedBox(width: 24),
              _Counter(label: 'post', value: postCount),
              const SizedBox(width: 24),
              _Counter(label: 'friends', value: friendCount),
            ],
          ),

          const SizedBox(height: 12),

          // bio
          if (bio.trim().isNotEmpty)
            Text(
              bio,
              style: const TextStyle(color: Colors.black87),
            ),

          const SizedBox(height: 12),

          // button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (_isMe) {
                  // ไปหน้าแก้โปรไฟล์ของคุณ (ถ้ามี)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Edit profile (coming soon)')),
                  );
                } else {
                  // กด Add friend (placeholder)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ส่งคำขอเป็นเพื่อนแล้ว')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                backgroundColor: _isMe ? Colors.blueGrey.shade700 : Colors.black,
                foregroundColor: Colors.white,
              ),
              child: Text(_isMe ? 'Edit Profile' : 'Add friend'),
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  final String label;
  final int value;
  const _Counter({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value',
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }
}