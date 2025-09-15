import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
//เปลี่ยนเป็น IP V4 ของเครื่องตัวเอง
static const String baseUrl = 'http://10.40.150.148:3000/api/auth';
//register
  static Future<http.Response> register(String username, String password) async {
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
  
}
