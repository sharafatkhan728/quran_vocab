import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
// import 'screens/surah_list_screen.dart';
// import 'screens/vocabulary_screen.dart';
// import 'screens/progress_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/user_provider.dart';
import 'providers/display_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/auth_screen.dart';
// import 'screens/profile_settings_screen.dart';
import 'services/morphology_service.dart';
import 'services/quran_cache_service.dart';
import 'services/translation_service.dart';
import 'services/word_glossary_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/main_navigation.dart';

/// Global navigator key — accessible from anywhere in the app
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase must be first
  await Firebase.initializeApp();

  // Warm up prefs cache so subsequent calls are instant
  await SharedPreferences.getInstance();

  // Load theme first so no flash on startup
  final themeProvider = ThemeProvider();
  await themeProvider.loadSettings();

  // Critical: must await — surah reader depends on this being loaded
  await MorphologyService.initialize();

  // Translation + glossary JSON assets (bundled, ~2-5MB each)
  await TranslationService.init();
  await WordGlossaryService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => DisplayProvider()),
      ],
      child: const QuranApp(),
    ),
  );

  // Build word index AFTER UI is visible — CPU intensive, runs in background
  QuranCacheService.buildWordIndex();
}

class QuranApp extends StatelessWidget {
  const QuranApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    if (!themeProvider.isLoaded) {
      return const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF1B4332),
          body: Center(
            child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
          ),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Quran Kalima',
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.isDark ? ThemeMode.dark : ThemeMode.light,
      // Stable key — prevents navigator rebuild on theme change
      navigatorKey: appNavigatorKey,
      home: const _AppHome(),
    );
  }
}

/// Separated from QuranApp so StreamBuilder is NOT rebuilt on theme changes
class _AppHome extends StatelessWidget {
  const _AppHome();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // While Firebase checks auth state — show spinner, not full app
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1B4332),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
            ),
          );
        }

        if (snapshot.hasData) {
          return Consumer<UserProvider>(
            builder: (context, userProvider, child) {
              if (userProvider.isRestoring) {
                return const _RestoringScreen();
              }
              return const MainNavigation();
            },
          );
        }

        return const AuthScreen();
      },
    );
  }
}


/// Shown while cloud sync restores user data after login
class _RestoringScreen extends StatelessWidget {
  const _RestoringScreen();

  @override
  Widget build(BuildContext context) {
    // No nested MaterialApp — uses outer app's theme and navigator
    return const Scaffold(
      backgroundColor: Color(0xFF1B4332),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('﷽',
                style: TextStyle(fontSize: 36, color: Color(0xFFD4AF37))),
            SizedBox(height: 32),
            CircularProgressIndicator(color: Color(0xFFD4AF37)),
            SizedBox(height: 20),
            Text(
              'Restoring your progress...',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 8),
            Text(
              'آپ کی پیشرفت بحال ہو رہی ہے',
              style: TextStyle(color: Color(0xFFD4AF37), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}