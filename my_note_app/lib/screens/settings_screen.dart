// lib/screens/settings_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/saved_posts_screen.dart';
import 'package:my_note_app/screens/liked_posts_screen.dart';
import 'package:my_note_app/screens/deleted_posts_screen.dart';
import 'package:my_note_app/screens/purchased_posts_feed_screen.dart';
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int? _userId;
  Future<Map<String, dynamic>>? _futureProfile;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final sp = await SharedPreferences.getInstance();
    final uid = sp.getInt('user_id');
    setState(() {
      _userId = uid;
      if (uid != null) {
        _futureProfile = ApiService.getUserProfile(uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _userId == null
          ? const Center(child: Text('กรุณาเข้าสู่ระบบ'))
          : FutureBuilder<Map<String, dynamic>>(
              future: _futureProfile,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError || !snap.hasData) {
                  return const Center(child: Text('โหลดโปรไฟล์ไม่สำเร็จ'));
                }

                final data = snap.data!;
                final username = (data['username'] as String?) ?? '';
                final avatar = (data['avatar_url'] as String?) ?? '';

                return ListView(
                  children: [
                    // Header
                    ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundImage: avatar.isNotEmpty
                            ? NetworkImage('${ApiService.host}$avatar')
                            : const AssetImage('assets/default_avatar.png')
                                  as ImageProvider,
                      ),
                      title: Text(
                        username.isEmpty ? 'MeowMath' : username,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      title: Text(
                        username.isEmpty ? 'MeowMath' : username,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text('Your profile'),
                    ),
                    const Divider(height: 1),

                    // Theme (placeholder)
                    const _SettingsItem(
                      icon: Icons.brightness_6_outlined,
                      title: 'Theme',
                    ),

                    // Saved
                    _SettingsItem(
                      icon: Icons.bookmark_border,
                      title: 'Saved',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SavedPostsScreen(userId: _userId!),
                          ),
                        );
                      },
                    ),

                    // Likes
                    _SettingsItem(
                      icon: Icons.favorite_border,
                      title: 'Likes',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LikedPostsScreen(userId: _userId!),
                          ),
                        );
                      },
                    ),

                    // Purchased posts (ใหม่)
                    _SettingsItem(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Purchased posts',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PurchasedPostsScreen(userId: _userId!),
                          ),
                        );
                      },
                    ),

                    // Withdraw (ใหม่)
                    _SettingsItem(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Withdraw',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WithdrawScreen(userId: _userId!),
                          ),
                        );
                      },
                    ),

                    // Deleted (placeholder)
                     _SettingsItem(
                      icon: Icons.delete_outline,
                      title: 'Deleted',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                DeletedPostsScreen(userId: _userId!),
                          ),
                        );
                      },
                    ),

                    // Log out (placeholder)
                    const _SettingsItem(icon: Icons.logout, title: 'Log Out'),
                  ],
                );
              },
            ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  const _SettingsItem({required this.icon, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// ======================
/// PurchasedPostsScreen
/// ======================
class PurchasedPostsScreen extends StatefulWidget {
  final int userId;
  const PurchasedPostsScreen({super.key, required this.userId});

  @override
  State<PurchasedPostsScreen> createState() => _PurchasedPostsScreenState();
}

class _PurchasedPostsScreenState extends State<PurchasedPostsScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchPurchased();
  }

  Future<List<dynamic>> _fetchPurchased() async {
    final uri = Uri.parse(
        '${ApiService.host}/api/users/${widget.userId}/purchased-posts');
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as List<dynamic>);
    }
    throw Exception('โหลดไม่ได้ (${res.statusCode})');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchased posts')),
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
            return const Center(child: Text('ยังไม่มีโพสต์ที่ซื้อ'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final p = items[i] as Map<String, dynamic>;
              final priceSatang = (p['price_amount_satang'] ?? 0) as int;
              return ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                tileColor: Theme.of(context).colorScheme.surface,
                title: Text(
                  (p['text'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'ซื้อเมื่อ: ${(p['granted_at'] ?? '').toString()} • ราคา ฿${(priceSatang / 100).toStringAsFixed(2)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: เปิดดูโพสต์จริง/เอกสารจริงของคุณ
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// ======================
/// WithdrawScreen
/// ======================
class WithdrawScreen extends StatefulWidget {
  final int userId;
  const WithdrawScreen({super.key, required this.userId});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _amountCtrl = TextEditingController(); // ป้อนเป็น "สตางค์"
  final _mobileCtrl = TextEditingController(); // PromptPay (มือถือ)
  bool _loading = false;

  int? _coinBalanceSatang;
  List<dynamic> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    try {
      final uri = Uri.parse(
          '${ApiService.host}/api/wallet/summary?user_id=${widget.userId}');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _coinBalanceSatang = data['coin_balance_satang'] as int? ?? 0;
          _transactions = data['transactions'] as List<dynamic>? ?? [];
        });
      } else {
        _toast('โหลดสรุปกระเป๋าไม่สำเร็จ (${res.statusCode})');
      }
    } catch (e) {
      _toast('ผิดพลาด: $e');
    }
  }

  Future<void> _submitWithdraw() async {
    final amt = int.tryParse(_amountCtrl.text.trim());
    final mobile = _mobileCtrl.text.trim();
    if (amt == null || amt <= 0 || mobile.isEmpty) {
      _toast('กรอกข้อมูลให้ถูกต้อง');
      return;
    }
    setState(() => _loading = true);
    try {
      final uri =
          Uri.parse('${ApiService.host}/api/wallet/payout-request');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': widget.userId,
          'amount_satang': amt,
          'promptpay_mobile': mobile,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['ok'] == true) {
          _toast('ส่งคำขอถอนแล้ว (fee ${data['fee_percent']}%)');
          _amountCtrl.clear();
          _mobileCtrl.clear();
          await _loadSummary();
        } else {
          _toast('ส่งคำขอถอนไม่สำเร็จ');
        }
      } else {
        _toast('ผิดพลาด: ${res.statusCode}');
      }
    } catch (e) {
      _toast('ผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balText = _coinBalanceSatang == null
        ? '...'
        : '฿${((_coinBalanceSatang ?? 0) / 100).toStringAsFixed(2)}';

    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ยอดเหรียญที่ถอนได้',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(balText,
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'จำนวนที่ต้องการถอน (สตางค์) เช่น 9900 = ฿99.00',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mobileCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'เบอร์ PromptPay (มือถือ)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _submitWithdraw,
              icon: const Icon(Icons.paid),
              label: _loading
                  ? const Text('กำลังส่งคำขอ...')
                  : const Text('ยืนยันถอนเงิน'),
            ),
            const SizedBox(height: 24),
            Text('ประวัติธุรกรรมล่าสุด',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._transactions.take(10).map((tx) {
              final m = tx as Map<String, dynamic>;
              final amt = (m['amount_satang'] ?? 0).toString();
              return ListTile(
                leading: Icon(
                  (m['type'] == 'credit_purchase')
                      ? Icons.add_circle
                      : Icons.remove_circle,
                ),
                title: Text('${m['type']}  (ยอด: $amt สต.)'),
                subtitle: Text((m['created_at'] ?? '').toString()),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
