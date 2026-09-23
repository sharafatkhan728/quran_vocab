import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  ThemeProvider() {
    WidgetsBinding.instance.addObserver(this);
    _loadFuture = _loadTheme();
  }

  // 'light' | 'dark' | 'system'
  String _themeChoice = 'light';
  String get themeChoice => _themeChoice;

  ThemeMode get themeMode {
    switch (_themeChoice) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  /// Effective brightness (resolves 'system' to the phone's real setting).
  bool get isDark {
    if (_themeChoice == 'system') {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return _themeChoice == 'dark';
  }

  @override
  void didChangePlatformBrightness() {
    if (_themeChoice == 'system') notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  late final Future<void> _loadFuture;

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_choice');
    if (saved != null &&
        (saved == 'light' || saved == 'dark' || saved == 'system')) {
      _themeChoice = saved;
    } else if (prefs.containsKey('is_dark_mode')) {
      // legacy users
      _themeChoice =
          (prefs.getBool('is_dark_mode') ?? false) ? 'dark' : 'light';
    } else {
      _themeChoice =
          prefs.getString('theme_mode') == 'system' ? 'system' : 'light';
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setThemeChoice(String choice) async {
    _themeChoice = choice;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_choice', choice);
  }

  Future<void> toggleTheme() => setThemeChoice(isDark ? 'light' : 'dark');

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

  /// Wait for the same initial load started by the constructor.
  Future<void> loadSettings() => _loadFuture;
}