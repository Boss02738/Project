import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/NewPost.dart';
import 'package:my_note_app/screens/login_screen.dart';
import 'package:my_note_app/screens/search_screen.dart';
import 'package:my_note_app/widgets/post_card.dart';

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
                final p = feed[i];
                return PostCard(post: p);
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
