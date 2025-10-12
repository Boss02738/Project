import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  //เปลี่ยนเป็น IP V4 ของเครื่องตัวเอง
  static const String baseUrl = 'http://10.40.150.148:3000/api/auth';
  static const String host = 'http://10.40.150.148:3000';
  
  //register
  static Future<http.Response> register(
    String username,
    String password,
  ) async {
    final url = Uri.parse('$baseUrl/register');
    return await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
  }

  //login
  static Future<http.Response> login(String email, String password) async {
    return await http.post(
      Uri.parse("$baseUrl/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email, "password": password}),
    );
  }

  //update profile
 static Future<http.Response> uploadAvatar({
    required String email,
    required File file,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/profile/avatar'));
    req.fields['email'] = email; // ต้องชื่อ email
    req.files.add(await http.MultipartFile.fromPath('avatar', file.path)); // ต้องชื่อ avatar
    final streamed = await req.send();
    return http.Response.fromStream(streamed); // ✅ คืน http.Response
  }

  static Future<http.Response> updateProfile({
    required String email,
    String? bio,
    String? gender,
  }) {
    return http.post(
      Uri.parse('$baseUrl/profile/update'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'bio': bio, 'gender': gender}),
    );
  }
    static Future<Map<String, dynamic>> getUserBrief(int userId) async {
    final resp = await http.get(Uri.parse('$baseUrl/user/$userId'));
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } else {
      throw Exception('โหลดข้อมูลผู้ใช้ล้มเหลว: ${resp.statusCode}');
    }
  }
    static Future<http.Response> createPost( {
    required int userId,
    String? text,
    String? yearLabel,
    String? subject,
    File? image,
    File? file,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/posts'));
    req.fields['user_id'] = userId.toString();
    if (text != null)      req.fields['text'] = text;
    if (yearLabel != null) req.fields['year_label'] = yearLabel;
    if (subject != null)   req.fields['subject'] = subject;
    if (image != null) {
      req.files.add(await http.MultipartFile.fromPath('image', image.path));
    }
    if (file != null) {
      req.files.add(await http.MultipartFile.fromPath('file', file.path));
    }
    final streamed = await req.send();
    return http.Response.fromStream(streamed);
  }

static Future<List<dynamic>> getFeed(int userId) async {
  final resp = await http.get(
    Uri.parse('$baseUrl/posts').replace(queryParameters: {'user_id': '$userId'}),
  );
  if (resp.statusCode == 200) {
    return jsonDecode(resp.body) as List<dynamic>;
  }
  throw Exception('โหลดฟีดล้มเหลว: ${resp.statusCode}');
}

  static Future<List<dynamic>> searchUsers(String query) async {
    final uri = Uri.parse('$host/api/search/users').replace(queryParameters: {
      'q': query,
    });
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      // expect: [{id_user, username, avatar_url}, ...]
      return (data as List).cast<dynamic>();
    }
    throw Exception('search users failed');
  }

  // GET /api/search/subjects?q=...
  static Future<List<String>> searchSubjects(String query) async {
    final uri = Uri.parse('$host/api/search/subjects').replace(queryParameters: {
      'q': query,
    });
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      // expect: ["subject A", "subject B", ...]
      return (data as List).map((e) => e.toString()).toList();
    }
    throw Exception('search subjects failed');
  }

static Future<List<dynamic>> getFeedBySubject(String subject, int userId) async {
  final encoded = Uri.encodeComponent(subject);
  final url = Uri.parse('$host/api/posts/subject/$encoded')
      .replace(queryParameters: {'user_id': '$userId'});
  final res = await http.get(url);
  if (res.statusCode == 200) {
    return jsonDecode(res.body) as List<dynamic>;
  }
  throw Exception('HTTP ${res.statusCode}');
}

static Future<Map<String, dynamic>> getCounts(int postId) async {
  final r = await http.get(Uri.parse('$baseUrl/posts/$postId/counts')); // <<<<<
  if (r.statusCode != 200) throw Exception('counts fail');
  return jsonDecode(r.body) as Map<String, dynamic>;
}

static Future<bool> toggleLike({required int postId, required int userId}) async {
  final r = await http.post(
    Uri.parse('$baseUrl/posts/$postId/like'),     // <<<<<
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'user_id': userId}),
  );
  if (r.statusCode != 200) throw Exception('like fail');
  final m = jsonDecode(r.body) as Map<String, dynamic>;
  return m['liked'] == true;
}

static Future<List<dynamic>> getComments(int postId) async {
  final r = await http.get(Uri.parse('$baseUrl/posts/$postId/comments')); // <<<<<
  if (r.statusCode != 200) throw Exception('comments fail');
  return jsonDecode(r.body) as List<dynamic>;
}

 static Future<void> addComment({
    required int postId,
    required int userId,
    required String text,
  }) async {
    final r = await http.post(
      Uri.parse('$baseUrl/posts/$postId/comments'),                   // ✅
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'text': text}),
    );
    if (r.statusCode != 200) throw Exception('add comment fail');
  }
}

