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
import 'package:my_note_app/screens/login_screen.dart';
import 'package:my_note_app/screens/change_password_screen.dart';

// ✅ นำเข้า ThemeController ที่เราสร้างไว้ใน main.dart
import 'package:my_note_app/main.dart' show ThemeController;

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

  // ---------- UI helpers ----------
  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      default:
        return 'ตามระบบ (System)';
    }
  }

  void _pickTheme(BuildContext context, ThemeMode current) {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                title: const Text('ตามระบบ (System)'),
                value: ThemeMode.system,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) ThemeController.instance.setMode(v);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Light'),
                value: ThemeMode.light,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) ThemeController.instance.setMode(v);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Dark'),
                value: ThemeMode.dark,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) ThemeController.instance.setMode(v);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
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
                final username = (data['username'] ?? 'MeowMath') as String;
                final avatar = (data['avatar_url'] ?? '') as String;

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
                        username,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text('Your profile'),
                    ),
                    const Divider(height: 1),

                    // ✅ Theme (interactive)
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: ThemeController.instance,
                      builder: (_, mode, __) {
                        return _SettingsItem(
                          icon: Icons.brightness_6_outlined,
                          title: 'Theme',
                          // โชว์สถานะธีมปัจจุบัน
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _themeLabel(mode),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () => _pickTheme(context, mode),
                        );
                      },
                    ),

                    _SettingsItem(
                      icon: Icons.bookmark_border,
                      title: 'Saved',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SavedPostsScreen(userId: _userId!),
                        ),
                      ),
                    ),

                    _SettingsItem(
                      icon: Icons.favorite_border,
                      title: 'Likes',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LikedPostsScreen(userId: _userId!),
                        ),
                      ),
                    ),

                    _SettingsItem(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Purchased posts',
                      onTap: () async {
                        final sp = await SharedPreferences.getInstance();
                        final uid = sp.getInt('user_id');

                        if (!context.mounted) return;

                        if (uid == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'กรุณาเข้าสู่ระบบก่อนดูโพสต์ที่ซื้อ',
                              ),
                            ),
                          );
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PurchasedPostsScreen(userId: uid),
                          ),
                        );
                      },
                    ),

                    _SettingsItem(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Withdraw',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WithdrawScreen(userId: _userId!),
                        ),
                      ),
                    ),

                    _SettingsItem(
                      icon: Icons.delete_outline,
                      title: 'Deleted',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeletedPostsScreen(userId: _userId!),
                        ),
                      ),
                    ),

                    _SettingsItem(
                      icon: Icons.lock_outline,
                      title: 'Change Password',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ChangePasswordScreen(userId: _userId!),
                          ),
                        );
                      },
                    ),

                    _SettingsItem(
                      icon: Icons.logout,
                      title: 'Log Out',
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: const Text('ยืนยันการออกจากระบบ'),
                              content: const Text(
                                'คุณแน่ใจหรือไม่ว่าต้องการออกจากระบบ?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('ยกเลิก'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('ออกจากระบบ'),
                                ),
                              ],
                            );
                          },
                        );

                        if (confirm != true) return;

                        final sp = await SharedPreferences.getInstance();
                        await sp.clear();

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ออกจากระบบเรียบร้อยแล้ว'),
                            ),
                          );

                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/login',
                            (route) => false,
                          );
                        }
                      },
                    ),
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
  final Widget? trailing;

  const _SettingsItem({
    required this.icon,
    required this.title,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
