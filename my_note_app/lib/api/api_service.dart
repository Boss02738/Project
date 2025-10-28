// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io'; // ถ้าจะ build เป็น Flutter Web ให้แยกไฟล์/หลีกเลี่ยง import นี้
import 'dart:typed_data'; // << เพิ่ม สำหรับ Uint8List
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // ---------- BASE URL ----------
  static String get host {
    if (kIsWeb) {
      const env = String.fromEnvironment(
        'API_BASE',
        defaultValue: 'http://localhost:3000',
      );
      return env;
    }
    if (Platform.isAndroid) return 'http://10.0.2.2:3000'; // Android emulator
    return 'http://10.34.104.53:3000'; // ปรับเป็น IP เครื่อง dev
  }

  // ---------- Base paths ----------
  static String get _auth => '$host/api/auth';
  static String get _posts => '$host/api/posts';
  static String get _search => '$host/api/search';

  // =========================================================
  // =================== Generic HTTP helpers =================
  // =========================================================
  static Map<String, dynamic> _decode(String body) {
    final obj = jsonDecode(body);
    return obj is Map<String, dynamic> ? obj : {'data': obj};
  }

  static void _ensureOk(http.Response r) {
    if (r.statusCode >= 400) {
      throw HttpException('HTTP ${r.statusCode}: ${r.body}');
    }
  }

  /// POST JSON ไป path ที่ต่อท้าย host (เช่น '/api/purchases')
  static Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final r = await http.post(
      Uri.parse('$host$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    _ensureOk(r);
    return _decode(r.body);
  }

  /// GET JSON จาก path ที่ต่อท้าย host (เช่น '/api/purchases/{id}')
  static Future<Map<String, dynamic>> getJson(String path) async {
    final r = await http.get(Uri.parse('$host$path'));
    _ensureOk(r);
    return _decode(r.body);
  }

  /// อัปโหลดไฟล์ multipart (ใช้ fieldName ที่ต้องการได้)
  static Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String filePath,
    String fieldName = 'file',
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$host$path'));
    req.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    _ensureOk(res);
    return _decode(res.body);
  }

  /// แปลง DataURL -> bytes (เช่น PNG ของ QR)
  static Uint8List dataUrlToBytes(String dataUrl) {
    final i = dataUrl.indexOf(',');
    if (i < 0) throw const FormatException('Invalid data URL');
    final b64 = dataUrl.substring(i + 1);
    return base64Decode(b64);
  }

  // =========================================================
  // ========================== Auth =========================
  // =========================================================
  static Future<http.Response> register(
    String username,
    String password,
  ) async {
    final url = Uri.parse('$_auth/register');
    return http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
  }

  static Future<http.Response> login(String email, String password) async {
    return http.post(
      Uri.parse('$_auth/login'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email, "password": password}),
    );
  }

  static Future<http.Response> uploadAvatar({
    required String email,
    required File file,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_auth/profile/avatar'),
    );
    req.fields['email'] = email;
    req.files.add(await http.MultipartFile.fromPath('avatar', file.path));
    final streamed = await req.send();
    return http.Response.fromStream(streamed);
  }

  static Future<http.Response> updateProfile({
    required String email,
    String? bio,
    String? gender,
    String? phone,
  }) {
    return http.post(
      Uri.parse('$_auth/profile/update'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'bio': bio,
        'gender': gender,
        'phone': phone,
      }),
    );
  }

  /// อัปเดต bio + phone (ไว้ใช้ PromptPay)
  static Future<void> updatePhoneAndBio({
    required int userId,
    String? bio,
    String? phone,
  }) async {
    final r = await http.post(
      Uri.parse('$host/api/users/$userId/profile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'bio': bio, 'phone': phone}),
    );
    _ensureOk(r);
  }

  static Future<Map<String, dynamic>> getUserBrief(int userId) async {
    final resp = await http.get(Uri.parse('$_auth/user/$userId'));
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } else {
      throw Exception('โหลดข้อมูลผู้ใช้ล้มเหลว: ${resp.statusCode}');
    }
  }

  // =========================================================
  // ========================== Posts ========================
  // =========================================================
  /// สร้างโพสต์ (แนบหลายรูป + แนบไฟล์ + ราคา)
  static Future<http.Response> createPost({
    required int userId,
    String? text,
    String? yearLabel,
    String? subject,
    List<File>? images,
    File? file,

    // ราคา
    String priceType = 'free', // 'free' | 'paid'
    double? priceBaht,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_posts'));
    req.fields['user_id'] = userId.toString();
    if (text != null) req.fields['text'] = text;
    if (yearLabel != null) req.fields['year_label'] = yearLabel;
    if (subject != null) req.fields['subject'] = subject;

    // ราคา
    if (priceType == 'paid') {
      final satang = ((priceBaht ?? 0) * 100).round();
      req.fields['price_type'] = 'paid';
      req.fields['price_amount_satang'] = satang.toString();
    } else {
      req.fields['price_type'] = 'free';
      req.fields['price_amount_satang'] = '0';
    }

    // รูปหลายรูป
    final imgList = (images ?? []).take(10);
    for (final img in imgList) {
      req.files.add(await http.MultipartFile.fromPath('images', img.path));
    }

    // ไฟล์แนบเดี่ยว
    if (file != null) {
      req.files.add(await http.MultipartFile.fromPath('file', file.path));
    }

    final streamed = await req.send();
    return http.Response.fromStream(streamed);
  }

  /// รายละเอียดโพสต์ + hasAccess (ใช้ตัดสินใจแสดงปุ่ม “ซื้อ”)
  static Future<Map<String, dynamic>> getPostDetail({
    required int postId,
    required int viewerUserId,
  }) async {
    final uri = Uri.parse(
      '$_posts/$postId',
    ).replace(queryParameters: {'userId': '$viewerUserId'});
    final r = await http.get(uri);
    _ensureOk(r);
    return _decode(r.body); // { post, hasAccess }
  }

  static Future<List<dynamic>> getFeed(int userId) async {
    final resp = await http.get(
      Uri.parse(
        '$_posts/feed',
      ).replace(queryParameters: {'user_id': '$userId'}),
    );
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as List<dynamic>;
    }
    throw Exception('โหลดฟีดล้มเหลว: ${resp.statusCode}');
  }

  static Future<List<dynamic>> getFeedBySubject(
    String subject,
    int userId,
  ) async {
    final url = Uri.parse(
      '$_posts/by-subject',
    ).replace(queryParameters: {'subject': subject, 'user_id': '$userId'});
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as List<dynamic>;
    }
    throw Exception('HTTP ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> getCounts(int postId) async {
    final r = await http.get(Uri.parse('$_posts/posts/$postId/counts'));
    if (r.statusCode != 200) throw Exception('counts fail');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<bool> toggleLike({
    required int postId,
    required int userId,
  }) async {
    final r = await http.post(
      Uri.parse('$_posts/posts/$postId/like'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    if (r.statusCode != 200) throw Exception('like fail');
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return m['liked'] == true;
  }

  static Future<List<dynamic>> getComments(int postId) async {
    final r = await http.get(Uri.parse('$_posts/posts/$postId/comments'));
    if (r.statusCode != 200) throw Exception('comments fail');
    return jsonDecode(r.body) as List<dynamic>;
  }

  static Future<void> addComment({
    required int postId,
    required int userId,
    required String text,
  }) async {
    final r = await http.post(
      Uri.parse('$_posts/posts/$postId/comments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'text': text}),
    );
    if (r.statusCode != 200) throw Exception('add comment fail');
  }

  // ---------------- Save ----------------
  static Future<bool> toggleSave({
    required int postId,
    required int userId,
  }) async {
    final r = await http.post(
      Uri.parse('$_posts/posts/$postId/save'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    if (r.statusCode != 200) throw Exception('save fail');
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return m['saved'] == true;
  }

  static Future<bool> getSavedStatus({
    required int postId,
    required int userId,
  }) async {
    final r = await http.get(
      Uri.parse('$_posts/posts/$postId/save/status?user_id=$userId'),
    );
    if (r.statusCode != 200) throw Exception('save status fail');
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return m['saved'] == true;
  }

  static Future<List<dynamic>> getSavedFeed(int userId) async {
    final r = await http.get(Uri.parse('$_posts/saved?user_id=$userId'));
    if (r.statusCode != 200) throw Exception('saved feed fail');
    return jsonDecode(r.body) as List<dynamic>;
  }

  // ---------------- Search ----------------
  static Future<List<dynamic>> searchUsers(String query) async {
    final uri = Uri.parse(
      '$_search/users',
    ).replace(queryParameters: {'q': query});
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as List).cast<dynamic>();
    }
    throw Exception('search users failed');
  }

  static Future<List<String>> searchSubjects(String query) async {
    final uri = Uri.parse(
      '$_search/subjects',
    ).replace(queryParameters: {'q': query});
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as List).map((e) => e.toString()).toList();
    }
    throw Exception('search subjects failed');
  }

  static Future<List<String>> getSubjects({
    String? yearLabel,
    String? q,
  }) async {
    final uri = Uri.parse('$_search/subjects').replace(
      queryParameters: {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (yearLabel != null && yearLabel.trim().isNotEmpty)
          'year_label': yearLabel.trim(),
      },
    );
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      return (data as List).map((e) => e.toString()).toList();
    }
    throw Exception('getSubjects failed: ${resp.statusCode}');
  }

  static Future<List<dynamic>> getPostsByUser({
    required int profileUserId,
    required int viewerId,
  }) async {
    final uri = Uri.parse(
      '$host/api/posts/user/$profileUserId',
    ).replace(queryParameters: {'viewer_id': '$viewerId'});
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as List).cast<dynamic>();
    }
    throw Exception('โหลดโพสต์ผู้ใช้ล้มเหลว: ${resp.statusCode}');
  }

  static Future<Map<String, dynamic>> getUserProfile(int userId) async {
    final url = Uri.parse('$_auth/user/$userId');
    final resp = await http.get(url);
    // debug ชั่วคราว
    // print('GET $url -> ${resp.statusCode} ${resp.body}');
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
  }

  static Future<List<dynamic>> getSavedPosts(int userId) async {
    final res = await http.get(Uri.parse('$_posts/posts/saved/$userId'));
    if (res.statusCode == 200) {
      return json.decode(res.body);
    } else {
      throw Exception('โหลดโพสต์ที่บันทึกไม่สำเร็จ');
    }
  }

  static Future<List<dynamic>> getLikedPosts(int userId) async {
    final res = await http.get(Uri.parse('$_posts/posts/liked/$userId'));
    if (res.statusCode == 200) {
      return json.decode(res.body);
    } else {
      throw Exception('โหลดโพสต์ที่ถูกใจไม่สำเร็จ');
    }
  }

  static Future<void> updateProfileById({
    required int userId,
    String? username,
    String? bio,
  }) async {
    final uri = Uri.parse('$_auth/profile/update-by-id');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        if (username != null) 'username': username,
        if (bio != null) 'bio': bio,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw 'Update profile failed (${res.statusCode}) ${res.body}';
    }
  }

  static Future<String> uploadAvatarById({
    required int userId,
    required File file,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_auth/profile/avatar-by-id'),
    );
    req.fields['user_id'] = '$userId';
    req.files.add(await http.MultipartFile.fromPath('avatar', file.path));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw 'Upload avatar failed (${res.statusCode}) ${res.body}';
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['avatar_url'] as String?) ?? '';
  }

  // =========================================================
  // ======================= Purchases =======================
  // =========================================================

  /// เริ่มคำสั่งซื้อ → { purchase, qrPngDataUrl }
  static Future<Map<String, dynamic>> startPurchase({
    required int postId,
    required int buyerId,
  }) async {
    return postJson('/api/purchases', {'postId': postId, 'buyerId': buyerId});
  }

  /// ดึงรายละเอียดออเดอร์ → { purchase }
  static Future<Map<String, dynamic>> getPurchase(String purchaseId) async {
    return getJson('/api/purchases/$purchaseId');
  }

  /// อัปโหลดสลิป (field name = 'slip')
  static Future<Map<String, dynamic>> uploadPurchaseSlip({
    required String purchaseId,
    required File slipFile,
  }) async {
    return uploadFile(
      '/api/purchases/$purchaseId/slip',
      filePath: slipFile.path,
      fieldName: 'slip',
    );
  }

  Future<bool> archivePost(int postId, int userId) async {
    final url = Uri.parse('$_posts/$postId/archive');
    final r = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    return r.statusCode == 200;
  }

  Future<bool> unarchivePost(int postId, int userId) async {
    final r = await http.post(Uri.parse('$_posts/$postId/unarchive'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    return r.statusCode == 200;
  }
  Future<List<dynamic>> getArchived(int userId) async {
    final r = await http.get(Uri.parse('$_posts/archived?user_id=$userId'));
    if (r.statusCode == 200) return jsonDecode(r.body) as List;
    throw Exception('load archived failed');
  }
    Future<bool> deletePost(int id) async {
    final r = await http.delete(Uri.parse('$_posts/$id'));
    return r.statusCode == 200;
  }
}


// Error อ่านง่ายขึ้นเวลามี status >= 400
class HttpException implements Exception {
  final String message;
  const HttpException(this.message);
  @override
  String toString() => message;
}
