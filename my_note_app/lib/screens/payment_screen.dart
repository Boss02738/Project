// lib/screens/payment_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_service.dart';

class PaymentScreen extends StatefulWidget {
  final int postId;
  final int buyerId;

  const PaymentScreen({
    super.key,
    required this.postId,
    required this.buyerId,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Map<String, dynamic>? purchase;   // ออเดอร์จาก server
  String? qrDataUrl;                // data:image/png;base64,...
  DateTime? expiresAt;              // เวลาหมดอายุ
  Duration remaining = Duration.zero;
  Timer? timer;
  bool loading = true;
  bool uploading = false;

  @override
  void initState() {
    super.initState();
    _createPurchase();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  // ---------- API ----------

  Future<void> _createPurchase() async {
    setState(() => loading = true);
    try {
      final resp = await ApiService.startPurchase(
        postId: widget.postId,
        buyerId: widget.buyerId,
      );

      final p = resp['purchase'] as Map<String, dynamic>?;
      final q1 = resp['qrDataUrl'];
      final q2 = resp['qrPngDataUrl']; // กันโค้ดเก่า
      final qr = (q1 ?? q2) as String?;

      if (p == null || qr == null) {
        throw Exception('Invalid server response');
      }

      final iso = p['expires_at'] as String?;
      DateTime? exp;
      if (iso != null) {
        exp = DateTime.tryParse(iso)?.toLocal();
      }

      setState(() {
        purchase = p;
        qrDataUrl = qr;
        expiresAt = exp;
        loading = false;
      });

      _startTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('สร้างคำสั่งซื้อไม่สำเร็จ: $e')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _refreshPurchase() async {
    if (purchase == null) return;
    try {
      final id = purchase!['id'] as String;
      final r = await ApiService.getPurchase(id);
      final p = r['purchase'] as Map<String, dynamic>?;
      if (p == null) return;
      setState(() {
        purchase = p;
        final iso = p['expires_at'] as String?;
        expiresAt = iso != null ? DateTime.tryParse(iso)?.toLocal() : null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('โหลดสถานะไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _uploadSlip() async {
    if (purchase == null) return;
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;

    setState(() => uploading = true);
    try {
      final id = purchase!['id'] as String;
      await ApiService.uploadPurchaseSlip(
        purchaseId: id,
        slipFile: File(img.path),
      );
      await _refreshPurchase();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปโหลดสลิปล้มเหลว: $e')),
      );
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  // ---------- Timer ----------
  void _startTimer() {
    timer?.cancel();
    if (expiresAt == null) return;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final diff = expiresAt!.difference(DateTime.now());
      setState(() => remaining = diff.isNegative ? Duration.zero : diff);

      // ถ้าหมดเวลา -> รีเฟรชสถานะสักครั้ง
      if (diff.isNegative) {
        timer?.cancel();
        _refreshPurchase();
      }
    });
  }

  // ---------- UI helpers ----------
  String _formatRemain(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    return hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
    }

  Widget _statusChip(String? status) {
    final s = (status ?? '').toLowerCase();
    final cs = Theme.of(context).colorScheme;

    Color bg;
    Color fg;
    switch (s) {
      case 'approved':
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
        break;
      case 'slip_uploaded':
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      case 'expired':
      case 'rejected':
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        break;
      default: // pending
        bg = cs.surfaceContainerHighest.withOpacity(0.6);
        fg = cs.onSurface;
    }

    return Chip(
      label: Text(s.isEmpty ? '-' : s),
      backgroundColor: bg,
      labelStyle: TextStyle(color: fg),
      side: BorderSide(color: fg.withOpacity(0.35)),
    );
  }

  // ---------- BUILD ----------
  @override
  Widget build(BuildContext context) {
    final status = (purchase?['status'] as String?)?.toLowerCase() ?? 'pending';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ชำระเงิน'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshPurchase,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      const Text('สถานะ: ', style: TextStyle(fontSize: 16)),
                      _statusChip(status),
                      const Spacer(),
                      IconButton(
                        onPressed: _refreshPurchase,
                        tooltip: 'รีเฟรช',
                        icon: const Icon(Icons.refresh),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (expiresAt != null && status == 'pending') ...[
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined),
                        const SizedBox(width: 8),
                        Text('เวลาที่เหลือ: ${_formatRemain(remaining)}'),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // QR (เฉพาะตอนรอชำระ)
                  if (qrDataUrl != null && status == 'pending') ...[
                    Center(
                      child: Image.memory(
                        ApiService.dataUrlToBytes(qrDataUrl!),
                        height: 240,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'สแกน QR เพื่อชำระเงิน (PromptPay)',
                      textAlign: TextAlign.center,
                    ),
                  ],

                  // ปุ่มอัปโหลดสลิป: ให้กดได้ตอน pending หรือ slip_uploaded (เผื่ออัปโหลดใหม่)
                  if (status == 'pending' || status == 'slip_uploaded') ...[
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: uploading ? null : _uploadSlip,
                      icon: uploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload),
                      label: Text(
                        uploading ? 'กำลังอัปโหลด...' : 'อัปโหลดสลิปโอนเงิน',
                      ),
                    ),
                  ],

                  if (status == 'approved') ...[
                    const SizedBox(height: 24),
                    const Icon(Icons.verified, color: Colors.green, size: 42),
                    const SizedBox(height: 8),
                    const Text(
                      'ชำระเงินสำเร็จแล้ว • โพสต์นี้จะเข้าบัญชีของคุณ',
                      textAlign: TextAlign.center,
                    ),
                  ],

                  if (status == 'expired') ...[
                    const SizedBox(height: 24),
                    const Icon(Icons.hourglass_disabled, color: Colors.red),
                    const SizedBox(height: 8),
                    const Text(
                      'คำสั่งซื้อหมดเวลาแล้ว • สร้างใหม่อีกครั้ง',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
