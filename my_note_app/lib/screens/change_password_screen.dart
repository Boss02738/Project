import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_note_app/api/api_service.dart';

class ChangePasswordScreen extends StatefulWidget {
  final int userId;
  const ChangePasswordScreen({super.key, required this.userId});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldPass = TextEditingController();
  final _newPass1 = TextEditingController();
  final _newPass2 = TextEditingController();
  bool _loading = false;
  bool _obscureOld = true;
  bool _obscureNew1 = true;
  bool _obscureNew2 = true;

  @override
  void dispose() {
    _oldPass.dispose();
    _newPass1.dispose();
    _newPass2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final oldP = _oldPass.text.trim();
    final n1 = _newPass1.text;
    final n2 = _newPass2.text;

    if (oldP.isEmpty || n1.isEmpty || n2.isEmpty) {
      _toast('กรอกข้อมูลให้ครบ');
      return;
    }
    if (n1.length < 6) {
      _toast('รหัสผ่านใหม่ต้องยาวอย่างน้อย 6 ตัว');
      return;
    }
    if (n1 != n2) {
      _toast('รหัสผ่านใหม่ไม่ตรงกัน');
      return;
    }

    setState(() => _loading = true);
    try {
      final uri = Uri.parse('${ApiService.host}/api/auth/change-password');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': widget.userId,
          'old_password': oldP,
          'new_password': n1,
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        _toast('เปลี่ยนรหัสผ่านสำเร็จ');
        if (mounted) Navigator.pop(context);
      } else {
        _toast(data['message'] ?? 'ไม่สามารถเปลี่ยนรหัสได้');
      }
    } catch (e) {
      _toast('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: _oldPass,
                    obscureText: _obscureOld,
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่านเดิม',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscureOld ? Icons.visibility : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureOld = !_obscureOld),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newPass1,
                    obscureText: _obscureNew1,
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่านใหม่',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureNew1
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureNew1 = !_obscureNew1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newPass2,
                    obscureText: _obscureNew2,
                    decoration: InputDecoration(
                      labelText: 'ยืนยันรหัสผ่านใหม่',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureNew2
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureNew2 = !_obscureNew2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: const Icon(Icons.lock_reset),
                      label:
                          Text(_loading ? 'กำลังเปลี่ยน...' : 'ยืนยันเปลี่ยนรหัสผ่าน'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
