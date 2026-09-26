import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quran_vocab/screens/payment_screen.dart';
import '../services/word_progress_service.dart';
import 'word_occurrences_screen.dart';
import '../providers/display_provider.dart';
import 'package:provider/provider.dart';
import 'vocabulary_search_screen.dart';
import 'progress_screen.dart';
import '../providers/learning_state_provider.dart';
import '../services/word_glossary_service.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  // Bumped by MainNavigation whenever the user taps the Vocabulary bottom
  // nav destination — VocabularyScreen stays alive inside an IndexedStack,
  // so its own initState only ever runs once at app startup, before the
  // tab is ever actually visible. Listening for this counter is how the
  // swipe-hint animation knows to replay only when the tab is opened.
  static final ValueNotifier<int> visitNotifier = ValueNotifier<int>(0);
  static void notifyVisited() => visitNotifier.value++;

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;
  List<WordEntry> _allWords = [];
  List<WordEntry> _knownWords = [];
  List<WordEntry> _unknownWords = [];
  LearningStateProvider? _learning;
  bool _isLoading = true;
  String _searchQuery = '';
  // Standalone entries for the always-transparent attached particles are
  // hidden from every tab — their known/unknown status no longer gates
  // compound-word derivation, so listing them separately just adds noise.
  static const _hiddenStandalone = {'و', 'ف', 'ال'};
  String _sortBy = 'freq_desc';
  final TextEditingController _searchController = TextEditingController();
  double _overallPercent = 0;
  int _swipeDemoKey = 0;
  final GlobalKey _progressRingKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 2);
    _tabController.addListener(_onTabChangedForSwipeDemo);
    VocabularyScreen.visitNotifier.addListener(_onScreenVisited);
    _initLoad();
    // Reload when WBW language changes
    WordGlossaryService.langNotifier.addListener(_onLangChanged);
  }

  // Fires only when the user actually taps into the Vocabulary tab from
  // the bottom nav — this is what makes the swipe hint play when the
  // screen becomes visible, instead of once at app startup while hidden.
  void _onScreenVisited() {
    if (!mounted) return;
    if (_tabController.index == 1 || _tabController.index == 2) {
      setState(() => _swipeDemoKey++);
    }
  }

  // Replays the swipe-hint animation on the top card whenever the user
  // lands on the Known or Unknown tab (where swipe-to-mark is available).
  void _onTabChangedForSwipeDemo() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1 || _tabController.index == 2) {
      setState(() => _swipeDemoKey++);
    }
  }

  void _onLangChanged() {
    if (mounted) _loadWords();
  }

  Future<void> _initLoad() async {
    if (!mounted) return;
    // Wait for LearningStateProvider to finish loading from SQLite
    final learning = context.read<LearningStateProvider>();
    if (!learning.isLoaded) {
      await learning.init();
    }
    if (mounted) await _loadWords();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final learning = context.read<LearningStateProvider>();
    if (_learning != learning) {
      _learning?.removeListener(_onLearningChanged);
      _learning = learning;
      _learning!.addListener(_onLearningChanged);
    }
  }

  void _onLearningChanged() {
    if (!mounted || _allWords.isEmpty) return;
    _reclassifyWords();
    _refreshOverallPercent();
  }

  Future<void> _refreshOverallPercent() async {
    final percent = await WordProgressService.getProgressPercent();
    if (mounted) setState(() => _overallPercent = percent);
  }

  void _reclassifyWords() {
    final learning = context.read<LearningStateProvider>();
    final known = <WordEntry>[];
    final unknown = <WordEntry>[];
    for (final w in _allWords) {
      final isNowKnown = learning.isKnown(w.arabic);
      w.isKnown = isNowKnown;
      if (isNowKnown) {
        known.add(w);
      } else {
        unknown.add(w);
      }
    }
    if (mounted) {
      setState(() {
        _knownWords = known;
        _unknownWords = unknown;
      });
    }
  }

  @override
  void dispose() {
    _learning?.removeListener(_onLearningChanged);
    WordGlossaryService.langNotifier.removeListener(_onLangChanged);
    _tabController.removeListener(_onTabChangedForSwipeDemo);
    VocabularyScreen.visitNotifier.removeListener(_onScreenVisited);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWords() async {
    setState(() => _isLoading = true);
    final learning = context.read<LearningStateProvider>();
    final wordFreq = await WordProgressService.getWordFrequencies();
    final percent = await WordProgressService.getProgressPercent();

    final all = wordFreq.entries
        .where((e) => !_hiddenStandalone.contains(e.key))
        .map((e) => WordEntry(
              arabic: e.key,
              originalArabic: e.value.originalArabic.isNotEmpty
                  ? e.value.originalArabic
                  : e.key,
              urdu: e.value.urdu, // keep as urdu field name for compatibility
              frequency: e.value.frequency,
              isKnown: learning.isKnown(e.key),
            ))
        .toList();
    _applySort(all);

    if (mounted) {
      setState(() {
        _allWords = all;
        _knownWords = all.where((w) => w.isKnown).toList();
        _unknownWords = all.where((w) => !w.isKnown).toList();
        _overallPercent = percent;
        _isLoading = false;
      });
    }
  }

  void _applySort(List<WordEntry> list) {
    switch (_sortBy) {
      case 'freq_asc':
        list.sort((a, b) => a.frequency.compareTo(b.frequency));
        break;
      case 'alpha_asc':
        list.sort((a, b) => a.arabic.compareTo(b.arabic));
        break;
      case 'alpha_desc':
        list.sort((a, b) => b.arabic.compareTo(a.arabic));
        break;
      case 'freq_desc':
      default:
        list.sort((a, b) => b.frequency.compareTo(a.frequency));
    }
  }

  List<WordEntry> _filtered(List<WordEntry> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list
        .where((w) => w.arabic.contains(q) || w.urdu.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _markKnown(WordEntry word) async {
    await context.read<LearningStateProvider>().setKnownByClean(word.arabic);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: const Text('✓ یاد ہے'),
      backgroundColor: Colors.green.shade800,
      duration: const Duration(seconds: 3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      action: SnackBarAction(
        label: 'Undo',
        textColor: Colors.white,
        onPressed: () async {
          if (mounted) {
            await context
                .read<LearningStateProvider>()
                .setUnknownByClean(word.arabic);
          }
        },
      ),
    ));
  }

  Future<void> _markUnknown(WordEntry word) async {
    await context.read<LearningStateProvider>().setUnknownByClean(word.arabic);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: const Text('نہیں جانتا'),
      backgroundColor: Colors.grey.shade700,
      duration: const Duration(seconds: 3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      action: SnackBarAction(
        label: 'Undo',
        textColor: Colors.white,
        onPressed: () async {
          if (mounted) {
            await context
                .read<LearningStateProvider>()
                .setKnownByClean(word.arabic);
          }
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leadingWidth: 108,
        leading: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.volunteer_activism, color: Color.fromARGB(255, 250, 248, 248)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaymentScreen()),
              ),
            ),
            _buildHeaderProgressRing(),
          ],
        ),
        title: const Column(
          children: [
            Text('Vocabulary'),
            Text('لغت القرآن',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B4332),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFD4AF37),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: [
            Tab(text: 'All (${_allWords.length})'),
            Tab(text: 'Known (${_knownWords.length})'),
            Tab(text: 'Unknown (${_unknownWords.length})'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const VocabularySearchScreen())),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: Colors.white),
            onSelected: (val) {
              setState(() => _sortBy = val);
              _applySort(_allWords);
              _applySort(_knownWords);
              _applySort(_unknownWords);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'freq_desc', child: Text('Frequency: High to Low')),
              const PopupMenuItem(
                  value: 'freq_asc', child: Text('Frequency: Low to High')),
              const PopupMenuItem(
                  value: 'alpha_asc', child: Text('Alphabetical (A → Z)')),
              const PopupMenuItem(
                  value: 'alpha_desc', child: Text('Alphabetical (Z → A)')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search Arabic or Urdu...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // Swipe hint — only on known/unknown tabs
          AnimatedBuilder(
            animation: _tabController,
            builder: (_, __) {
              if (_tabController.index == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _tabController.index == 1
                      ? 'Swipe right to mark as Forgotten -->>'
                      : '<<-- Swipe left to mark as Remembered ',
                  style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF1B4332)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _WordList(
                        words: _filtered(_allWords),
                        swipeEnabled: false,
                        onTap: (w) => _openOccurrences(w),
                        onMarkKnown: _markKnown,
                        onMarkUnknown: _markUnknown,
                      ),
                      _WordList(
                        words: _filtered(_knownWords),
                        swipeDirection: SwipeDirection.toRight,
                        swipeLabel: 'Forgot',
                        swipeColor: Colors.red,
                        swipeIcon: Icons.close,
                        swipeDemoKey: _swipeDemoKey,
                        onSwipe: _markUnknown,
                        onTap: (w) => _openOccurrences(w),
                        onMarkKnown: _markKnown,
                        onMarkUnknown: _markUnknown,
                      ),
                      _WordList(
                        words: _filtered(_unknownWords),
                        swipeDirection: SwipeDirection.toLeft,
                        swipeLabel: 'Remembered',
                        swipeColor: Colors.green,
                        swipeIcon: Icons.check,
                        swipeDemoKey: _swipeDemoKey,
                        onSwipe: _markKnown,
                        onTap: (w) => _openOccurrences(w),
                        onMarkKnown: _markKnown,
                        onMarkUnknown: _markUnknown,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _openOccurrences(WordEntry word) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => WordOccurrencesScreen(word: word)));
  }

  Widget _buildHeaderProgressRing() {
    return GestureDetector(
      key: _progressRingKey,
      onTap: _openProgressScreen,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  value: (_overallPercent / 100).clamp(0.0, 1.0),
                  strokeWidth: 3,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFD4AF37)),
                ),
              ),
              Text(
                '${_overallPercent.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Finds the ring's exact position on screen, then pushes ProgressScreen
  // with a custom circular-reveal transition that expands outward from
  // that point — matches the effect of the screen "coming out of the logo".
  void _openProgressScreen() {
    final renderBox =
        _progressRingKey.currentContext?.findRenderObject() as RenderBox?;
    Offset center;
    if (renderBox != null && renderBox.attached) {
      final size = renderBox.size;
      final position = renderBox.localToGlobal(Offset.zero);
      center = position + Offset(size.width / 2, size.height / 2);
    } else {
      center = MediaQuery.of(context).size.topCenter(Offset.zero);
    }

    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => const ProgressScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return AnimatedBuilder(
            animation: animation,
            builder: (_, ___) => ClipPath(
              clipper: _CircleRevealClipper(
                center: center,
                fraction: Curves.easeInOutCubic.transform(animation.value),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

// ── Stat Badge ────────────────────────────────────────────────────────────────
// ignore: unused_element
class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBadge(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.white60)),
      ],
    );
  }
}

