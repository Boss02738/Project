import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'purchase_slip_upload_screen.dart';

class PurchaseScreen extends StatefulWidget {
  final int purchaseId; // ใช้ int
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
      if (!mounted) return;
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'ยอดที่ต้องโอน',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        amountText,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // NOTE: ถ้าโปรเจ็กต์คุณใช้เวอร์ชันใหม่ จะมี QrImageView
                      // ถ้าแดงว่าไม่มี QrImageView ให้ใช้ QrImage (ตัวนี้ด้านล่าง)
                      // QrImageView(data: widget.qrPayload, size: 220),
                      QrImageView(
                        data: widget.qrPayload,
                        size: 220,
                        // ไม่จำเป็น แต่กัน edge case ได้:
                        // version: QrVersions.auto,
                      ),

                      const SizedBox(height: 10),
                      _expired
                          ? const Text(
                              'หมดเวลา QR แล้ว',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : Text(
                              'เวลาที่เหลือ: $mm:$ss',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _expired || _uploading ? null : _pickAndUploadSlip,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload),
                label: const Text('อัปโหลดสลิปโอนเงิน'),
              ),
              const SizedBox(height: 8),
              const Text(
                'หลังอัปโหลดสลิปแล้ว กรุณารอแอดมินตรวจสอบ/อนุมัติ',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadSlip() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => PurchaseSlipUploadScreen(
          purchaseId: widget.purchaseId, // ส่งเป็น int
          amountSatang: widget.amountSatang,
          postTitle: 'โพสต์ที่ต้องซื้อ',
        ),
      ),
    );

    if (result == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}