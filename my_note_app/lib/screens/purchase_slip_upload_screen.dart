import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_note_app/api/api_service.dart';

class PurchaseSlipUploadScreen extends StatefulWidget {
  final int purchaseId;            // <-- เปลี่ยนเป็น int
  final int amountSatang;
  final String postTitle;

  const PurchaseSlipUploadScreen({
    Key? key,
    required this.purchaseId,
    required this.amountSatang,
    required this.postTitle,
  }) : super(key: key);

  @override
  State<PurchaseSlipUploadScreen> createState() =>
      _PurchaseSlipUploadScreenState();
}

class _PurchaseSlipUploadScreenState extends State<PurchaseSlipUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedSlipImage;
  bool _isUploading = false;
  bool _autoVerified = false;
  Map<String, dynamic>? _verificationResult;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _checkCurrentStatus();
  }

  Future<void> _checkCurrentStatus() async {
    try {
      // ใช้เมธอดที่มีจริง
      final result = await ApiService.getPurchase(widget.purchaseId);
      final purchase = (result['purchase'] ?? result) as Map<String, dynamic>;
      final status = purchase['status'] as String?;

      if (mounted && status == 'approved') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ การซื้อได้รับการอนุมัติแล้ว! สามารถเข้าถึงโพสต์ได้'),
          ),
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context, true);
        });
      }
    } catch (e) {
      // แค่ log ไว้ ไม่ต้องล้ม UI
      // ignore: avoid_print
      print('Error checking status: $e');
    }
  }

  Future<void> _pickSlipImage() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (file != null) {
        setState(() {
          _selectedSlipImage = File(file.path);
          _uploadError = null;
          _verificationResult = null;
        });
      }
    } catch (e) {
      setState(() {
        _uploadError = 'ไม่สามารถเลือกรูปภาพได้: $e';
      });
    }
  }

  Future<void> _uploadSlip() async {
    if (_selectedSlipImage == null) {
      setState(() {
        _uploadError = 'กรุณาเลือกรูปภาพสลิป';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      final result = await ApiService.uploadPurchaseSlip(
        purchaseId: widget.purchaseId,        // <-- ส่ง int
        slipFile: _selectedSlipImage!,
      );

      if (!mounted) return;

      final autoVerified = (result['auto_verified'] ?? false) as bool;
      final verification = result['verification'];

      setState(() {
        _autoVerified = autoVerified;
        _verificationResult = (verification is Map<String, dynamic>)
            ? verification
            : null;
        _isUploading = false;
      });

      if (autoVerified) {
        _showSuccessDialog();
      } else {
        _showPendingDialog(verification);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadError = 'อัปโหลดสลิปไม่สำเร็จ: $e';
        _isUploading = false;
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('✅ ตรวจสอบสำเร็จ'),
        content: const Text(
          'ระบบได้ตรวจสอบสลิปของคุณแล้ว '
          'และพบว่าจำนวนเงินตรงกับที่ต้องชำระ '
          'การซื้อได้รับการอนุมัติอัตโนมัติแล้ว! '
          'สามารถเข้าถึงโพสต์ได้ทันที',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, true);
            },
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
  }

  void _showPendingDialog(dynamic verification) {
    String? error;
    String? amount;

    if (verification is Map) {
      error = verification['error'] as String?;
      final amt = verification['amount'];
      if (amt is num) {
        amount = '${amt.toStringAsFixed(2)} บาท';
      }
    }

    final message = error == 'amount_mismatch'
        ? 'ระบบตรวจสอบสลิปแล้ว แต่พบว่าจำนวนเงิน ($amount) ไม่ตรงกับที่ต้องชำระ '
            '(${(widget.amountSatang / 100).toStringAsFixed(2)} บาท) '
            'กรุณารอการตรวจสอบจากแอดมิน'
        : 'ระบบไม่สามารถอ่านข้อมูลจากสลิป (${error ?? 'ไม่ทราบสาเหตุ'}) '
            'กรุณารอการตรวจสอบจากแอดมิน';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('⏳ รอการตรวจสอบ'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amountBaht = widget.amountSatang / 100;

    return Scaffold(
      appBar: AppBar(
        title: const Text('อัปโหลดสลิปชำระเงิน'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'รายละเอียดการซื้อ',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _infoRow('โพสต์', widget.postTitle),
                    _infoRow('จำนวนเงิน', '${amountBaht.toStringAsFixed(2)} บาท'),
                    _infoRow('รหัสการซื้อ', widget.purchaseId.toString()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Text('เลือกสลิปธนาคาร',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            if (_selectedSlipImage == null)
              GestureDetector(
                onTap: _isUploading ? null : _pickSlipImage,
                child: Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300, width: 2),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade50,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('แตะเพื่อเลือกสลิป',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _selectedSlipImage!,
                      width: double.infinity,
                      height: 250,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _isUploading ? null : _pickSlipImage,
                    icon: const Icon(Icons.refresh),
                    label: const Text('เลือกรูปใหม่'),
                  ),
                ],
              ),

            const SizedBox(height: 24),

            if (_uploadError != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_uploadError!, style: TextStyle(color: Colors.red.shade700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_selectedSlipImage == null || _isUploading) ? null : _uploadSlip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _isUploading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                        )
                      : const Text('อัปโหลดสลิป'),
                ),
              ),
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ℹ️ วิธีการใช้งาน',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                  const SizedBox(height: 8),
                  Text(
                    '1. ถ่ายภาพหรือเลือกรูปสลิปธนาคารที่แสดงจำนวนเงินและวันที่โอน\n'
                    '2. ตรวจสอบว่ารูปชัดเจน อ่านตัวเลขได้\n'
                    '3. อัปโหลดสลิป\n'
                    '4. ระบบจะตรวจสอบอัตโนมัติ:\n'
                    '   • ถ้าจำนวนตรงกัน → อนุมัติทันที ✅\n'
                    '   • ถ้าจำนวนไม่ตรง → รอแอดมิน ⏳',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800, height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