class WordEntry {
  final String arabic;
  final String originalArabic;
  final String urdu;
  final int frequency;
  bool isKnown;

  WordEntry({
    required this.arabic,
    required this.originalArabic,
    required this.urdu,
    required this.frequency,
    required this.isKnown,
  });
}

enum SwipeDirection { toLeft, toRight }

// ── Word List ─────────────────────────────────────────────────────────────────
class _WordList extends StatelessWidget {
  final List<WordEntry> words;
  final bool swipeEnabled;
  final SwipeDirection? swipeDirection;
  final String? swipeLabel;
  final Color? swipeColor;
  final IconData? swipeIcon;
  final int swipeDemoKey;
  final Function(WordEntry)? onSwipe;
  final Function(WordEntry) onTap;
  final Function(WordEntry) onMarkKnown;
  final Function(WordEntry) onMarkUnknown;

  const _WordList({
    required this.words,
    this.swipeEnabled = true,
    this.swipeDirection,
    this.swipeLabel,
    this.swipeColor,
    this.swipeIcon,
    this.swipeDemoKey = 0,
    this.onSwipe,
    required this.onTap,
    required this.onMarkKnown,
    required this.onMarkUnknown,
  });

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16), 
            Text(
              'Open surahs to discover words',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: words.length,
      itemBuilder: (context, index) {
        final word = words[index];
        final tile = _WordCard(word: word, onTap: () => onTap(word));

        if (!swipeEnabled || swipeDirection == null || onSwipe == null) {
          return tile;
        }

        final dismissible = Dismissible(
          key: Key('${word.arabic}_${word.isKnown}_$index'),
          direction: swipeDirection == SwipeDirection.toRight
              ? DismissDirection.startToEnd
              : DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: swipeColor,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: swipeDirection == SwipeDirection.toRight
                ? Alignment.centerLeft
                : Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (swipeDirection == SwipeDirection.toLeft)
                  Text(swipeLabel!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                if (swipeDirection == SwipeDirection.toLeft)
                  const SizedBox(width: 8),
                Icon(swipeIcon, color: Colors.white, size: 28),
                if (swipeDirection == SwipeDirection.toRight)
                  const SizedBox(width: 8),
                if (swipeDirection == SwipeDirection.toRight)
                  Text(swipeLabel!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
              ],
            ),
          ),
          onDismissed: (_) => onSwipe!(word),
          child: tile,
        );

        // Only the very top card gets the auto-playing swipe hint — it
        // replays whenever swipeDemoKey changes (see
        // _onTabChangedForSwipeDemo in the parent screen).
        if (index == 0) {
          return _TopSwipeHint(
            key: ValueKey('swipe_demo_$swipeDemoKey'),
            toRight: swipeDirection == SwipeDirection.toRight,
            color: swipeColor!,
            icon: swipeIcon!,
            label: swipeLabel!,
            child: dismissible,
          );
        }
        return dismissible;
      },
    );
  }
}

