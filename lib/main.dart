import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'screens/surah_list_screen.dart';
import 'screens/vocabulary_screen.dart';
import 'screens/progress_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/user_provider.dart';
import 'providers/display_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/auth_screen.dart';
import 'screens/profile_settings_screen.dart';
import 'services/translation_service.dart';
import 'services/word_glossary_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/splash_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await SharedPreferences.getInstance();

  final themeProvider = ThemeProvider();
  await themeProvider.loadSettings();

  // Heavy services still needed by surah reader until fully migrated
  await TranslationService.init();
  await WordGlossaryService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => DisplayProvider()),
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

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    SurahListScreen(),
    VocabularyScreen(),
    ProgressScreen(),
    ProfileSettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: Theme.of(context).cardColor,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Quran',
          ),
          NavigationDestination(
            icon: Icon(Icons.abc_outlined),
            selectedIcon: Icon(Icons.abc),
            label: 'Vocabulary',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
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