import 'package:flutter/material.dart';
import 'package:my_note_app/screens/login_screen.dart';
import 'package:my_note_app/screens/register_screen.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Note App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.red,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color.fromARGB(255, 86, 99, 107),
          foregroundColor: Colors.white,
        ),
      ),
       initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        // เพิ่ม routes อื่น ๆ ตามโปรเจกต์
      },// ใช้ชื่อคลาสที่ถูกต้อง
    );
  }
}


