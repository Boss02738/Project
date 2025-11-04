// lib/main.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';

/// ตัวควบคุมธีม (บันทึกค่าไว้ใน SharedPreferences)
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._(ThemeMode m) : super(m);
  static final instance = ThemeController._(ThemeMode.system);
  static const _k = 'app_theme_mode';

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    instance.value = switch (p.getString(_k)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode m) async {
    value = m;
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, m == ThemeMode.light ? 'light' : m == ThemeMode.dark ? 'dark' : 'system');
  }

  // ✅ รองรับโค้ดเก่าที่เรียก setMode(...)
  Future<void> setMode(ThemeMode m) => set(m);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // ใช้ฟ้าเป็นสีหลัก
  static const _seedBlue = Color(0xFF3B82F6);

  ThemeData _light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seedBlue, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF7F9FE),
        appBarTheme: const AppBarTheme(centerTitle: true),
      );

  ThemeData _dark() {
    final scheme = ColorScheme.fromSeed(seedColor: _seedBlue, brightness: Brightness.dark);
    const bg = Color(0xFF0B1217), surface = Color(0xFF0F151A), card = Color(0xFF121A20);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(background: bg, surface: surface, surfaceTint: scheme.primary),
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(centerTitle: true, backgroundColor: surface),
      cardColor: card,
      listTileTheme: const ListTileThemeData(tileColor: card),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ThemeController.instance,
      builder: (_, ThemeMode mode, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Note App',
        theme: _light(),
        darkTheme: _dark(),
        themeMode: mode,
        initialRoute: '/login',
        routes: {
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
        },
      ),
    );
  }
}
