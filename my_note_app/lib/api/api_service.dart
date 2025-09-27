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
}


