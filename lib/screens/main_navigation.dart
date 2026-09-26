import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'surah_list_screen.dart';
import 'vocabulary_screen.dart';
import 'profile_settings_screen.dart';
import '../providers/learning_state_provider.dart';
import '../services/analytics_service.dart';
import '../services/announcement_service.dart';
import '../services/surah_prefetch_service.dart';
import '../services/sync_service.dart';
import '../services/leaderboard_service.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _learningInitDone = false;

  bool _waitingForSecondBack = false;
  Timer? _backPressTimer;

  final List<Widget> _screens = const [
    SurahListScreen(),
    VocabularyScreen(),
    ProfileSettingsScreen(),
  ];

  static const _tabNames = ['Quran', 'Vocabulary', 'Profile'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _deferredInit());
    // Tab switches use IndexedStack + setState, not Navigator.push, so the
    // global NavigatorObserver in main.dart never sees them — log the
    // initial tab explicitly here.
    unawaited(AnalyticsService.logScreenView(_tabNames[_currentIndex]));
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
    // Silently pre-builds every surah's word data in the background so
    // opening any surah later is instant. Delayed slightly so it never
    // competes with the very first frames rendering, and runs with its own
    // internal pauses so it stays invisible to the user throughout.
    Future.delayed(const Duration(seconds: 2), () {
      unawaited(SurahPrefetchService.start());
    });
    // Leaderboard sync — throttled internally to min 10 min gap, safe to
    // call this often (e.g. every 15 min while app is foreground).
    LeaderboardService.scheduleSync();
    Timer.periodic(const Duration(minutes: 15), (_) {
      if (mounted) LeaderboardService.scheduleSync();
    });
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SyncService.scheduleSyncUp();
      LeaderboardService.scheduleSync();
    }
  }

  @override
  void dispose() {
    _backPressTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // ignore: deprecated_member_use
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
            unawaited(AnalyticsService.logScreenView(_tabNames[i]));
            if (i == 1) VocabularyScreen.notifyVisited();
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