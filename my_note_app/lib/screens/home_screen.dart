// import 'package:flutter/material.dart';
// import 'package:my_note_app/screens/NewPost.dart';

// class homescreen extends StatefulWidget {
//   const homescreen({super.key});

//   @override
//   State<homescreen> createState() => _CmState();
// }

// class _CmState extends State<homescreen> {
//   int _currentIndex = 0;

//   final List<Widget> _screens = [
//     Center(child: Text('Home Screen')),
//     Center(child: Text('Search Screen')),
//     Center(child: Text('Add Screen')),
//     Center(child: Text('Profile Screen')),
//   ];

//   @override
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Note app')),
//       body: Column(
//         children: [
//           const Padding(
//             padding: EdgeInsets.all(16.0),
//             child: Text(
//               'สวัสดี! ยินดีต้อนรับเข้าสู่ Note App',
//               style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//             ),
//           ),
//           Expanded(child: _screens[_currentIndex]),
//         ],
//       ),
//       // ...existing code...
//       bottomNavigationBar: BottomNavigationBar(
//         currentIndex: _currentIndex,
//         selectedItemColor: const Color.fromARGB(255, 31, 102, 160),
//         unselectedItemColor: Colors.grey,
//         type: BottomNavigationBarType.fixed,
//         onTap: (index) async {
//           if (index == 2) {
//             // ไปหน้า NewPostScreen แล้วรอผลลัพธ์
//             final result = await Navigator.push(
//               context,
//               MaterialPageRoute(
//                 builder: (context) => NewPostScreen(
//                   userId: 1, // 🔹 mock ไว้ก่อน
//                   username: "test", // 🔹 mock username
//                 ),
//               ),
//             );
//             // TODO: ถ้าต้องการ refresh หรือเพิ่มโพสต์ใหม่ใน Home ให้จัดการที่นี่
//           } else {
//             setState(() {
//               _currentIndex = index;
//             });
//           }
//         },
//         items: const [
//           BottomNavigationBarItem(
//             icon: Icon(Icons.home_outlined),
//             label: 'Home',
//           ),
//           BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
//           BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Add'),
//           BottomNavigationBarItem(
//             icon: Icon(Icons.account_circle_outlined),
//             label: 'Profile',
//           ),
//         ],
//       ),
//       // ...existing code...
//     );
//   }
// }
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/NewPost.dart';
import 'package:my_note_app/screens/login_screen.dart';


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

  StreamSubscription<void>? _feedSub; // ✅ subscribe event bus

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

    // ✅ listen event bus เพื่อรีโหลดอัตโนมัติ
  }

  Future<void> _reload() async {
    setState(() => _futureFeed = ApiService.getFeed());
  }

  @override
  void dispose() {
    _feedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUser) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
                  Center(child: Text('โหลดฟีดไม่สำเร็จ — ลองดึงเพื่อรีโหลด')),
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
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: feed.length,
              itemBuilder: (_, i) {
                final p = feed[i];
                final avatar = (p['avatar_url'] as String?) ?? '';
                final img    = (p['image_url']  as String?) ?? '';
                final file   = (p['file_url']   as String?) ?? '';
                final name   = p['username'] as String? ?? '';
                final text   = p['text'] as String? ?? '';
                final subject= p['subject'] as String? ?? '';
                final year   = p['year_label'] as String? ?? '';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundImage: avatar.isNotEmpty
                          ? NetworkImage('${ApiService.host}$avatar')
                          : const AssetImage('assets/default_avatar.png')
                              as ImageProvider,
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(subject.isNotEmpty ? subject : 'No subject'),
                      trailing: const Icon(Icons.more_horiz),
                    ),
                    if (img.isNotEmpty)
                      AspectRatio(
                        aspectRatio: 16/9,
                        child: Image.network(
                          '${ApiService.host}$img',
                          fit: BoxFit.cover,
                        ),
                      ),
                    if (file.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.insert_drive_file, size: 18),
                            const SizedBox(width: 8),
                            Flexible(child: Text(file.split('/').last, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    if (text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(text),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(year, style: const TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                  ],
                );
              },
            ),
          );
        },
      ),
      const Center(child: Text('Search Screen')),
      const Center(child: Text('Add Screen')),
      const Center(child: Text('Profile Screen')),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Note app'),
        automaticallyImplyLeading: false, // ❌ เอาลูกศรออก
),
      
      body: Column(
        children: [
          Expanded(child: screens[_currentIndex]),
        ],
      ),
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
            // ไม่ต้องทำอะไรต่อ — FeedBus จะเป็นคนสั่ง reload เอง
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
