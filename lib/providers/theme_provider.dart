import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDark = false;
  bool get isDark => _isDark;

  String _arabicFont = 'uthmani'; // uthmani, indopak
  String get arabicFont => _arabicFont;

  Future<void> setArabicFont(String font) async {
    _arabicFont = font;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('arabic_font', font);
    notifyListeners();
  }

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool('is_dark_mode') ?? false;
    _arabicFont = prefs.getString('arabic_font') ?? 'uthmani';
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDark = !_isDark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', _isDark);
    notifyListeners();
  }

  static const _seed = Color(0xFF1B4332);

  ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: _seed,
        scaffoldBackgroundColor: const Color(0xFFFDF8F0),
        cardColor: Colors.white,
        dividerColor: const Color(0xFFE0E0E0),
        listTileTheme: const ListTileThemeData(
          tileColor: Colors.transparent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1B4332),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      );

  ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: _seed,
        scaffoldBackgroundColor: const Color(0xFF0D1B12),
        cardColor: const Color(0xFF1A2E1F),
        dividerColor: const Color(0xFF2C2C2C),
        listTileTheme: const ListTileThemeData(
          tileColor: Colors.transparent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1B12),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF1A2E1F),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      );
}