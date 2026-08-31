import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/user_provider.dart';
import 'providers/display_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/auth_screen.dart';
import 'services/translation_service.dart';
import 'services/word_glossary_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/splash_screen.dart';
import 'screens/main_navigation.dart';
import 'providers/learning_state_provider.dart';
import 'services/notification_service.dart';
import 'services/crashlytics_service.dart';
import 'database/database_manager.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// Pass to NotificationService for deep-link taps
void _initNotifications() {
  NotificationService.navigatorKey = appNavigatorKey;
  NotificationService.init();
  // Capture scheduling errors so the notification settings screen can
  // surface them to the user after rescheduleAll() completes.
  NotificationService.onScheduleError = (message) {
    debugPrint('NotificationService: $message');
    CrashlyticsService.recordError(
        Exception(message), StackTrace.current,
        context: 'Notification scheduling');
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // ── Crash reporting (must be first so all subsequent errors are captured) ─
  await CrashlyticsService.init();

  await SharedPreferences.getInstance();

  // ── Repair corrupted DB before anything else ──────────────────────────────
  // On emulators with minimal SQLite the DB can become malformed.
  // Deleting it lets the importer rebuild everything while preserving
  // known_words and srs_cards.
  if (await DatabaseManager.isDbCorrupted()) {
    await DatabaseManager.deleteCorruptedDb();
  }

  final themeProvider = ThemeProvider();
  await themeProvider.loadSettings();

  // ── Lightweight service inits are independent — run them in parallel ──────
  await Future.wait([
    TranslationService.init(),
    TranslationLangService.init(),
    WordGlossaryService.init(),
  ]);

  _initNotifications();

  // Wrap runApp in runZonedGuarded to catch unhandled async / zone errors
  // that FlutterError.onError and PlatformDispatcher.instance.onError miss.
  runZonedGuarded(
    () => runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeProvider),
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => DisplayProvider()),
          ChangeNotifierProvider(create: (_) => LearningStateProvider()),
        ],
        child: const QuranAppRoot(),
      ),
    ),
    (error, stack) => CrashlyticsService.recordError(
      error, stack,
      context: 'runZonedGuarded (unhandled app error)',
    ),
  );
}

/// Root widget — always provides MaterialApp so SplashScreen has Directionality
class QuranAppRoot extends StatelessWidget {
  const QuranAppRoot({super.key});

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
      navigatorKey: appNavigatorKey,
      // SplashScreen handles DB init then shows _AppGate
      home: const SplashScreen(child: _AppGate()),
    );
  }
}

class _AppGate extends StatelessWidget {
  const _AppGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
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

class _RestoringScreen extends StatelessWidget {
  const _RestoringScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1B4332),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('﷽', style: TextStyle(fontSize: 36, color: Color(0xFFD4AF37))),
            SizedBox(height: 32),
            CircularProgressIndicator(color: Color(0xFFD4AF37)),
            SizedBox(height: 20),
            Text('Restoring your progress...',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
            SizedBox(height: 8),
            Text('آپ کی پیشرفت بحال ہو رہی ہے',
                style: TextStyle(color: Color(0xFFD4AF37), fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
