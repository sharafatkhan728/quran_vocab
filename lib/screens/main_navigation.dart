import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'surah_list_screen.dart';
import 'vocabulary_screen.dart';
import 'profile_settings_screen.dart';
import '../providers/learning_state_provider.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  bool _learningInitDone = false;
  int _backPressCount = 0;
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
  }

  Future<void> _deferredInit() async {
    if (!_learningInitDone && mounted) {
      _learningInitDone = true;
      await context.read<LearningStateProvider>().init();
    }
  }

  Future<bool> _onBackPressed() async {
    if (_backPressCount == 0) {
      setState(() => _backPressCount = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
      _backPressTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _backPressCount = 0);
      });
      return false;
    }
    _backPressTimer?.cancel();
    return true;
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
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onBackPressed();
        if (!mounted) return;
        if (shouldPop) Navigator.of(context).pop();
      },
      child: Scaffold(
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
