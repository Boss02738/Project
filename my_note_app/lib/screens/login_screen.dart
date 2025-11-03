import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/register_screen.dart';
import 'package:my_note_app/screens/home_screen.dart';
import 'package:my_note_app/screens/create_profile_screen.dart';
import 'package:my_note_app/screens/reset_password_screen.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  InputDecoration _input(String label, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      prefixIcon: label.toLowerCase().contains('email')
          ? const Icon(Icons.email, color: Color.fromARGB(255, 122, 122, 122))
          : const Icon(Icons.lock, color: Color.fromARGB(255, 122, 122, 122)),
      suffixIcon: suffix,
      filled: true,
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final email = emailController.text.trim();
    final password = passwordController.text;

    setState(() => _loading = true);
    try {
      final resp = await ApiService.login(email, password);
      final data = jsonDecode(resp.body);

      if (resp.statusCode == 200) {
        final user = data['user'] as Map<String, dynamic>;
        final needProfile = data['needProfile'] == true;

        // เก็บ user ไว้ใช้ทั่วแอป
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', user['id'] as int);
        await prefs.setString('username', user['username'] as String);
        await prefs.setString('email', user['email'] as String);
        if (user['avatar_url'] != null) {
          await prefs.setString('avatar_url', user['avatar_url'] as String);
        }

        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('เข้าสู่ระบบสำเร็จ')));

        if (needProfile) {
          // ครั้งแรกหลังสมัคร → ไปสร้างโปรไฟล์
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => CreateProfileScreen(
                username: user['username'] as String,
                email: user['email'] as String,
                avatarUrl: user['avatar_url'] as String?,
              ),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const homescreen()),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'เข้าสู่ระบบไม่สำเร็จ')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        // ให้ขยับข้อความ/ฟอร์มให้ balance กับหน้า Register
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'LOG IN TO YOUR ACCOUNT',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 28),

                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _input('Email (@ku.th เท่านั้น)'),
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) return 'กรอกอีเมล';
                            if (!RegExp(r'^[^@]+@ku\.th$').hasMatch(text)) {
                              return 'อนุญาตเฉพาะอีเมล @ku.th';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: passwordController,
                          obscureText: _obscure,
                          decoration: _input(
                            'Password',
                            suffix: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'กรอกรหัสผ่าน' : null,
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ResetPasswordScreen(),
                              ),
                            );
                          },
                          child: const Text('Forget the password?'),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _handleLogin,
                            child: Text(_loading ? 'Signing in...' : 'Sign in'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: const Text('Don’t have an account? Sign up'),
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
