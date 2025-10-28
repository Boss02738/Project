// lib/admin_web/pending_slips_page.dart
import 'package:flutter/material.dart';
import 'admin_api.dart';

class PendingSlipsPage extends StatefulWidget {
  const PendingSlipsPage({super.key});

  @override
  State<PendingSlipsPage> createState() => _PendingSlipsPageState();
}

class _PendingSlipsPageState extends State<PendingSlipsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = AdminApi.getPendingSlips();
  }

  Future<void> _reload() async {
    setState(() => _future = AdminApi.getPendingSlips());
  }

  String _baht(int satang) => (satang / 100).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin · Pending Slips')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('โหลดข้อมูลล้มเหลว'),
                  const SizedBox(height: 8),
                  Text(
                    snap.error.toString(),
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _reload,
                    child: const Text('ลองใหม่'),
                  ),
                ],
              ),
            );
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inbox_outlined, size: 48),
                  const SizedBox(height: 8),
                  const Text('ไม่มีสลิปรออนุมัติ'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _reload,
                    child: const Text('รีเฟรช'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final it = items[i];
                final slipPath = it['file_path'] as String?;
                final purchaseId = '${it['id']}';
                final title = (it['title'] ?? 'Untitled').toString();
                final buyer = (it['buyer_email'] ?? 'unknown').toString();
                final seller = (it['seller_email'] ?? 'unknown').toString();
                final amountSatang = (it['amount_satang'] ?? 0) as int;
                final status = (it['status'] ?? '').toString();

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // หัวเรื่อง
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            _StatusChip(status: status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Buyer: $buyer'),
                        Text('Seller: $seller'),
                        const SizedBox(height: 8),
                        Text('Amount: ${_baht(amountSatang)} ฿'),

                        const SizedBox(height: 12),
                        if (slipPath != null && slipPath.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              AdminApi.slipUrl(slipPath),
                              height: 220,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey.shade200,
                                height: 220,
                                alignment: Alignment.center,
                                child: const Text('โหลดรูปสลิปไม่ได้'),
                              ),
                            ),
                          ),

                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () async {
                                  await AdminApi.decidePurchase(
                                    purchaseId: purchaseId,
                                    approved: true,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('อนุมัติสำเร็จ'),
                                      ),
                                    );
                                    _reload();
                                  }
                                },
                                icon: const Icon(Icons.check),
                                label: const Text('อนุมัติ'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await AdminApi.decidePurchase(
                                    purchaseId: purchaseId,
                                    approved: false,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('ปฏิเสธแล้ว'),
                                      ),
                                    );
                                    _reload();
                                  }
                                },
                                icon: const Icon(Icons.close),
                                label: const Text('ปฏิเสธ'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color c;
    switch (status) {
      case 'pending':
        c = Colors.orange;
        break;
      case 'slip_uploaded':
        c = Colors.blue;
        break;
      case 'approved':
        c = Colors.green;
        break;
      case 'rejected':
      case 'expired':
        c = Colors.red;
        break;
      default:
        c = Colors.grey;
    }
    return Chip(
      label: Text(status.isEmpty ? '-' : status),
      backgroundColor: c.withOpacity(0.15),
      labelStyle: TextStyle(color: c),
      side: BorderSide(color: c.withOpacity(0.4)),
    );
  }
}
