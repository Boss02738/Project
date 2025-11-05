import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';                     // <- สำหรับกรองตัวเลข
import 'package:shared_preferences/shared_preferences.dart';// <- เอา user_id จาก login
import 'package:image_picker/image_picker.dart';
import 'package:my_note_app/api/api_service.dart';          // แก้ path ให้ตรงโปรเจกต์คุณ
import 'package:my_note_app/screens/home_screen.dart';

class CreateProfileScreen extends StatefulWidget {
  final String username;
  final String email;
  final String? avatarUrl;

  const CreateProfileScreen({
    super.key,
    required this.username,
    required this.email,
    this.avatarUrl,
  });

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _bio = TextEditingController();
  final _phoneCtrl = TextEditingController();               // <- เพิ่มเบอร์โทร

  String? _gender;
  bool _loading = false;

  File? _pickedFile;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _bio.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _pickedFile = File(x.path));
  }

  Future<String?> _uploadIfAny() async {
    if (_pickedFile == null) return null;
    final res = await ApiService.uploadAvatar(email: widget.email, file: _pickedFile!);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['avatar_url'] as String?;
    } else {
      if (!mounted) return null;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ (${res.statusCode})')));
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      // 0) เอา user_id จาก SharedPreferences (ได้ตอน login)
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id'); // ตาราง users.id_user
      if (userId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบ user_id (โปรดล็อกอินใหม่)')),
        );
        setState(() => _loading = false);
        return;
      }

      // 1) อัปโหลดรูปก่อน (ถ้ามี)
      await _uploadIfAny();

      // 2) เซฟ bio/gender (ของเดิม)
      final res = await ApiService.updateProfile(
        email: widget.email,
        bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        gender: _gender,
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      );

      // 3) เซฟเบอร์ PromptPay เพิ่ม (ใหม่)
      final phone = _phoneCtrl.text.trim();
      await ApiService.updatePhoneAndBio(
        userId: userId,
        bio: null,                 // bio อัปเดตไปแล้วด้านบน
        phone: phone.isEmpty ? null : phone,
      );

      if (res.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('บันทึกโปรไฟล์สำเร็จ')));
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const homescreen()));
      } else {
        if (!mounted) return;
        final data = jsonDecode(res.body);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(data['message'] ?? 'บันทึกไม่สำเร็จ')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ImageProvider _avatarProvider() {
    if (_pickedFile != null) return FileImage(_pickedFile!);
    if ((widget.avatarUrl ?? '').isNotEmpty) {
      // ใช้ host จาก ApiService เพื่อไม่ hardcode IP
      return NetworkImage('${ApiService.host}${widget.avatarUrl!}');
    }
    return const AssetImage('assets/default_avatar.png');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CREATE YOUR\nPROFILE',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.1),
                  ),
                  const SizedBox(height: 8),
                  const Text('What would you like me to call you?', style: TextStyle(color: Colors.black54)),

                  const SizedBox(height: 20),
                  Center(
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(radius: 56, backgroundImage: _avatarProvider()),
                        InkWell(
                          onTap: _pickImage,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.indigo,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.edit, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Username readOnly
                        TextFormField(
                          initialValue: widget.username,
                          enabled: false,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                            filled: true,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Bio
                        TextFormField(
                          controller: _bio,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Bio',
                            prefixIcon: Icon(Icons.info_outline),
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                            filled: true,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Phone (PromptPay) — ใหม่
                        // TextFormField(
                        //   controller: _phoneCtrl,
                        //   keyboardType: TextInputType.phone,
                        //   maxLength: 10, // ไทยนิยม 10 หลัก
                        //   inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        //   decoration: const InputDecoration(
                        //     labelText: 'Phone (PromptPay)',
                        //     hintText: 'เช่น 0812345678',
                        //     counterText: '',
                        //     prefixIcon: Icon(Icons.phone_android),
                        //     border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                        //     filled: true,
                        //   ),
                        //   validator: (v) {
                        //     final s = (v ?? '').trim();
                        //     if (s.isEmpty) return null;                // ไม่บังคับกรอก
                        //     if (s.length < 9 || s.length > 10) return 'กรุณากรอกเบอร์ 9–10 หลัก';
                        //     return null;
                        //   },
                        // ),
                        // const SizedBox(height: 12),

                        // Gender
                        DropdownButtonFormField<String>(
                          value: _gender,
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            prefixIcon: Icon(Icons.wc_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                            filled: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'male', child: Text('male')),
                            DropdownMenuItem(value: 'female', child: Text('female')),
                            DropdownMenuItem(value: 'other', child: Text('other')),
                          ],
                          onChanged: (v) => setState(() => _gender = v),
                          validator: (v) => (v == null || v.isEmpty) ? 'เลือกเพศ' : null,
                        ),
                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _save,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text(_loading ? 'Saving...' : 'Confirm'),
                          ),
                        ),
                      ],
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
