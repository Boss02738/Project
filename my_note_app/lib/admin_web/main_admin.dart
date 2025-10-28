// lib/admin_web/main_admin.dart
import 'package:flutter/material.dart';
import 'pending_slips_page.dart';

void main() {
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoteCoLab Admin',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1F66A0),
        useMaterial3: true,
      ),
      home: const PendingSlipsPage(),
    );
  }
}
