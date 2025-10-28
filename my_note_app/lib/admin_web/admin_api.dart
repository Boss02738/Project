// lib/admin_web/admin_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Admin API (เว็บอย่างเดียว) — ไม่ใช้ dart:io
class AdminApi {
  static String base = const String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:3000',
  );

  static Uri _u(String path) => Uri.parse('$base$path');

  /// ดึงสลิปที่รออนุมัติ
  /// GET /api/admin/pending-slips
  /// -> { items: [ { id, post_id, buyer_email, seller_email, amount_satang, currency, status, file_path, created_at, ... } ] }
  static Future<List<Map<String, dynamic>>> getPendingSlips() async {
    final r = await http.get(_u('/api/admin/pending-slips'));
    if (r.statusCode >= 400) throw Exception('HTTP ${r.statusCode}: ${r.body}');
    final obj = jsonDecode(r.body) as Map<String, dynamic>;
    final items = (obj['items'] as List).cast<Map<String, dynamic>>();
    return items;
  }

  /// ตัดสินคำสั่งซื้อ: approved / rejected
  /// POST /api/admin/purchases/:id/decision { decision: 'approved' | 'rejected' }
  static Future<Map<String, dynamic>> decidePurchase({
    required String purchaseId,
    required bool approved,
  }) async {
    final r = await http.post(
      _u('/api/admin/purchases/$purchaseId/decision'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'decision': approved ? 'approved' : 'rejected'}),
    );
    if (r.statusCode >= 400) throw Exception('HTTP ${r.statusCode}: ${r.body}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// ช่วยต่อ URL รูปสลิป (server ส่ง /uploads/xxx)
  static String slipUrl(String? filePath) {
    if (filePath == null || filePath.isEmpty) return '';
    if (filePath.startsWith('http')) return filePath;
    if (!filePath.startsWith('/')) return '$base/$filePath';
    return '$base$filePath';
  }
}
