import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'surah_list_screen.dart';
import 'vocabulary_screen.dart';
import 'profile_settings_screen.dart';
import '../providers/learning_state_provider.dart';
import '../services/announcement_service.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  bool _learningInitDone = false;

  bool _waitingForSecondBack = false;
  Timer? _backPressTimer;

  final List<Widget> _screens = const [
    SurahListScreen(),
    VocabularyScreen(),
    ProfileSettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _deferredInit());
    // Independent of the above — checks Firestore for any live announcements
    // and shows them over whatever screen is active. Fully self-contained
    // and silently no-ops on failure, so it can never affect app startup or
    // the back-button logic below.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => AnnouncementService.checkAndShow(context));
  }

  Future<void> _deferredInit() async {
    if (!_learningInitDone && mounted) {
      _learningInitDone = true;
      await context.read<LearningStateProvider>().init();
    }
  }

  void _handleBackPressed() {
    // First back press
    if (!_waitingForSecondBack) {
      setState(() {
        _waitingForSecondBack = true;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
          ),
        );

      _backPressTimer?.cancel();

      _backPressTimer = Timer(
        const Duration(seconds: 2),
        () {
          if (!mounted) return;

          setState(() {
            _waitingForSecondBack = false;
          });
        },
      );

      return;
    }

    // Second back press within 2 seconds
    _backPressTimer?.cancel();

    // Close the application.
    // This is intentionally called ONLY on the second back press.
    SystemNavigator.pop();
  }

  @override
  void dispose() {
    _backPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;

        _handleBackPressed();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) {
            setState(() {
              _currentIndex = i;
            });
          },
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
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}