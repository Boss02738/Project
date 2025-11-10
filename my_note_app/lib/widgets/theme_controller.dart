import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ValueNotifier<ThemeMode> {
  static const _kKey = 'app_theme_mode'; 
  ThemeController._internal(ThemeMode mode) : super(mode);

  static final ThemeController instance = ThemeController._internal(ThemeMode.system);

  static Future<void> init() async {
    final pref = await SharedPreferences.getInstance();
    final raw = pref.getString(_kKey);
    switch (raw) {
      case 'light':
        instance.value = ThemeMode.light;
        break;
      case 'dark':
        instance.value = ThemeMode.dark;
        break;
      default:
        instance.value = ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    value = mode;
    final pref = await SharedPreferences.getInstance();
    String s = 'system';
    if (mode == ThemeMode.light) s = 'light';
    if (mode == ThemeMode.dark) s = 'dark';
    await pref.setString(_kKey, s);
  }
}
