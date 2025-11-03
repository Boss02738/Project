import 'package:flutter/material.dart';
import 'package:my_note_app/api/api_service.dart';
// ⬇️ เพิ่ม import หน้าดูโปรไฟล์
import 'package:my_note_app/screens/profile_screen.dart';

class FriendsListScreen extends StatefulWidget {
  final int userId;
  const FriendsListScreen({super.key, required this.userId});

  @override
  State<FriendsListScreen> createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getFriends(widget.userId);
  }

  ImageProvider _avatarProvider(String? avatarUrl) {
    final avatar = avatarUrl ?? '';
    if (avatar.startsWith('http')) return NetworkImage(avatar);
    if (avatar.isNotEmpty) return NetworkImage('${ApiService.host}$avatar');
    return const AssetImage('assets/default_avatar.png');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เพื่อนของฉัน')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('โหลดไม่สำเร็จ: ${snap.error}'));
          }

          final friends = snap.data ?? const [];
          if (friends.isEmpty) {
            return const Center(child: Text('ยังไม่มีเพื่อน'));
          }

          return ListView.separated(
            itemCount: friends.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final f = friends[i];
              final idUser = (f['id_user'] is int)
                  ? f['id_user'] as int
                  : int.tryParse('${f['id_user']}') ?? 0;
              final name = (f['username'] as String?) ?? 'user#$idUser';
              final bio = (f['bio'] as String?)?.trim() ?? '';

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                leading: CircleAvatar(
                  radius: 28,
                  backgroundImage: _avatarProvider(f['avatar_url'] as String?),
                ),
                title: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: bio.isEmpty
                    ? const SizedBox.shrink()
                    : Text(
                        bio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                // ✅ แตะเพื่อเปิดหน้าโปรไฟล์เพื่อนคนนั้น
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(userId: idUser),
                    ),
                  );
                  // กลับมาแล้วถ้าต้องการรีเฟรชรายการเพื่อน (กรณีสถานะเปลี่ยน)
                  setState(() {
                    _future = ApiService.getFriends(widget.userId);
                  });
                },
              );
            },
          );
        },
      ),
    );
  }
}
