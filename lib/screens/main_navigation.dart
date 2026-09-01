import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'surah_list_screen.dart';
import 'vocabulary_screen.dart';
// import 'progress_screen.dart';
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

  final List<Widget> _screens = const [
    SurahListScreen(),
    VocabularyScreen(),
    // ProgressScreen(),
    ProfileSettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Defer LearningStateProvider.init() until after the splash screen has
    // completed, so the UI renders immediately instead of waiting for the
    // full vocab_words table scan (~15 K rows) on every launch.
    WidgetsBinding.instance.addPostFrameCallback((_) => _deferredInit());
  }

  Future<void> _deferredInit() async {
    if (!_learningInitDone && mounted) {
      _learningInitDone = true;
      await context.read<LearningStateProvider>().init();
    }
  }

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
          // NavigationDestination(
          //   icon: Icon(Icons.bar_chart_outlined),
          //   selectedIcon: Icon(Icons.bar_chart),
          //   label: 'Progress',
          // ),
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
