import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:my_note_app/api/api_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _pass1 = TextEditingController();
  final _pass2 = TextEditingController();

  final _formKeyEmail = GlobalKey<FormState>();
  final _formKeyReset = GlobalKey<FormState>();

  int _step = 0;
  bool _loading = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _email.dispose();
    _otp.dispose();
    _pass1.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    if (!_formKeyEmail.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final uri = Uri.parse('${ApiService.host}/api/auth/password/request-otp');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': _email.text.trim()}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        _toast('ส่ง OTP ไปที่อีเมลแล้ว');
        setState(() {
          _step = 1;
          _resendCooldown = (data['resend_after_sec'] ?? 60) as int;
        });
        _startCooldown();
      } else {
        _toast(data['message'] ?? 'ขอ OTP ไม่สำเร็จ');
      }
    } catch (_) {
      _toast('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendOtp() async {
    if (_resendCooldown > 0 || _loading) return;
    setState(() => _loading = true);
    try {
      final uri = Uri.parse('${ApiService.host}/api/auth/password/request-otp');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': _email.text.trim()}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        _toast('ส่ง OTP ใหม่แล้ว');
        setState(() => _resendCooldown = (data['resend_after_sec'] ?? 60) as int);
        _startCooldown();
      } else {
        _toast(data['message'] ?? 'ส่ง OTP ใหม่ไม่สำเร็จ');
      }
    } catch (_) {
      _toast('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKeyReset.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final uri = Uri.parse('${ApiService.host}/api/auth/password/reset');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _email.text.trim(),
          'otp': _otp.text.trim(),
          'new_password': _pass1.text
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        _toast('เปลี่ยนรหัสผ่านสำเร็จ! ลองเข้าสู่ระบบใหม่ได้เลย');
        if (mounted) Navigator.pop(context);
      } else {
        _toast(data['message'] ?? 'เปลี่ยนรหัสผ่านไม่สำเร็จ');
      }
    } catch (_) {
      _toast('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        t.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _validateEmail(String? v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return 'กรอกอีเมล';
    if (!RegExp(r'^[^@]+@ku\.th$').hasMatch(text)) {
      return 'อนุญาตเฉพาะอีเมล @ku.th';
    }
    return null;
  }

  String? _validateOTP(String? v) {
    final t = (v ?? '').trim();
    if (t.length != 6) return 'กรอก OTP ให้ครบ 6 หลัก';
    if (!RegExp(r'^\d{6}$').hasMatch(t)) return 'OTP ต้องเป็นตัวเลข 6 หลัก';
    return null;
  }

  String? _validatePass1(String? v) {
    final p = v ?? '';
    if (p.length < 6) return 'รหัสผ่านต้องอย่างน้อย 6 ตัวอักษร';
    return null;
  }

  String? _validatePass2(String? v) {
    if (v != _pass1.text) return 'รหัสผ่านทั้งสองช่องไม่ตรงกัน';
    return null;
  }

  double _passwordStrength(String p) {
    int score = 0;
    if (p.length >= 8) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    return (score / 4).clamp(0, 1).toDouble();
  }

  InputDecoration _decor(
    String label, {
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      filled: true,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
    );
  }

  Widget _stepHeader() {
    return Row(
      children: [
        _StepDot(active: _step == 0, number: 1, label: 'ขอรหัส OTP'),
        const Expanded(child: Divider(thickness: 2)),
        _StepDot(active: _step == 1, number: 2, label: 'ยืนยัน & เปลี่ยนรหัส'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF7F9FC), Color(0xFFEFF3F9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          tooltip: 'Back',
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Reset Password',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _stepHeader(),
                    const SizedBox(height: 16),

                    Expanded(
                      child: Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _step == 0 ? _buildStepRequest() : _buildStepVerifyReset(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _step == 0
                          ? 'กรอกอีเมล @ku.th ที่ใช้สมัคร ระบบจะส่ง OTP ไปยังกล่องจดหมายของคุณ'
                          : 'ตรวจสอบอีเมลของคุณ ใส่ OTP ให้ครบ 6 หลัก และตั้งรหัสผ่านใหม่',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepRequest() {
    return Padding(
      key: const ValueKey('step0'),
      padding: const EdgeInsets.all(18),
      child: Form(
        key: _formKeyEmail,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              'ขอรหัส OTP',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'เราจะส่งรหัส OTP สำหรับรีเซ็ตรหัสผ่านไปยังอีเมล @ku.th ของคุณ',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
              decoration: _decor(
                'อีเมล (@ku.th)',
                prefixIcon: const Icon(Icons.email_outlined),
                hint: 'student@ku.th',
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _loading ? null : _requestOtp,
                icon: const Icon(Icons.send),
                label: Text(_loading ? 'กำลังส่ง...' : 'ขอรหัส OTP'),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildStepVerifyReset() {
    final strength = _passwordStrength(_pass1.text);
    return Padding(
      key: const ValueKey('step1'),
      padding: const EdgeInsets.all(18),
      child: Form(
        key: _formKeyReset,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              'ยืนยัน & เปลี่ยนรหัสผ่าน',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _email,
              readOnly: true,
              decoration: _decor('อีเมล', prefixIcon: const Icon(Icons.alternate_email)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _otp,
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              validator: _validateOTP,
              decoration: _decor(
                'OTP (6 หลัก)',
                prefixIcon: const Icon(Icons.pin_outlined),
                suffixIcon: TextButton(
                  onPressed: (_resendCooldown == 0 && !_loading) ? _resendOtp : null,
                  child: Text(_resendCooldown == 0 ? 'ส่งใหม่' : 'ส่งใหม่ใน ${_resendCooldown}s'),
                ),
                hint: 'ใส่รหัสจากอีเมล',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'หากไม่พบอีเมล ให้ตรวจสอบโฟลเดอร์สแปมหรือรอประมาณ 1 นาที',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pass1,
              obscureText: _obscure1,
              onChanged: (_) => setState(() {}),
              validator: _validatePass1,
              decoration: _decor(
                'รหัสผ่านใหม่',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure1 ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure1 = !_obscure1),
                ),
                hint: 'อย่างน้อย 6 ตัวอักษร',
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: strength,
                backgroundColor: Colors.black12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strength < 0.34
                  ? 'ความแข็งแรง: อ่อน'
                  : (strength < 0.67 ? 'ความแข็งแรง: ปานกลาง' : 'ความแข็งแรง: ดีมาก'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pass2,
              obscureText: _obscure2,
              validator: _validatePass2,
              decoration: _decor(
                'ยืนยันรหัสผ่านใหม่',
                prefixIcon: const Icon(Icons.verified_user_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure2 = !_obscure2),
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _loading ? null : _resetPassword,
                icon: const Icon(Icons.lock_reset),
                label: Text(_loading ? 'กำลังเปลี่ยน...' : 'ยืนยันเปลี่ยนรหัส'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool active;
  final int number;
  final String label;
  const _StepDot({required this.active, required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = active ? Theme.of(context).colorScheme.primary : Colors.grey.shade400;
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: color.withOpacity(0.15),
          child: Text(
            '$number',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: active ? Theme.of(context).colorScheme.onSurface : Colors.grey.shade600,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