// ── One-shot swipe-hint animation ───────────────────────────────────────────
// Nudges the wrapped card sideways and back once. Wraps the Dismissible
// FROM THE OUTSIDE so it never touches the Dismissible's own drag/dismiss
// gesture logic — purely visual, real swipe-to-mark keeps working exactly
// as before. Giving this widget a new `key` (via swipeDemoKey) makes
// Flutter treat it as a brand-new instance each time, which is what makes
// the animation replay.
class _TopSwipeHint extends StatefulWidget {
  final Widget child;
  final bool toRight;
  final Color color;
  final IconData icon;
  final String label;
  const _TopSwipeHint({
    super.key,
    required this.child,
    required this.toRight,
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  State<_TopSwipeHint> createState() => _TopSwipeHintState();
}

class _TopSwipeHintState extends State<_TopSwipeHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _slide = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOutCubic)),
          weight: 40),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 15),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeInCubic)),
          weight: 45),
    ]).animate(_ctrl);
    // Small delay so it plays after the tab-switch transition settles.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mirrors the exact background Container from _WordList's real
    // Dismissible — same margin, color, radius, alignment, padding, and
    // the same Icon+Text row/order/style — so the hint looks identical to
    // an actual swipe reveal, just played automatically once.
    return AnimatedBuilder(
      animation: _slide,
      builder: (_, child) {
        final dx = (widget.toRight ? 1 : -1) * 52.0 * _slide.value;
        return Stack(
          children: [
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment:
                    widget.toRight ? Alignment.centerLeft : Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!widget.toRight)
                      Text(widget.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    if (!widget.toRight) const SizedBox(width: 8),
                    Icon(widget.icon, color: Colors.white, size: 28),
                    if (widget.toRight) const SizedBox(width: 8),
                    if (widget.toRight)
                      Text(widget.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                  ],
                ),
              ),
            ),
            Transform.translate(offset: Offset(dx, 0), child: child),
          ],
        );
      },
      child: widget.child,
    );
  }
}

