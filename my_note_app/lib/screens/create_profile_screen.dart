import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:my_note_app/api/api_service.dart'; // แก้ path ให้ตรงโปรเจกต์คุณ
import 'package:my_note_app/screens/home_screen.dart';

class CreateProfileScreen extends StatefulWidget {
  final String username;
  final String email;
  final String? avatarUrl; // รับมาไว้แสดงถ้ามี
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
  String? _gender;
  bool _loading = false;

  File? _pickedFile; // สำหรับแสดง preview ก่อนอัปโหลด
  final _picker = ImagePicker();

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) {
      setState(() => _pickedFile = File(x.path));
    }
  }

  Future<String?> _uploadIfAny() async {
    if (_pickedFile == null) return null;
    final resp = await ApiService.uploadAvatar(email: widget.email, file: _pickedFile!);
    final body = await http.Response.fromStream(resp);
    if (body.statusCode == 200) {
      final data = jsonDecode(body.body);
      return data['avatar_url'] as String?;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ')),
      );
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      // 1) อัปโหลดรูปก่อน (ถ้ามีเลือก)
      await _uploadIfAny();

      // 2) เซฟ bio/gender และ mark profile_completed
      final res = await ApiService.updateProfile(
        email: widget.email,
        bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        gender: _gender,
      );
      final data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกโปรไฟล์สำเร็จ')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const homescreen()),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'บันทึกไม่สำเร็จ')),
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

  ImageProvider _avatarProvider() {
    if (_pickedFile != null) return FileImage(_pickedFile!);
    if ((widget.avatarUrl ?? '').isNotEmpty) {
      // เสิร์ฟจาก backend เช่น /uploads/avatars/xxx.png
      return NetworkImage('http://10.40.150.148:3000${widget.avatarUrl!}');
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
                  const Text('CREATE YOUR\nPROFILE',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.1)),
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
                        )
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
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                            filled: true,
                          ),
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: _bio,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Bio',
                            prefixIcon: Icon(Icons.info_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                            filled: true,
                          ),
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          value: _gender,
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            prefixIcon: Icon(Icons.wc_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
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