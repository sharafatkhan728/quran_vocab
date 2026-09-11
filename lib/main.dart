import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
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

  // ── Firebase App Check ────────────────────────────────────────────────────
  // Wrap in try/catch: AndroidProvider.playIntegrity requires Google Play
  // Integrity API which some devices (Chinese OEMs, custom ROMs) lack.
  // If activation fails we continue without App Check rather than crashing
  // before runApp() — which would produce a black screen in release mode.
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
    );
  } catch (e) {
    debugPrint('FirebaseAppCheck activation skipped: $e');
  }

  // ── Crash reporting (must be first so all subsequent errors are captured) ─
  await CrashlyticsService.init();

  await SharedPreferences.getInstance();

  final themeProvider = ThemeProvider();
  await themeProvider.loadSettings();

  // ── Lightweight service inits are independent — run them in parallel ──────
  await Future.wait([
    TranslationService.init(),
    TranslationLangService.init(),
    WordGlossaryService.init(),
  ]);

  _initNotifications();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => DisplayProvider()),
        ChangeNotifierProvider(create: (_) => LearningStateProvider()),
      ],
      child: const QuranAppRoot(),
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
          // Go straight to the app. Cloud restore (if any) runs quietly in
          // the background via UserProvider/SyncService — no blocking
          // "Restoring your progress..." screen. LearningStateProvider and
          // any relevant UI simply refresh themselves via notifyListeners()
          // once the restore finishes, through SyncService.onSyncDownComplete.
          return const MainNavigation();
        }
        return const AuthScreen();
      },
    );
  }
}