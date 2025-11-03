// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io'
    show
        File,
        Platform; // ถ้าจะ build เป็น Flutter Web ให้แยกไฟล์/หลีกเลี่ยง import นี้
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const _reqTimeout = Duration(seconds: 20);

class ApiService {
  // ================= BASE URL =================
  // CHANGED: รองรับ --dart-define=API_BASE ทั้ง Web และ Non-Web
  static String get host {
    // หากกำหนดผ่าน --dart-define=API_BASE จะมาก่อน
    const envBase = String.fromEnvironment('API_BASE', defaultValue: '');
    if (envBase.isNotEmpty) return envBase;

    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    if (Platform.isAndroid) return 'http://10.0.2.2:3000'; // Android emulator
    return 'http://192.168.1.38:3000'; // ปรับเป็น IP เครื่อง dev ของคุณ
  }

  // -------- Base paths --------
  static String get _auth => '$host/api/auth';
  static String get _posts => '$host/api/posts';
  static String get _search => '$host/api/search';
  // NEW: Friends base
  static String get _friends => '$host/api/friends';

  // ============== Generic HTTP helpers ==============
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
    final r = await http
        .post(
          Uri.parse('$host$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_reqTimeout);
    _ensureOk(r);
    return _decode(r.body);
  }

  /// GET JSON จาก path ที่ต่อท้าย host (เช่น '/api/purchases/{id}')
  static Future<Map<String, dynamic>> getJson(String path) async {
    final r = await http.get(Uri.parse('$host$path')).timeout(_reqTimeout);
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
    final streamed = await req.send().timeout(_reqTimeout);
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

  // ============== Auth ==============
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

  // ============== Posts ==============
  static Future<http.Response> createPost({
    required int userId,
    String? text,
    String? yearLabel,
    String? subject,
    List<File>? images,
    File? file,
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

  static Future<Map<String, dynamic>> getPostDetail({
    required int postId,
    required int viewerUserId,
  }) async {
    final uri = Uri.parse(
      '$_posts/$postId',
    ).replace(queryParameters: {'userId': '$viewerUserId'});
    final r = await http.get(uri).timeout(_reqTimeout);
    _ensureOk(r);
    return _decode(r.body);
  }

  static Future<List<dynamic>> getFeed(int userId) async {
    final resp = await http
        .get(
          Uri.parse(
            '$_posts/feed',
          ).replace(queryParameters: {'user_id': '$userId'}),
        )
        .timeout(_reqTimeout);
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
    final res = await http.get(url).timeout(_reqTimeout);
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as List<dynamic>;
    }
    throw Exception('HTTP ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> getCounts(int postId) async {
    final r = await http
        .get(Uri.parse('$_posts/posts/$postId/counts'))
        .timeout(_reqTimeout);
    if (r.statusCode != 200) throw Exception('counts fail');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<bool> toggleLike({
    required int postId,
    required int userId,
  }) async {
    final r = await http
        .post(
          Uri.parse('$_posts/posts/$postId/like'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': userId}),
        )
        .timeout(_reqTimeout);
    if (r.statusCode != 200) throw Exception('like fail');
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return m['liked'] == true;
  }

  static Future<List<dynamic>> getComments(int postId) async {
    final r = await http
        .get(Uri.parse('$_posts/posts/$postId/comments'))
        .timeout(_reqTimeout);
    if (r.statusCode != 200) throw Exception('comments fail');
    return jsonDecode(r.body) as List<dynamic>;
  }

  static Future<void> addComment({
    required int postId,
    required int userId,
    required String text,
  }) async {
    final r = await http
        .post(
          Uri.parse('$_posts/posts/$postId/comments'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': userId, 'text': text}),
        )
        .timeout(_reqTimeout);
    if (r.statusCode != 200) throw Exception('add comment fail');
  }

  // ---------------- Save ----------------
  static Future<bool> toggleSave({
    required int postId,
    required int userId,
  }) async {
    final r = await http
        .post(
          Uri.parse('$_posts/posts/$postId/save'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': userId}),
        )
        .timeout(_reqTimeout);
    if (r.statusCode != 200) throw Exception('save fail');
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return m['saved'] == true;
  }

  static Future<bool> getSavedStatus({
    required int postId,
    required int userId,
  }) async {
    final r = await http
        .get(Uri.parse('$_posts/posts/$postId/save/status?user_id=$userId'))
        .timeout(_reqTimeout);
    if (r.statusCode != 200) throw Exception('save status fail');
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return m['saved'] == true;
  }

  static Future<List<dynamic>> getSavedFeed(int userId) async {
    final r = await http
        .get(Uri.parse('$_posts/saved?user_id=$userId'))
        .timeout(_reqTimeout);
    if (r.statusCode != 200) throw Exception('saved feed fail');
    return jsonDecode(r.body) as List<dynamic>;
  }

  // ---------------- Search ----------------
  static Future<List<dynamic>> searchUsers(String query) async {
    final uri = Uri.parse(
      '$_search/users',
    ).replace(queryParameters: {'q': query});
    final resp = await http.get(uri).timeout(_reqTimeout);
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as List).cast<dynamic>();
    }
    throw Exception('search users failed');
  }

  static Future<List<String>> searchSubjects(String query) async {
    final uri = Uri.parse(
      '$_search/subjects',
    ).replace(queryParameters: {'q': query});
    final resp = await http.get(uri).timeout(_reqTimeout);
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
    final resp = await http.get(uri).timeout(_reqTimeout);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      return (data as List).map((e) => e.toString()).toList();
    }
    throw Exception('getSubjects failed: ${resp.statusCode}');
  }

  static Future<List<dynamic>> getPurchasedPosts(int userId) async {
    final uri = Uri.parse(
      '$_posts/purchased',
    ).replace(queryParameters: {'user_id': '$userId'});
    final r = await http.get(uri).timeout(_reqTimeout);
    _ensureOk(r);
    return (jsonDecode(r.body) as List).cast<dynamic>();
  }

  static Future<List<dynamic>> getPostsByUser({
    required int profileUserId,
    required int viewerId,
  }) async {
    final uri = Uri.parse(
      '$host/api/posts/user/$profileUserId',
    ).replace(queryParameters: {'viewer_id': '$viewerId'});
    final resp = await http.get(uri).timeout(_reqTimeout);
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as List).cast<dynamic>();
    }
    throw Exception('โหลดโพสต์ผู้ใช้ล้มเหลว: ${resp.statusCode}');
  }

  static Future<Map<String, dynamic>> getUserProfile(int userId) async {
    final url = Uri.parse('$_auth/user/$userId');
    final resp = await http.get(url).timeout(_reqTimeout);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
  }

  static Future<List<dynamic>> getSavedPosts(int userId) async {
    final res = await http
        .get(Uri.parse('$_posts/posts/saved/$userId'))
        .timeout(_reqTimeout);
    if (res.statusCode == 200) {
      return json.decode(res.body);
    } else {
      throw Exception('โหลดโพสต์ที่บันทึกไม่สำเร็จ');
    }
  }

  static Future<List<dynamic>> getLikedPosts(int userId) async {
    final res = await http
        .get(Uri.parse('$_posts/posts/liked/$userId'))
        .timeout(_reqTimeout);
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
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            if (username != null) 'username': username,
            if (bio != null) 'bio': bio,
          }),
        )
        .timeout(_reqTimeout);
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
    final streamed = await req.send().timeout(_reqTimeout);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw 'Upload avatar failed (${res.statusCode}) ${res.body}';
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['avatar_url'] as String?) ?? '';
  }

  // ============== NEW: รูป/ไฟล์แบบเช็คสิทธิ์ ==============

  /// ดึง "รายการรูป" ของโพสต์ตามสิทธิ์:
  /// - ฟรี/ซื้อแล้ว/เจ้าของ → ได้ทั้งหมด
  /// - ยังไม่ซื้อ → ได้รูปแรกเท่านั้น
  static Future<List<String>> getPostImagesRespectAccess({
    required int postId,
    required int viewerUserId,
  }) async {
    final uri = Uri.parse(
      '$_posts/$postId/images',
    ).replace(queryParameters: {'user_id': '$viewerUserId'});
    final res = await http.get(uri).timeout(_reqTimeout);
    if (res.statusCode != 200) {
      throw HttpException('Images error (${res.statusCode}): ${res.body}');
    }
    final list = jsonDecode(res.body) as List;
    return list
        .map((e) => (e as Map)['image_url']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// สร้าง URL สำหรับดาวน์โหลดไฟล์แนบแบบเช็คสิทธิ์
  /// UI ควรเปิดลิงก์นี้ด้วย url_launcher / ดาวน์โหลดผ่าน dio ตามต้องการ
  static String buildSecureDownloadUrl({
    required int postId,
    required int viewerUserId,
  }) {
    return '$_posts/$postId/file/download?user_id=$viewerUserId';
  }

  static Future<dynamic> _getJson(String url) async {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      // รองรับ utf8
      final body = utf8.decode(resp.bodyBytes);
      return jsonDecode(body);
    }
    throw Exception('GET $url -> ${resp.statusCode} ${resp.reasonPhrase}');
  }

  Future<List<String>> fetchPostImages(int postId, int viewerUserId) async {
    final list = await _getJson(
      '$host/api/posts/$postId/images?user_id=$viewerUserId',
    );
    return (list as List).cast<String>();
  }

  // ============== Purchases ==============
  static Future<Map<String, dynamic>> startPurchase({
    required int postId,
    required int buyerId,
  }) async {
    return postJson('/api/purchases', {'postId': postId, 'buyerId': buyerId});
  }

  static Future<Map<String, dynamic>?> createPurchase({
    required int postId,
    required int buyerId,
  }) async {
    Future<Map<String, dynamic>> _call(String path) async {
      final uri = Uri.parse('$host$path');
      final body = jsonEncode({
        'postId': postId,
        'buyerId': buyerId,
        'post_id': postId,
        'buyer_id': buyerId,
      });

      final r = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(_reqTimeout);

      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw HttpException(
          'HTTP ${r.statusCode} ${r.reasonPhrase}: ${r.body}',
        );
      }
      return _decode(r.body);
    }

    Map<String, dynamic> _normalize(Map<String, dynamic> data) {
      final purchase = (data['purchase'] is Map)
          ? (data['purchase'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      final id = data['id'] ?? purchase['id'] ?? data['purchase_id'];
      final amt =
          data['amount_satang'] ??
          data['amountSatang'] ??
          purchase['amount_satang'] ??
          purchase['amountSatang'] ??
          0;
      final qr =
          data['qr_payload'] ??
          data['qrPayload'] ??
          purchase['qr_payload'] ??
          purchase['qrPayload'];
      final exp =
          data['expires_at'] ?? data['expiresAt'] ?? purchase['expires_at'];

      if (id == null || qr == null) return data;

      return {
        'id': id is int ? id : int.tryParse('$id') ?? id,
        'amount_satang': amt is int ? amt : int.tryParse('$amt') ?? 0,
        'qr_payload': '$qr',
        'expires_at': exp,
      };
    }

    try {
      final data = await _call('/api/purchases');
      return _normalize(data);
    } on HttpException catch (e) {
      if (e.toString().contains('404')) {
        final data = await _call('/api/purchases');
        return _normalize(data);
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getPurchase(String purchaseId) async {
    return getJson('/api/purchases/$purchaseId');
  }

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
    final r = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': userId}),
        )
        .timeout(_reqTimeout);
    return r.statusCode == 200;
  }

  Future<bool> unarchivePost(int postId, int userId) async {
    final r = await http
        .post(
          Uri.parse('$_posts/$postId/unarchive'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': userId}),
        )
        .timeout(_reqTimeout);
    return r.statusCode == 200;
  }

  Future<List<dynamic>> getArchived(int userId) async {
    final r = await http
        .get(Uri.parse('$_posts/archived?user_id=$userId'))
        .timeout(_reqTimeout);
    if (r.statusCode == 200) return jsonDecode(r.body) as List;
    throw Exception('load archived failed');
  }

  // ============== Notifications ==============
  static Future<int> getUnreadCount(int userId) async {
    final uri = Uri.parse(
      '$host/api/notifications/unread-count',
    ).replace(queryParameters: {'user_id': '$userId'});
    final res = await http.get(uri).timeout(_reqTimeout);

    if (res.statusCode == 200) {
      try {
        final data = jsonDecode(res.body);
        if (data is Map && data.containsKey('unread')) {
          return (data['unread'] as num).toInt();
        } else if (data is int) {
          return data;
        }
      } catch (_) {}
      return 0;
    } else {
      throw HttpException(
        'โหลดจำนวนแจ้งเตือนล้มเหลว (${res.statusCode}): ${res.body}',
      );
    }
  }

  static Future<List<dynamic>> getNotifications(int userId) async {
    final uri = Uri.parse(
      '$host/api/notifications',
    ).replace(queryParameters: {'user_id': '$userId'});
    final res = await http.get(uri).timeout(_reqTimeout);
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as List<dynamic>;
    } else {
      throw HttpException(
        'โหลดรายการแจ้งเตือนล้มเหลว (${res.statusCode}): ${res.body}',
      );
    }
  }

  static Future<void> markAllAsRead(int userId) async {
    final uri = Uri.parse('$host/api/notifications/mark-read');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
        'อัปเดตแจ้งเตือนเป็นอ่านแล้วล้มเหลว (${res.statusCode}): ${res.body}',
      );
    }
  }
  // Future<bool> deletePost(int id) async {
  //   final r = await http.delete(Uri.parse('$_posts/$id')).timeout(_reqTimeout);
  //   return r.statusCode == 200;
  // }
Future<Map<String, dynamic>> deletePost(int id, {int? userId}) async {
  final uri = Uri.parse('$_posts/$id');
  final res = await http
      .delete(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: (userId == null) ? null : jsonEncode({'user_id': userId}),
      )
      .timeout(_reqTimeout);

  final data = jsonDecode(res.body);
  return {'ok': res.statusCode == 200, 'message': data['message'] ?? ''};
}

  // ============== Friends ==============

  /// สถานะความสัมพันธ์ระหว่าง user กับอีกคน
  /// return: 'none' | 'pending_in' | 'pending_out' | 'friends'
  static Future<String> getFriendStatus({
    required int userId,
    required int otherUserId,
  }) async {
    final res = await getJson(
      '/api/friends/status?user_id=$userId&other_id=$otherUserId',
    );
    return (res['status'] as String?) ?? 'none';
  }

  /// ส่งคำขอเป็นเพื่อน (ฉัน -> เขา)
  static Future<void> sendFriendRequest({
    required int fromUserId,
    required int toUserId,
  }) async {
    await postJson('/api/friends/request', {
      'from_user_id': fromUserId,
      'to_user_id': toUserId,
    });
  }

  /// ตอบคำขอ (ฝั่งผู้รับกด): action = 'accept' | 'reject'
  static Future<void> respondFriendRequest({
    required int userId,
    required int otherUserId,
    required String action, // 'accept' | 'reject'
  }) async {
    await postJson('/api/friends/respond', {
      'user_id': userId,
      'other_user_id': otherUserId,
      'action': action,
    });
  }

  /// ยกเลิกคำขอ (ฝั่งผู้ส่ง)
  static Future<void> cancelFriendRequest({
    required int userId,
    required int otherUserId,
  }) async {
    await postJson('/api/friends/cancel', {
      'user_id': userId,
      'other_user_id': otherUserId,
    });
  }

  /// เลิกเป็นเพื่อน (สถานะต้องเป็น accepted)
  static Future<void> unfriend({
    required int userId,
    required int otherUserId,
  }) async {
    final uri = Uri.parse(
      '$_friends/unfriend/$otherUserId',
    ).replace(queryParameters: {'user_id': '$userId'});
    final r = await http.delete(uri).timeout(_reqTimeout);
    _ensureOk(r);
  }

  /// รายชื่อเพื่อนของฉัน (status = accepted)
  static Future<List<Map<String, dynamic>>> listFriends(int userId) async {
    final res = await getJson('/api/friends/list?user_id=$userId');
    final list = (res['friends'] as List? ?? const []);
    return list
        .map<Map<String, dynamic>>((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// คิวคำขอที่ “ฉันต้องตอบ” (incoming)
  static Future<List<Map<String, dynamic>>> listIncomingRequests(
    int userId,
  ) async {
    final res = await getJson('/api/friends/requests/incoming?user_id=$userId');
    final list = (res['incoming'] as List? ?? const []);
    return list
        .map<Map<String, dynamic>>((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// คิวคำขอที่ “ฉันเป็นคนส่ง” (outgoing)
  static Future<List<Map<String, dynamic>>> listOutgoingRequests(
    int userId,
  ) async {
    final res = await getJson('/api/friends/requests/outgoing?user_id=$userId');
    final list = (res['outgoing'] as List? ?? const []);
    return list
        .map<Map<String, dynamic>>((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getFriends(int userId) async {
    final url = Uri.parse('$host/api/friends/list?user_id=$userId');
    final resp = await http.get(url).timeout(_reqTimeout);
    if (resp.statusCode != 200) {
      throw Exception('โหลดรายชื่อเพื่อนไม่สำเร็จ: HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (data['friends'] as List? ?? [])
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .toList();
    return list;
  }

  // ============== Wallet/Coins ==============
  Future<Map<String, String>> _jsonAuthHeaders() async {
    final token =
        await getToken(); // TODO: ดึงจากที่คุณเก็บจริง (SharedPreferences ฯลฯ)
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// TODO: แทนที่ด้วยวิธีเอา token จริงของโปรเจ็กต์คุณ
  Future<String?> getToken() async {
    return null;
  }

  Future<Map<String, dynamic>> getWithdrawConfig() async {
  final uri = Uri.parse('$host/api/withdrawals/config');

  final res = await http.get(
    uri,
    headers: {
      'Accept': 'application/json',
      // ถ้ามี token ให้ใส่แบบนี้:
      // 'Authorization': 'Bearer $token',
    },
  );

  if (res.statusCode != 200) {
    throw '(${res.statusCode}) ${res.body}';
  }

  final data = jsonDecode(res.body);
  return (data is Map<String, dynamic>)
      ? data
      : <String, dynamic>{};
}

  /// ดึงยอดเหรียญคงเหลือของผู้ใช้
  Future<int> getWalletBalance({int? userId}) async {
    // 1) /api/users/me (auth)
    try {
      final uri1 = Uri.parse('${ApiService.host}/api/users/me');
      final r1 = await http
          .get(uri1, headers: await _jsonAuthHeaders())
          .timeout(_reqTimeout);

      if (r1.statusCode == 200) {
        final j = json.decode(r1.body) as Map<String, dynamic>;
        final coins = (j['coins'] as num?)?.toInt();
        if (coins != null) return coins;
      }
    } catch (_) {
      // ignore → ไป fallback
    }

    // 2) fallback ต้องมี userId
    if (userId == null) {
      throw const HttpException(
        'ต้องระบุ userId เมื่อไม่มี token (fallback /api/wallet)',
      );
    }
    final uri2 = Uri.parse(
      '${ApiService.host}/api/wallet',
    ).replace(queryParameters: {'user_id': '$userId'});
    final r2 = await http.get(uri2).timeout(_reqTimeout);
    if (r2.statusCode != 200) {
      throw HttpException('โหลดยอดไม่สำเร็จ (${r2.statusCode}): ${r2.body}');
    }
    final j2 = json.decode(r2.body) as Map<String, dynamic>;
    final coins = (j2['coins'] as num?)?.toInt();
    if (coins == null) {
      throw const HttpException('รูปแบบผลลัพธ์ไม่ถูกต้อง (coins)');
    }
    return coins;
  }

  /// สร้างคำขอถอน: POST /api/withdrawals (multipart: user_id, coins, qr)
  Future<Map<String, dynamic>> createWithdrawal({
    required int userId,
    required int coins,
    required File qrFile,
  }) async {
    final uri = Uri.parse('${ApiService.host}/api/withdrawals');
    final req = http.MultipartRequest('POST', uri)
      ..fields['user_id'] = '$userId'
      ..fields['coins'] = '$coins'
      ..files.add(await http.MultipartFile.fromPath('qr', qrFile.path));

    req.headers.addAll(await _jsonAuthHeaders());

    final streamed = await req.send().timeout(_reqTimeout);
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 201) {
      throw HttpException(
        'สร้างคำขอถอนล้มเหลว (${resp.statusCode}): ${resp.body}',
      );
    }
    final j = json.decode(resp.body) as Map<String, dynamic>;
    return (j['withdrawal'] as Map?)?.cast<String, dynamic>() ?? j;
  }

  /// ประวัติถอนของฉัน: GET /api/withdrawals/my?user_id=...
  Future<List<Map<String, dynamic>>> getMyWithdrawals({
    required int userId,
  }) async {
    final uri = Uri.parse(
      '${ApiService.host}/api/withdrawals/my',
    ).replace(queryParameters: {'user_id': '$userId'});
    final r = await http
        .get(uri, headers: await _jsonAuthHeaders())
        .timeout(_reqTimeout);
    if (r.statusCode != 200) {
      throw HttpException('โหลดประวัติถอนล้มเหลว (${r.statusCode}): ${r.body}');
    }
    final j = json.decode(r.body) as Map<String, dynamic>;
    final items = (j['items'] as List? ?? const [])
        .map<Map<String, dynamic>>((e) => (e as Map).cast<String, dynamic>())
        .toList();
    return items;
  }
}

// ===== Report Post API =====
Future<void> reportPost({
  required int postId,
  required int userId,
  required String reason,
  String? details,
}) async {
  // ถ้าในคลาสมีตัวแปร host อยู่แล้ว เช่น: static String host = 'http://...';
  // ให้เรียกผ่าน ApiService.host เพื่อกันชื่อซ้ำ/scope ผิด
  final uri = Uri.parse('${ApiService.host}/api/reports');

  final payload = <String, dynamic>{
    'post_id': postId,
    'reporter_id': userId,
    'reason': reason,
    if ((details ?? '').trim().isNotEmpty) 'details': (details ?? '').trim(),
  };

  final r = await http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 20)); // แทน _reqTimeout

  // ถ้าไฟล์นี้ไม่มี _ensureOk ให้ใช้เช็คสถานะแบบนี้
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('HTTP ${r.statusCode}: ${r.body}');
  }
}

// Error อ่านง่ายขึ้นเวลามี status >= 400
class HttpException implements Exception {
  final String message;
  const HttpException(this.message);
  @override
  String toString() => message;
}

