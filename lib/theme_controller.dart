import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
/// Global theme controller: dark mode + named [AppSkin].
/// Persists in SharedPreferences (`dark_mode`, `app_skin`).

class ThemeController {
  static final ThemeController instance = ThemeController._internal();
  ThemeController._internal();
  final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.light);
  final ValueNotifier<AppSkin> skin =
      ValueNotifier<AppSkin>(AppSkin.precision);
  static const _darkPrefKey = 'dark_mode';
  static const _skinPrefKey = 'app_skin';
  /// Load saved theme from SharedPreferences.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_darkPrefKey) ?? false;
    themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
    final skinName = prefs.getString(_skinPrefKey);
    skin.value = AppSkin.values.firstWhere(
      (s) => s.name == skinName,
      orElse: () => AppSkin.precision,
    );
  }
  /// Set dark mode on/off and persist the choice.
  Future<void> setDarkMode(bool isDark) async {
    themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkPrefKey, isDark);
  }
  /// Set named skin and persist the choice.
  Future<void> setSkin(AppSkin value) async {
    skin.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skinPrefKey, value.name);
  }
}
