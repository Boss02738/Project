import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/NewPost.dart';
import 'package:my_note_app/screens/login_screen.dart';
import 'package:my_note_app/screens/search_screen.dart';
import 'package:my_note_app/screens/profile_screen.dart';
import 'package:my_note_app/screens/purchase_screen.dart';

import 'package:my_note_app/widgets/post_card.dart';
import 'package:my_note_app/widgets/purchased_overlay.dart';

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
    if (_userId == null) return;
    setState(() => _futureFeed = ApiService.getFeed(_userId!));
  }

  // ---------- helpers แปลงชนิด ----------
  int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  String _asStr(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    return v.toString();
  }

  DateTime _asDate(dynamic v) {
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return DateTime.now().add(const Duration(minutes: 10));
    }
  }

  // ===== กด “ซื้อ” ที่แถวราคา =====
  Future<void> _handleBuy({
    required int postId,
    required int amountSatang,
  }) async {
    if (_userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนซื้อโพสต์')),
      );
      return;
    }

    Map<String, dynamic>? created;
    try {
      // ใช้เมธอดที่ประกาศใน ApiService (คืน {id, amount_satang, qr_payload, expires_at})
      created = await ApiService.startPurchase(
        postId: postId,
        buyerId: _userId!,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('สร้างคำสั่งซื้อไม่สำเร็จ : $e')));
      return;
    }

    if (created == null ||
        created['id'] == null ||
        created['qr_payload'] == null ||
        created['expires_at'] == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('สร้างคำสั่งซื้อไม่สำเร็จ')),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseScreen(
          purchaseId: _asInt(created!['id']),
          amountSatang:
              _asInt(created!['amount_satang'], fallback: amountSatang),
          qrPayload: _asStr(created!['qr_payload']),
          expiresAt: _asDate(created!['expires_at']),
        ),
      ),
    );

    await _reload();
  }

  // แถบ “ราคา + ปุ่มซื้อ”
  Widget _paidBar({required int postId, required int amountSatang}) {
    final priceBaht = amountSatang / 100.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Text(
            '฿${priceBaht.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: () =>
                _handleBuy(postId: postId, amountSatang: amountSatang),
            child: const Text('ซื้อ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final screens = [
      // ===================== HOME (ฟีด) =====================
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

                final String priceType = (p['price_type'] ?? 'free').toString();
                final bool isPaid = priceType == 'paid';
                final int amountSatang = (p['price_amount_satang'] ?? 0) is int
                    ? p['price_amount_satang'] as int
                    : int.tryParse('${p['price_amount_satang']}') ?? 0;

                final int postId = p['id'] is int
                    ? p['id'] as int
                    : int.parse('${p['id']}');

                final postCard = PostCard(post: p,onDeleted: _reload);

                // โพสต์ฟรี → แสดงการ์ดปกติ
                if (!isPaid) return postCard;

                // โพสต์เสียเงิน → ตรวจ hasAccess ภายใน FutureBuilder
                return FutureBuilder<Map<String, dynamic>>(
                  future: ApiService.getPostDetail(
                    postId: postId,
                    viewerUserId: _userId!,
                  ),
                  builder: (context, detailSnap) {
                    final bool hasAccess =
                        (detailSnap.data?['hasAccess'] == true);

                    // ระหว่างโหลดสิทธิ์ แสดงการ์ดปกติ
                    if (detailSnap.connectionState ==
                        ConnectionState.waiting) {
                      return postCard;
                    }

                    if (hasAccess) {
                      // มีสิทธิ์แล้ว → ครอบป้าย "ซื้อแล้ว"
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          postCard,
                          const SizedBox(height: 8),
                        ],
                      );
                    }

                    // ยังไม่มีสิทธิ์ → แสดงราคา + ปุ่มซื้อ
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        postCard,
                        _paidBar(
                          postId: postId,
                          amountSatang: amountSatang,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          );
        },
      ),

      // ===================== SEARCH =====================
      const SearchScreen(),

      // ===================== ADD =====================
      const Center(child: Text('Add Screen')),

      // ===================== PROFILE =====================
      ProfileScreen(userId: _userId),
    ];

    return Scaffold(
      appBar: (_currentIndex == 3)
          ? null
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
            if (_userId == null) return;
            final changed = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    NewPostScreen(userId: _userId!, username: _username ?? ''),
              ),
            );
            if (changed == true) await _reload();
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
