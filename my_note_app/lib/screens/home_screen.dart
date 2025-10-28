import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/NewPost.dart';
import 'package:my_note_app/screens/login_screen.dart';
import 'package:my_note_app/screens/search_screen.dart';
import 'package:my_note_app/widgets/post_card.dart';
import 'package:my_note_app/screens/profile_screen.dart';
import 'package:my_note_app/screens/payment_screen.dart';

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
      _futureFeed = ApiService.getFeed(_userId!);
    });
  }

  Future<void> _reload() async {
    setState(() => _futureFeed = ApiService.getFeed(_userId!));
  }

  // เวลาแบบย่อ
  String _timeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    DateTime dt;
    try {
      dt = DateTime.parse(iso).toLocal();
    } catch (_) {
      return '';
    }
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
                final p = feed[i] as Map<String, dynamic>;

                // อ่านชนิดราคาและราคา (บาท) จากโพสต์
                final String priceType = (p['price_type'] ?? 'free').toString();
                final bool isPaid = priceType == 'paid';
                final int satang = (p['price_amount_satang'] ?? 0) is int
                    ? p['price_amount_satang'] as int
                    : int.tryParse('${p['price_amount_satang']}') ?? 0;
                final double priceBaht = satang / 100.0;

                // postId เป็น int
                final int postId = p['id'] is int ? p['id'] as int : int.parse('${p['id']}');

                // การ์ดโพสต์ "เดิม" (ไม่แตะโค้ดข้างใน)
                final postCard = PostCard(post: p);

                // ถ้าเป็นโพสต์ฟรี แสดงแค่การ์ดเดิม
                if (!isPaid) {
                  return postCard;
                }

                // เป็นโพสต์เสียเงิน → เช็คสิทธิ์ (hasAccess) เฉพาะเมื่อเป็น paid
                return FutureBuilder<Map<String, dynamic>>(
                  future: ApiService.getPostDetail(
                    postId: postId,
                    viewerUserId: _userId!,
                  ),
                  builder: (context, detailSnap) {
                    final bool hasAccess =
                        (detailSnap.data?['hasAccess'] == true);

                    // แถว “ราคา + ปุ่มซื้อ” ใต้การ์ด เฉพาะกรณี paid และยังไม่มีสิทธิ์
                    final priceBar = (!hasAccess)
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: Row(
                              children: [
                                Text(
                                  '${priceBaht.toStringAsFixed(2)} ฿',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                OutlinedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PaymentScreen(
                                          postId: postId,
                                          buyerId: _userId!,
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text('ซื้อ'),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink();

                    // รวมเป็นหนึ่งบล็อค โดย "ไม่แก้หน้าตา PostCard"
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        postCard,
                        priceBar,
                      ],
                    );
                  },
                );
              },
            ),
          );
        },
      ),
      const SearchScreen(),
      const Center(child: Text('Add Screen')),
      // show profile screen as one of the tab pages; pass current _userId (may be null)
      ProfileScreen(userId: _userId),
    ];

    return Scaffold(
      appBar: (_currentIndex == 3)
    ? null // ❌ ซ่อน AppBar ตอนอยู่หน้า Profile
    : AppBar(
        title: Text(
          _currentIndex == 1
              ? 'Search'
              : _currentIndex == 0
                  ? 'Home'
                  : 'Note app',
        ),
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
                builder: (_) =>
                    NewPostScreen(userId: _userId!, username: _username ?? ''),
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
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Add'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle_outlined),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
