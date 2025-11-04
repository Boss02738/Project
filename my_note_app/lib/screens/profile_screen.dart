// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/widgets/post_card.dart';
import 'package:my_note_app/screens/settings_screen.dart';
import 'package:my_note_app/screens/edit_profile_screen.dart';
import 'package:my_note_app/widgets/friend_action_button.dart';
import 'package:my_note_app/screens/friends_list_screen.dart';

class ProfileScreen extends StatefulWidget {
  final int? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int? _viewerId;
  int? _profileUserId;
  bool _loading = true;

  Map<String, dynamic>? _profile;
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
      setState(() => _loading = false);
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

    try {
      final p = await ApiService.getUserProfile(_profileUserId!);
      final posts = await ApiService.getPostsByUser(
        profileUserId: _profileUserId!,
        viewerId: _viewerId ?? 0,
      );
      if (!mounted) return;
      setState(() {
        _profile = p;
        _posts = posts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('โหลดข้อมูลไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _refresh() async => _loadAll();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(_isMe ? 'Profile' : (_profile?['username'] ?? 'Profile')),
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
                  SliverToBoxAdapter(child: _buildHeader(context)),
                  if (_posts.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('ยังไม่มีโพสต์')),
                    )
                  else
                    // Flutter ไม่มี SliverList.separated -> แทรก Divider เอง
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index.isOdd) {
                            return Divider(
                              height: 1,
                              color: Theme.of(context).dividerColor,
                            );
                          }
                          final i = index ~/ 2;
                          return PostCard(post: _posts[i]);
                        },
                        childCount: _posts.length * 2 - 1,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;

    final avatar = (_profile?['avatar_url'] as String?) ?? '';
    final bio = (_profile?['bio'] as String?) ?? '';
    final username = (_profile?['username'] as String?) ?? '';

    final postCount = _posts.length;
    final friendCount =
        (_profile?['friends_count'] as int?) ??
            (_profile?['friend_count'] as int?) ??
            0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ชื่อผู้ใช้
          Text(
            username.isNotEmpty ? username : 'user#${_profileUserId ?? ''}',
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),

          // ✅ เอา container การ์ดออก เหลือแค่แถวโปร่ง ๆ
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: avatar.isNotEmpty
                    ? NetworkImage('${ApiService.host}$avatar')
                    : const AssetImage('assets/default_avatar.png')
                        as ImageProvider,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  children: [
                    const Spacer(),
                    _RightStat(label: 'post', value: postCount),
                    const Spacer(),
                    InkWell(
                      onTap: () {
                        final uid = _profileUserId;
                        if (uid != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FriendsListScreen(userId: uid),
                            ),
                          );
                        }
                      },
                      child: _RightStat(label: 'friends', value: friendCount),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (bio.trim().isNotEmpty)
            Text(
              bio,
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),

          const SizedBox(height: 12),

          // ปุ่มหลัก
          SizedBox(
            width: double.infinity,
            child: _isMe
                ? FilledButton(
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
                    child: const Text('Edit Profile'),
                  )
                : (_viewerId == null
                    ? FilledButton.tonal(
                        onPressed: null,
                        child: const Text('กรุณาเข้าสู่ระบบเพื่อเพิ่มเพื่อน'),
                      )
                    : FriendActionButton(
                        meId: _viewerId!,
                        otherId: _profileUserId!,
                      )),
          ),

          const SizedBox(height: 12),
          Divider(height: 1, color: theme.dividerColor),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _RightStat extends StatelessWidget {
  final String label;
  final int value;
  const _RightStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

