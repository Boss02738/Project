import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_note_app/api/api_service.dart';

class WithdrawScreen extends StatefulWidget {
  final int userId; // << ต้องส่งมาจาก Settings
  const WithdrawScreen({super.key, required this.userId});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _formKey = GlobalKey<FormState>();
  final _coinsCtrl = TextEditingController();

  int? _balance;
  bool _loading = true;
  bool _submitting = false;

  XFile? _qrFile;

  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    setState(() => _loading = true);
    try {
      final bal = await _api.getWalletBalance(userId: widget.userId); // << ส่ง userId
      setState(() => _balance = bal);
    } catch (e) {
      setState(() => _balance = null);
      _toast('โหลดยอดเหรียญไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickQr() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file != null && mounted) {
      setState(() => _qrFile = file);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_qrFile == null) {
      _toast('กรุณาเลือกรูป QR ธนาคารก่อน');
      return;
    }

    final coins = int.tryParse(_coinsCtrl.text.trim()) ?? 0;
    if (coins <= 0) {
      _toast('จำนวนเหรียญไม่ถูกต้อง');
      return;
    }
    if (_balance != null && coins > _balance!) {
      _toast('เหรียญไม่พอ (คงเหลือ: $_balance)');
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await _api.createWithdrawal(
        userId: widget.userId,                 // << ส่ง userId
        coins: coins,
        qrFile: File(_qrFile!.path),
      );
      _toast('ส่งคำขอถอนแล้ว (ID: ${result['id'] ?? result['withdrawal']?['id'] ?? '-'})');

      _coinsCtrl.clear();
      setState(() => _qrFile = null);
      await _loadBalance();
    } catch (e) {
      _toast('ส่งคำขอไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openHistory() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _WithdrawHistoryPage(userId: widget.userId), // << ส่ง userId
    ));
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_submitting;

    return Scaffold(
      appBar: AppBar(title: const Text('ถอนเหรียญ')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: ListTile(
                      title: const Text('ยอดเหรียญคงเหลือ'),
                      subtitle: Text(
                        _balance == null ? 'ไม่ทราบ (ลองใหม่ภายหลัง)' : '$_balance เหรียญ',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loadBalance,
                        tooltip: 'รีเฟรชยอด',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _coinsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'จำนวนเหรียญที่ต้องการถอน',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            if (n == null || n <= 0) {
                              return 'กรอกจำนวนเหรียญเป็นตัวเลขมากกว่า 0';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickQr,
                                icon: const Icon(Icons.qr_code_2),
                                label: Text(_qrFile == null ? 'เลือกรูป QR ธนาคาร' : 'เปลี่ยนรูป QR'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_qrFile != null)
                              SizedBox(
                                width: 64,
                                height: 64,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(File(_qrFile!.path), fit: BoxFit.cover),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: canSubmit ? _submit : null,
                            icon: const Icon(Icons.send),
                            label: Text(_submitting ? 'กำลังส่ง...' : 'ยืนยันถอน'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _openHistory,
                          icon: const Icon(Icons.history),
                          label: const Text('ดูประวัติถอนของฉัน'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _WithdrawHistoryPage extends StatefulWidget {
  final int userId;
  const _WithdrawHistoryPage({required this.userId});

  @override
  State<_WithdrawHistoryPage> createState() => _WithdrawHistoryPageState();
}

class _WithdrawHistoryPageState extends State<_WithdrawHistoryPage> {
  late Future<List<Map<String, dynamic>>> _future;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _future = _api.getMyWithdrawals(userId: widget.userId); // << ส่ง userId
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ประวัติถอนเหรียญของฉัน')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('โหลดไม่สำเร็จ: ${snap.error}'));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('ยังไม่มีรายการถอน'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final w = items[i];
              final amountSatang = (w['amount_satang'] ?? 0) as int;
              final amountBaht = (amountSatang / 100).toStringAsFixed(2);
              final status = (w['status'] ?? '').toString();
              final created = (w['created_at'] ?? '').toString();

              return ListTile(
                leading: const Icon(Icons.payments),
                title: Text('฿$amountBaht ($status)'),
                subtitle: Text('coins: ${w['coins']} · $created'),
                trailing: Icon(
                  status == 'paid'
                      ? Icons.check_circle
                      : status == 'rejected'
                          ? Icons.cancel
                          : Icons.hourglass_bottom,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
