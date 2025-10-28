import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_note_app/api/api_service.dart';

class EditProfileScreen extends StatefulWidget {
  final int userId;
  final String initialUsername;
  final String initialBio;
  final String initialAvatar;

  const EditProfileScreen({
    super.key,
    required this.userId,
    required this.initialUsername,
    required this.initialBio,
    required this.initialAvatar,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  bool _saving = false;
  File? _pickedImageFile;
  late String _avatarPathFromDb;

  @override
  void initState() {
    super.initState();
    _usernameCtrl.text = widget.initialUsername;
    _bioCtrl.text = widget.initialBio;
    _avatarPathFromDb = widget.initialAvatar;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked != null) {
      setState(() => _pickedImageFile = File(picked.path));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      String? newAvatarPath;

      // ✅ ถ้ามีเลือกรูปใหม่
      if (_pickedImageFile != null) {
        newAvatarPath = await ApiService.uploadAvatarById(
          userId: widget.userId,
          file: _pickedImageFile!,
        );
      }

      // ✅ อัปเดตข้อมูลโปรไฟล์ (username / bio)
      await ApiService.updateProfileById(
        userId: widget.userId,
        username: _usernameCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกโปรไฟล์เรียบร้อย')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกล้มเหลว: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarProvider = _pickedImageFile != null
        ? FileImage(_pickedImageFile!)
        : (_avatarPathFromDb.isNotEmpty
            ? NetworkImage('${ApiService.host}${_avatarPathFromDb}')
            : const AssetImage('assets/default_avatar.png')) as ImageProvider;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Header username
                Text(
                  _usernameCtrl.text.isEmpty ? 'Your Profile' : _usernameCtrl.text,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // รูปโปรไฟล์
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 56,
                      backgroundImage: avatarProvider,
                    ),
                    InkWell(
                      onTap: _pickImage,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.edit, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                const Text('ข้อมูลส่วนตัว', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),

                // Username
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'กรอก username' : null,
                ),
                const SizedBox(height: 12),

                // Bio
                TextFormField(
                  controller: _bioCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: 140,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('บันทึก'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
