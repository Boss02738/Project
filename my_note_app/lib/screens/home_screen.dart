import 'package:flutter/material.dart';
import 'package:my_note_app/screens/NewPost.dart';

class homescreen extends StatefulWidget {
  const homescreen({super.key});

  @override
  State<homescreen> createState() => _CmState();
}

class _CmState extends State<homescreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    Center(child: Text('Home Screen')),
    Center(child: Text('Search Screen')),
    Center(child: Text('Add Screen')),
    Center(child: Text('Profile Screen')),
  ];

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Note app')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'สวัสดี! ยินดีต้อนรับเข้าสู่ Note App',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: _screens[_currentIndex]),
        ],
      ),
      // ...existing code...
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color.fromARGB(255, 31, 102, 160),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) async {
          if (index == 2) {
            // ไปหน้า NewPostScreen แล้วรอผลลัพธ์
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NewPostScreen(
                  userId: 1, // 🔹 mock ไว้ก่อน
                  username: "test", // 🔹 mock username
                ),
              ),
            );
            // TODO: ถ้าต้องการ refresh หรือเพิ่มโพสต์ใหม่ใน Home ให้จัดการที่นี่
          } else {
            setState(() {
              _currentIndex = index;
            });
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
      // ...existing code...
    );
  }
}