// ── Word Card ─────────────────────────────────────────────────────────────────
class _WordCard extends StatelessWidget {
  final WordEntry word;
  final VoidCallback onTap;

  const _WordCard({required this.word, required this.onTap});

  TextStyle _arabicStyle(BuildContext context, double size) {
    final d = context.read<DisplayProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : const Color(0xFF1A1A1A);
    switch (d.arabicFont) {
      case 'indopak':
        return TextStyle(
            fontFamily: 'IndoPak', fontSize: size, color: color, height: 1.8);
      case 'noorehuda':
        return TextStyle(
            fontFamily: 'NoorehudaFont',
            fontSize: size,
            color: color,
            height: 1.8);
      default:
        return GoogleFonts.amiri(
            fontSize: size, color: color, height: 1.8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1A2E1F), const Color(0xFF0D1B12)]
                : [Colors.white, const Color(0xFFF8F4E8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: word.isKnown
                ? Colors.green.withValues(alpha: 0.6)
                : const Color(0xFFD4AF37).withValues(alpha: 0.4),
            width: word.isKnown ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Frequency badge (left)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? const Color(0xFFD4AF37).withValues(alpha: 0.15)
                      : const Color(0xFF1B4332).withValues(alpha: 0.1),
                  border: Border.all(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.5)),
                ),
                child: Center(
                  child: Text(
                    '${word.frequency}×',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? const Color(0xFFD4AF37)
                          : const Color(0xFF1B4332),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Arabic word + Urdu meaning (center)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (word.urdu.isNotEmpty) ...[
                          Text(
                            word.urdu,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontFamily: 'JameelNoori',
                              fontSize: 20, // for Urdu text
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          word.originalArabic,
                          textDirection: TextDirection.rtl,
                          style: _arabicStyle(context, 26),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Known indicator (right)
              if (word.isKnown)
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 18),

                )
              else
                const SizedBox(width: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Circular-reveal clip path ────────────────────────────────────────────────
// Grows a circle from [center] out to the farthest screen corner as
// [fraction] goes 0 → 1, so the incoming page appears to emerge from a
// single point (the tapped progress ring) instead of sliding in normally.
class _CircleRevealClipper extends CustomClipper<Path> {
  final Offset center;
  final double fraction;
  _CircleRevealClipper({required this.center, required this.fraction});

  @override
  Path getClip(Size size) {
    final radius = _maxRadius(size) * fraction;
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  double _maxRadius(Size size) {
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    double maxDist = 0;
    for (final c in corners) {
      final d = (c - center).distance;
      if (d > maxDist) maxDist = d;
    }
    return maxDist;
  }

  @override
  bool shouldReclip(covariant _CircleRevealClipper oldClipper) =>
      oldClipper.fraction != fraction || oldClipper.center != center;
}