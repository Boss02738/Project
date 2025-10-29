import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../api/api_service.dart';

class PurchaseScreen extends StatefulWidget {
  final int purchaseId;            // purchases.id (BIGINT)
  final int amountSatang;
  final String qrPayload;
  final DateTime expiresAt;

  const PurchaseScreen({
    super.key,
    required this.purchaseId,
    required this.amountSatang,
    required this.qrPayload,
    required this.expiresAt,
  });

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  late Timer _timer;
  Duration _remain = Duration.zero;
  bool _expired = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _remain = widget.expiresAt.difference(DateTime.now());
    _expired = _remain.isNegative;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final d = widget.expiresAt.difference(DateTime.now());
      setState(() {
        _remain = d;
        _expired = d.isNegative;
      });
      if (_expired) _timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get amountText => '฿${(widget.amountSatang / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final mm = _remain.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = _remain.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(title: const Text('ชำระเงิน')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('ยอดที่ต้องโอน', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(amountText, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    QrImageView(
                      data: widget.qrPayload,
                      size: 220,
                    ),
                    const SizedBox(height: 10),
                    _expired
                        ? const Text('หมดเวลา QR แล้ว', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                        : Text('เวลาที่เหลือ: $mm:$ss', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _expired || _uploading ? null : _pickAndUploadSlip,
              icon: const Icon(Icons.upload),
              label: const Text('อัปโหลดสลิปโอนเงิน'),
            ),
            const SizedBox(height: 8),
            const Text('หลังอัปโหลดสลิปแล้ว กรุณารอแอดมินตรวจสอบ/อนุมัติ', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadSlip() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (image == null) return;

    setState(() => _uploading = true);
    try {
      final uri = Uri.parse('${ApiService.host}/api/purchases/${widget.purchaseId}/slip');
      final req = http.MultipartRequest('POST', uri);
      req.files.add(await http.MultipartFile.fromPath('slip', image.path, filename: 'slip.jpg'));
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['ok'] == true) {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('ส่งสลิปแล้ว'),
              content: const Text('รอแอดมินตรวจสอบและอนุมัติ'),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ตกลง'))],
            ),
          );
        } else {
          _toast('อัปโหลดไม่สำเร็จ');
        }
      } else {
        _toast('อัปโหลดไม่สำเร็จ (${res.statusCode})');
      }
    } catch (e) {
      _toast('ผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
