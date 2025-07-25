import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // ถ้าใช้บนมือถือจริง ให้เปลี่ยน localhost เป็น IP ของเครื่องที่รัน backend อาจจะต้องเปลี่ยนตอนหลัง เพราะ อาจต้องโยนขึ้น cloud ถ
static const String baseUrl = 'http://10.40.150.148:3000/api/auth';

  static Future<http.Response> register(String username, String password) async {
    final url = Uri.parse('$baseUrl/register');
    return await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
  }

  static Future<http.Response> login(String username, String password) async {
    final url = Uri.parse('$baseUrl/login');
    return await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
  }
}