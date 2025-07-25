import 'package:flutter/material.dart';
import 'package:my_note_app/screens/login_screen.dart';
import 'package:my_note_app/screens/register_screen.dart';
import 'package:my_note_app/screens/home_screen.dart';

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
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LoginScreen(), // ใช้ชื่อคลาสที่ถูกต้อง
    );
  }
}


