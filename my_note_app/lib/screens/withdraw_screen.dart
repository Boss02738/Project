import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_note_app/api/api_service.dart';

class WithdrawScreen extends StatefulWidget {
  final int userId;
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

  double? _feePercent;  
  int? _minCoins;       

  XFile? _qrFile;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _coinsCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getWalletBalance(userId: widget.userId),
        _api.getWithdrawConfig(), 
      ]);

      final bal = results[0] as int;
      final cfg = results[1] as Map<String, dynamic>;

      setState(() {
        _balance = bal;
        _feePercent = (cfg['fee_percent'] as num?)?.toDouble();
        _minCoins  = (cfg['min_coins'] as num?)?.toInt();
      });
    } catch (e) {
      _toast('โหลดข้อมูลไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadBalance() async {
    try {
      final bal = await _api.getWalletBalance(userId: widget.userId);
      setState(() => _balance = bal);
    } catch (e) {
      _toast('โหลดยอดเหรียญไม่สำเร็จ: $e');
    }
  }

  Future<void> _pickQr() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file != null && mounted) setState(() => _qrFile = file);
  }

  int get _amount {
    final n = int.tryParse(_coinsCtrl.text.trim());
    return (n == null || n < 0) ? 0 : n;
  }

  int get _feeCoins {
    final fp = _feePercent ?? 0;
    return ((_amount * fp) / 100.0).floor();
  }

  int get _netCoins {
    final net = _amount - _feeCoins;
    return net < 0 ? 0 : net;
  }

  bool get _canSubmit {
    final minOk = _minCoins == null ? true : _amount >= _minCoins!;
    final balOk = _balance == null ? true : _amount <= _balance!;
    return !_submitting &&
        _amount > 0 &&
        minOk &&
        balOk &&
        _netCoins > 0 &&
        _qrFile != null &&
        _feePercent != null; 
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_feePercent == null || _minCoins == null) {
      _toast('ยังไม่ได้โหลดค่าธรรมเนียมหรือขั้นต่ำ กรุณาลองใหม่');
      return;
    }
    if (_qrFile == null) {
      _toast('กรุณาเลือกรูป QR ธนาคารก่อน');
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await _api.createWithdrawal(
        userId: widget.userId,
        coins: _amount,
        qrFile: File(_qrFile!.path),
      );
      _toast('ส่งคำขอถอนแล้ว (ID: ${result['id'] ?? result['withdrawal']?['id'] ?? '-'})');

      _coinsCtrl.clear();
      setState(() => _qrFile = null);
      await _reloadBalance();
    } catch (e) {
      _toast('ส่งคำขอไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openHistory() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _WithdrawHistoryPage(userId: widget.userId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hintStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).hintColor);

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
                        onPressed: _reloadBalance,
                        tooltip: 'รีเฟรชยอด',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _coinsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'จำนวนเหรียญที่ต้องการถอน',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            if (n == null || n <= 0) return 'กรอกจำนวนเหรียญเป็นตัวเลขมากกว่า 0';
                            if (_minCoins != null && n < _minCoins!) {
                              return 'ขั้นต่ำถอนได้ ${_minCoins!} เหรียญขึ้นไป';
                            }
                            if (_balance != null && n > _balance!) {
                              return 'เหรียญไม่พอ (คงเหลือ: $_balance)';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 8),

                        // ข้อความจาง ๆ แสดงค่าหัก + สุทธิ
                        Text(
                          (_feePercent == null)
                              ? 'กำลังโหลดค่าธรรมเนียม…'
                              : 'แอปจะหัก ${_feePercent!.toStringAsFixed(0)}% '
                                '(≈ $_feeCoins เหรียญ) • รับสุทธิ ≈ $_netCoins เหรียญ'
                                '${_minCoins != null ? ' • ขั้นต่ำ ${_minCoins} เหรียญ' : ''}',
                          style: hintStyle,
                        ),
                        Text(
                          (_feePercent == null)
                              ? ''
                              : 'โปรดตรวจสอบ QR code ว่าถูกต้องจะใช้เวลาทำการประมาณ 3 วัน',
                          style: hintStyle,
                        ),

                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _submitting ? null : _pickQr,
                            icon: const Icon(Icons.qr_code_2),
                            label: Text(_qrFile == null ? 'แนบ/เปลี่ยนรูป QR' : 'เปลี่ยนรูป QR'),
                          ),
                        ),

                        if (_qrFile != null) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_qrFile!.path),
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _canSubmit ? _submit : null,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                            label: Text(_submitting ? 'กำลังส่ง...' : 'ยืนยันถอน'),
                          ),
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
    _future = _api.getMyWithdrawals(userId: widget.userId);
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