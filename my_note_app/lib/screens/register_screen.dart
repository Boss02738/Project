import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String apiBase = 'http://10.40.150.148:3000/api/auth';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Controllers
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _otp = TextEditingController();

  // Form keys
  final _formStep1Key = GlobalKey<FormState>();
  final _formStep2Key = GlobalKey<FormState>();

  // UI states
  bool otpSent = false;
  bool loading = false;

  // Timer / countdown
  DateTime? _expiresAtServer; // เวลาหมดอายุจาก server (เก็บไว้เผื่อใช้ต่อ)
  DateTime? _serverNow; // เวลา server ตอนออก OTP (เก็บไว้เผื่อใช้ต่อ)
  Timer? _countdownTimer;
  Timer? _resendTimer;
  int _remainingSec = 0; // นับถอยหลัง OTP
  int _resendRemain = 0; // นับถอยหลังปุ่มส่งใหม่

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _otp.dispose();
    _countdownTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  // แปลงวินาทีเป็น mm:ss
  String _mmss(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  void _startTimers({
    required DateTime serverNow,
    required DateTime expiresAt,
    required int resendAfterSec,
  }) {
    // sync เวลาด้วยส่วนต่าง serverNow กับเวลาปัจจุบัน
    final drift = DateTime.now().difference(serverNow);
    final localExpires = expiresAt.subtract(drift);

    _expiresAtServer = expiresAt;
    _serverNow = serverNow;

    setState(() {
      _remainingSec =
          localExpires.difference(DateTime.now()).inSeconds.clamp(0, 999999);
      _resendRemain = resendAfterSec;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remain =
          localExpires.difference(DateTime.now()).inSeconds.clamp(0, 999999);
      if (!mounted) return;
      setState(() => _remainingSec = remain);
      if (remain <= 0) _countdownTimer?.cancel();
    });

    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_resendRemain > 0) {
        setState(() => _resendRemain--);
      } else {
        _resendTimer?.cancel();
      }
    });
  }

  Future<void> _requestOtp() async {
    // เช็คฟอร์ม + confirm password ต้องตรง
    if (!_formStep1Key.currentState!.validate()) return;
    if (_password.text != _confirmPassword.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('รหัสผ่านยืนยันไม่ตรงกัน')),
      );
      return;
    }

    setState(() => loading = true);
    try {
      final res = await http.post(
        Uri.parse('$apiBase/register/request-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _username.text.trim(),
          'email': _email.text.trim(),
          'password': _password.text,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        setState(() => otpSent = true);

        // เริ่มจับเวลา
        _startTimers(
          serverNow: DateTime.parse(data['now']),
          expiresAt: DateTime.parse(data['expiresAt']),
          resendAfterSec: (data['resend_after_sec'] ?? 60) as int,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ส่ง OTP แล้ว กรุณาตรวจอีเมล')),
          );
        }
      } else {
        if (res.statusCode == 429 && data['retry_after_sec'] != null) {
          setState(() => _resendRemain = data['retry_after_sec']);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'ขอ OTP ไม่สำเร็จ')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ติดต่อเซิร์ฟเวอร์ไม่ได้')),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _verifyAndRegister() async {
    if (!_formStep2Key.currentState!.validate()) return;

    setState(() => loading = true);
    try {
      final res = await http.post(
        Uri.parse('$apiBase/register/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _username.text.trim(),
          'email': _email.text.trim(),
          'password': _password.text,
          'otp': _otp.text.trim(),
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('สมัครสำเร็จ')),
          );
          Navigator.of(context).pop(); // หรือไปหน้า Login
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'ยืนยันไม่สำเร็จ')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ติดต่อเซิร์ฟเวอร์ไม่ได้')),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _resendOtp() async {
    if (_resendRemain > 0) return;

    setState(() => loading = true);
    try {
      final res = await http.post(
        Uri.parse('$apiBase/register/resend-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': _email.text.trim()}),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        _startTimers(
          serverNow: DateTime.parse(data['now']),
          expiresAt: DateTime.parse(data['expiresAt']),
          resendAfterSec: (data['resend_after_sec'] ?? 60) as int,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ส่ง OTP ใหม่แล้ว')),
          );
        }
      } else if (res.statusCode == 429) {
        final wait = (data['retry_after_sec'] ?? 60) as int;
        setState(() => _resendRemain = wait);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ขอใหม่ได้ใน ${_mmss(wait)}')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'ขอ OTP ใหม่ไม่สำเร็จ')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ติดต่อเซิร์ฟเวอร์ไม่ได้')),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  InputDecoration _input(String label, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ให้เว้นซ้าย/ขวาแบบเดียวกับหน้า Login (เช่น 24)
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // ให้หัวเรื่องชิดซ้าย
                children: [
                  // ขยับหัวเรื่องให้เว้นซ้ายพอดีกับ Login
                  const Padding(
                    padding: EdgeInsets.only(left: 0),
                    child: Text(
                      'CREATE YOUR ACCOUNT',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // STEP 1
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surface,
                   
                      child: Form(
                        key: _formStep1Key,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'ขั้นตอนที่ 1: กรอกข้อมูล',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _username,
                              decoration: _input('Username'),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'กรอก Username'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _input('Email (@ku.th เท่านั้น)'),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'กรอก Email @ku.th';
                                }
                                final email = v.trim();
                                final pattern = RegExp(r'^[^@]+@ku\.th$');
                                if (!pattern.hasMatch(email)) {
                                  return 'อนุญาตเฉพาะอีเมล @ku.th เท่านั้น';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _password,
                              obscureText: true,
                              decoration: _input('Password'),
                              validator: (v) => (v == null || v.length < 6)
                                  ? 'รหัสผ่านอย่างน้อย 6 ตัวอักษร'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirmPassword,
                              obscureText: true,
                              decoration: _input('Confirm Password'),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'ยืนยันรหัสผ่าน';
                                }
                                if (v != _password.text) {
                                  return 'รหัสผ่านยืนยันไม่ตรงกัน';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: loading ? null : _requestOtp,
                              icon: const Icon(Icons.email_outlined),
                              label: Text(
                                loading ? 'กำลังส่ง...' : 'ส่ง OTP ไปที่อีเมล',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ),
                  const SizedBox(height: 8),

                  // STEP 2
                  if (otpSent)
                    Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surface,
                        child: Form(
                          key: _formStep2Key,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'ขั้นตอนที่ 2: ยืนยัน OTP',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _otp,
                                keyboardType: TextInputType.number,
                                decoration: _input('OTP 6 หลัก'),
                                validator: (v) =>
                                    (v == null || v.trim().length != 6)
                                        ? 'กรอก OTP 6 หลัก'
                                        : null,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _remainingSec > 0
                                        ? 'รหัสหมดอายุใน ${_mmss(_remainingSec)}'
                                        : 'รหัสหมดอายุแล้ว กรุณากดส่งใหม่',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  TextButton.icon(
                                    onPressed: (_resendRemain > 0 || loading)
                                        ? null
                                        : _resendOtp,
                                    icon: const Icon(Icons.refresh),
                                    label: Text(
                                      _resendRemain > 0
                                          ? 'ส่งใหม่ได้ใน ${_mmss(_resendRemain)}'
                                          : 'ส่ง OTP ใหม่',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: loading ? null : _verifyAndRegister,
                                icon:
                                    const Icon(Icons.check_circle_outline),
                                label: Text(
                                  loading
                                      ? 'กำลังยืนยัน...'
                                      : 'ยืนยันและสมัคร',
                                ),
                              ),
                            ],
                          ),
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
