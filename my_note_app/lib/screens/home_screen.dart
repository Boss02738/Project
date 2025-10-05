import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/NewPost.dart';
import 'package:my_note_app/screens/login_screen.dart';
import 'package:my_note_app/screens/search_screen.dart';

class homescreen extends StatefulWidget {
  const homescreen({super.key});
  @override
  State<homescreen> createState() => _HomeState();
}

class _HomeState extends State<homescreen> {
  int _currentIndex = 0;
  late Future<List<dynamic>> _futureFeed;

  int? _userId;
  String? _username;
  bool _loadingUser = true;

  // เก็บ id โพสต์ที่กำลัง “ขยายข้อความ”
  final Set<int> _expandedPosts = {};

  @override
  void initState() {
    super.initState();
    _loadUserThenFeed();
  }

  Future<void> _loadUserThenFeed() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('user_id');
    final name = prefs.getString('username');

    if (id == null || name == null || name.isEmpty) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    setState(() {
      _userId = id;
      _username = name;
      _loadingUser = false;
      _futureFeed = ApiService.getFeed();
    });
  }

  Future<void> _reload() async {
    setState(() => _futureFeed = ApiService.getFeed());
  }

  // เวลาแบบย่อ
  String _timeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    DateTime dt;
    try { dt = DateTime.parse(iso).toLocal(); } catch (_) { return ''; }
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds} วิ.';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาที';
    if (diff.inHours < 24) return '${diff.inHours} ชม.';
    if (diff.inDays < 7) return '${diff.inDays} วัน';
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}/$m/$d';
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final screens = [
      FutureBuilder<List<dynamic>>(
        future: _futureFeed,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text('โหลดฟีดไม่สำเร็จ — ดึงลงเพื่อรีโหลด')),
                ],
              ),
            );
          }
          final feed = snap.data ?? [];
          if (feed.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text('ยังไม่มีโพสต์')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: feed.length,
              itemBuilder: (_, i) {
                final p        = feed[i];
                final postId   = (p['id'] as int?) ?? i;
                final avatar   = (p['avatar_url'] as String?) ?? '';
                final img      = (p['image_url']  as String?) ?? '';
                final file     = (p['file_url']   as String?) ?? '';
                final name     = p['username'] as String? ?? '';
                final text     = p['text'] as String? ?? '';
                final subject  = p['subject'] as String? ?? '';
                final year     = p['year_label'] as String? ?? ''; // ปี 1/2/3/4/วิชาเฉพาะเลือก
                final created  = p['created_at'] as String?;

                final isExpanded = _expandedPosts.contains(postId);
                final showSeeMore = text.trim().length > 80; // เกณฑ์คร่าว ๆ

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---------- Header (username + ปี อยู่บนหัว; subject + เวลาเป็น subtitle) ----------
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundImage: avatar.isNotEmpty
                              ? NetworkImage('${ApiService.host}$avatar')
                              : const AssetImage('assets/default_avatar.png') as ImageProvider,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (year.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF4FF),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  year,
                                  style: const TextStyle(fontSize: 11.5, color: Color.fromARGB(255, 83, 83, 83)),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          subject.isNotEmpty
                              ? '$subject'   
                              : '',
                        ),
                        trailing: const Icon(Icons.more_horiz),
                      ),

                      // ---------- รูปหลัก ----------
                      if (img.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: double.infinity,
                              height: 220,
                              color: const Color(0xFFEFEFEF),
                              child: Image.network(
                                '${ApiService.host}$img',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Center(child: Icon(Icons.image_not_supported)),
                                loadingBuilder: (ctx, child, evt) {
                                  if (evt == null) return child;
                                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                                },
                              ),
                            ),
                          ),
                        ),

                      // ---------- ไฟล์แนบ ----------
                      if (file.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                              color: const Color(0xFFFBFBFB),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.insert_drive_file, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    file.split('/').last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.download_rounded),
                                  onPressed: () {
                                    // TODO: ดาวน์โหลดไฟล์ถ้าต้องการ
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                      // ---------- “username (ดำ) + เนื้อหา” อยู่บรรทัดเดียว (ตัด 2 บรรทัด + ดูเพิ่มเติม/ย่อ) ----------
                      // ---------- “username (ดำ) + เนื้อหา” ----------
if (text.trim().isNotEmpty)
  Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$name ',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              TextSpan(
                text: text,
                style: const TextStyle(color: Colors.black87),
              ),
            ],
          ),
          maxLines: isExpanded ? null : 2,
          overflow: isExpanded
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
        ),
        if (showSeeMore)
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              setState(() {
                if (isExpanded) {
                  _expandedPosts.remove(postId);
                } else {
                  _expandedPosts.add(postId);
                }
              });
            },
            child: Text(isExpanded ? 'ย่อ' : 'ดูเพิ่มเติม'),
          ),
      ],
    ),
  ),

// ---------- เวลาโพสต์ไว้ด้านล่าง ----------
Padding(
  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
  child: Text(
    _timeAgo(created),
    style: const TextStyle(color: Colors.grey, fontSize: 12),
  ),
),


                      const SizedBox(height: 8),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
      const SearchScreen(),
      const Center(child: Text('Add Screen')),
      const Center(child: Text('Profile Screen')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Note app'),
        automaticallyImplyLeading: false,
      ),
      body: Column(children: [Expanded(child: screens[_currentIndex])]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color.fromARGB(255, 31, 102, 160),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) async {
          if (index == 2) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NewPostScreen(
                  userId: _userId!,
                  username: _username ?? '',
                ),
              ),
            );
          } else if (index == 1) {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            );
          } else {
            setState(() => _currentIndex = index);
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Add'),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle_outlined), label: 'Profile'),
        ],
      ),
    );
  }
}
