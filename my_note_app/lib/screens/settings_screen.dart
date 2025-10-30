// lib/screens/settings_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/saved_posts_screen.dart';
import 'package:my_note_app/screens/liked_posts_screen.dart';
import 'package:my_note_app/screens/deleted_posts_screen.dart';
import 'package:my_note_app/screens/purchased_posts_screen.dart';
import 'package:my_note_app/screens/withdraw_screen.dart';

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
                      icon: Icons.receipt_long_outlined,
                      title: 'Purchased',
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
/// WithdrawScreen
/// ======================
