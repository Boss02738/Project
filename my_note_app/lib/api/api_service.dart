import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // Android emulator ใช้ 10.0.2.2, ถ้ารันบนมือถือใช้ IP จริงของเครื่อง dev
  static String get host {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:3000';      // Android emulator
    }
    return 'http://10.40.150.148:3000';   // Physical device/iOS
  }

  // แยก base ตามกลุ่ม API ชัด ๆ
  static String get _auth => '$host/api/auth';
  static String get _posts => '$host/api/posts';
  static String get _search => '$host/api/search';

  // ---------------- Auth ----------------
  static Future<http.Response> register(String username, String password) async {
    final url = Uri.parse('$_auth/register');
    return http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
  }

  static Future<http.Response> login(String email, String password) async {
    return http.post(
      Uri.parse("$_auth/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email, "password": password}),
    );
  }

  // --------------- Profile ---------------
  static Future<http.Response> uploadAvatar({
    required String email,
    required File file,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_auth/profile/avatar'));
    req.fields['email'] = email; // ต้องชื่อ email
    req.files.add(await http.MultipartFile.fromPath('avatar', file.path)); // ต้องชื่อ avatar
    final streamed = await req.send();
    return http.Response.fromStream(streamed);
  }

  static Future<http.Response> updateProfile({
    required String email,
    String? bio,
    String? gender,
  }) {
    return http.post(
      Uri.parse('$_auth/profile/update'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'bio': bio, 'gender': gender}),
    );
  }

  static Future<Map<String, dynamic>> getUserBrief(int userId) async {
    final resp = await http.get(Uri.parse('$_auth/user/$userId'));
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } else {
      throw Exception('โหลดข้อมูลผู้ใช้ล้มเหลว: ${resp.statusCode}');
    }
  }

  // ---------------- Posts ----------------
  /// สร้างโพสต์: แนบรูปหลายรูปผ่านฟิลด์ "images" (สูงสุด 10) + แนบไฟล์ "file" ได้ 1 ชิ้น
  static Future<http.Response> createPost({
    required int userId,
    String? text,
    String? yearLabel,
    String? subject,
    List<File>? images,
    File? file,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_posts'));
    req.fields['user_id'] = userId.toString();
    if (text != null) req.fields['text'] = text;
    if (yearLabel != null) req.fields['year_label'] = yearLabel;
    if (subject != null) req.fields['subject'] = subject;

    // แนบรูปหลายไฟล์: field name ต้องเป็น 'images'
    final imgList = (images ?? []).take(10);
    for (final img in imgList) {
      req.files.add(await http.MultipartFile.fromPath('images', img.path));
    }

    // แนบไฟล์เอกสาร (ถ้ามี)
    if (file != null) {
      req.files.add(await http.MultipartFile.fromPath('file', file.path));
    }

    final streamed = await req.send();
    return http.Response.fromStream(streamed);
  }

  static Future<List<dynamic>> getFeed(int userId) async {
    final resp = await http.get(
      Uri.parse('$_posts/feed').replace(queryParameters: {'user_id': '$userId'}),
    );
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as List<dynamic>;
    }
    throw Exception('โหลดฟีดล้มเหลว: ${resp.statusCode}');
  }

  static Future<List<dynamic>> getFeedBySubject(String subject, int userId) async {
    // ฝั่ง backend ใช้ /api/posts/by-subject?subject=...
    final url = Uri.parse('$_posts/by-subject').replace(queryParameters: {
      'subject': subject,
      'user_id': '$userId',
    });
    final res = await http.get(url);
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as List<dynamic>;
    }
    throw Exception('HTTP ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> getCounts(int postId) async {
    // เส้นทางอยู่ใต้ /api/posts (อย่าอิง /api/auth)
    final r = await http.get(Uri.parse('$_posts/posts/$postId/counts'));
    if (r.statusCode != 200) throw Exception('counts fail');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<bool> toggleLike({required int postId, required int userId}) async {
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
  static Future<bool> toggleSave({required int postId, required int userId}) async {
    final r = await http.post(
      Uri.parse('$_posts/posts/$postId/save'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    if (r.statusCode != 200) throw Exception('save fail');
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return m['saved'] == true;
  }

  static Future<bool> getSavedStatus({required int postId, required int userId}) async {
    final r = await http.get(Uri.parse('$_posts/posts/$postId/save/status?user_id=$userId'));
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
    final uri = Uri.parse('$_search/users').replace(queryParameters: {'q': query});
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as List).cast<dynamic>();
    }
    throw Exception('search users failed');
  }

  static Future<List<String>> searchSubjects(String query) async {
    final uri = Uri.parse('$_search/subjects').replace(queryParameters: {'q': query});
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as List).map((e) => e.toString()).toList();
    }
    throw Exception('search subjects failed');
  }
  static Future<List<String>> getSubjects({String? yearLabel, String? q}) async {
  final uri = Uri.parse('$_search/subjects').replace(queryParameters: {
    if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    if (yearLabel != null && yearLabel.trim().isNotEmpty) 'year_label': yearLabel.trim(),
  });
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
  final uri = Uri.parse('$host/api/posts/user/$profileUserId')
      .replace(queryParameters: {'viewer_id': '$viewerId'});
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
}
