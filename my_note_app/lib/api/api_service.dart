import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  //เปลี่ยนเป็น IP V4 ของเครื่องตัวเอง
  static const String baseUrl = 'http://10.40.150.148:3000/api/auth';
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
  static Future<http.Response> updateProfile({
    required String email,
    String? bio,
    String? gender,
  }) => http.post(
    Uri.parse('$baseUrl/profile/update'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'email': email, 'bio': bio, 'gender': gender}),
  );
   // 🔹 อัปโหลด avatar (multipart/form-data; field: avatar)
  static Future<http.StreamedResponse> uploadAvatar({
    required String email,
    required File file,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/profile/avatar'));
    req.fields['email'] = email;
    req.files.add(await http.MultipartFile.fromPath('avatar', file.path));
    return req.send();
  }
}

