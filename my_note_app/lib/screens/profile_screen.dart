import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/widgets/post_card.dart';
import 'package:my_note_app/screens/settings_screen.dart';
import 'package:my_note_app/screens/edit_profile_screen.dart';
import 'package:my_note_app/widgets/friend_action_button.dart';

// ⬇️ เพิ่ม import สำหรับ bottom nav และหน้าที่จะนำทางไป
import 'package:my_note_app/widgets/app_bottom_nav_bar.dart';
import 'package:my_note_app/screens/home_screen.dart';
import 'package:my_note_app/screens/search_screen.dart';
import 'package:my_note_app/screens/documents_screen.dart';
import 'package:my_note_app/screens/NewPost.dart';

class ProfileScreen extends StatefulWidget {
  /// โปรไฟล์ที่ต้องการเปิดดู; ถ้าไม่ส่งมา จะเปิดโปรไฟล์ตนเอง
  final int? userId;

  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int? _viewerId; // id ของคนที่กำลังดู
  int? _profileUserId; // id ของโปรไฟล์ที่เปิด
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('กรุณาเข้าสู่ระบบ')));
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

    // 1) โหลดโปรไฟล์
    try {
      p = await ApiService.getUserProfile(_profileUserId!);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('โหลดโปรไฟล์ไม่สำเร็จ: $e')));
      return;
    }

    // 2) โหลดโพสต์
    try {
      posts = await ApiService.getPostsByUser(
        profileUserId: _profileUserId!,
        viewerId: _viewerId ?? 0,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('โหลดโพสต์ไม่สำเร็จ')));
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

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isMe ? 'Profile' : (_profile?['username'] ?? 'Profile')),
        automaticallyImplyLeading: true,
        actions: [
          if (_isMe)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
        ],
      ),
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

      // ✅ ใช้ AppBottomNavBar (index 4 = Profile)
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: 4,
        onTapAsync: (index) async {
          if (index == 0) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const homescreen()),
            );
          } else if (index == 1) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            );
          } else if (index == 2) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const DocumentsScreen()),
            );
          } else if (index == 3) {
            // ไปหน้าเพิ่มโพสต์ ต้องมี userId และ username
            final sp = await SharedPreferences.getInstance();
            final uid = sp.getInt('user_id');
            final uname = sp.getString('username') ?? '';
            if (uid == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนโพสต์')),
              );
              return;
            }
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => NewPostScreen(userId: uid, username: uname),
              ),
            );
          } else if (index == 4) {
            // อยู่หน้า Profile แล้ว — ไม่ต้องทำอะไร
          }
        },
      ),
    );
  }

  Widget _buildHeader() {
    final avatar = (_profile?['avatar_url'] as String?) ?? '';
    final bio = (_profile?['bio'] as String?) ?? '';
    final username = (_profile?['username'] as String?) ?? '';

    // นับโพสต์จากที่โหลดมา (หรือให้ backend ส่ง count มาก็ได้)
    final postCount = _posts.length;
    // ใช้ friends_count ถ้ามี (รองรับ friend_count เดิมเป็น fallback)
    final friendCount =
        (_profile?['friends_count'] as int?) ?? (_profile?['friend_count'] as int?) ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ชื่อ
          Text(
            username.isNotEmpty ? username : 'user#${_profileUserId ?? ''}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
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
            Text(bio, style: const TextStyle(color: Colors.black87)),

          const SizedBox(height: 12),

          // ===== ปุ่มด้านล่างรูปโปรไฟล์ =====
          SizedBox(
            width: double.infinity,
            child: _isMe
                ? ElevatedButton(
                    onPressed: () async {
                      final changed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditProfileScreen(
                            userId: _profileUserId!,
                            initialUsername:
                                (_profile?['username'] as String?) ?? '',
                            initialBio: (_profile?['bio'] as String?) ?? '',
                            initialAvatar:
                                (_profile?['avatar_url'] as String?) ?? '',
                          ),
                        ),
                      );
                      if (changed == true) _refresh();
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      backgroundColor: Colors.blueGrey.shade700,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Edit Profile'),
                  )
                : (_viewerId == null
                    ? ElevatedButton(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('กรุณาเข้าสู่ระบบเพื่อเพิ่มเพื่อน'),
                      )
                    : // ใช้ FriendActionButton ที่เชื่อม API แล้ว
                    FriendActionButton(
                        meId: _viewerId!,
                        otherId: _profileUserId!,
                      )),
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
        Text(
          '$value',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }
}
