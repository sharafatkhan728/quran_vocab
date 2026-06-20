import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/word_progress_service.dart';
import '../services/quran_preloader_service.dart';
import 'word_occurrences_screen.dart';
import '../providers/display_provider.dart';
import 'package:provider/provider.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<WordEntry> _allWords = [];
  List<WordEntry> _knownWords = [];
  List<WordEntry> _unknownWords = [];
  bool _isLoading = true;
  bool _isPreloading = false;
  int _preloadProgress = 0;
  String _searchQuery = '';
  String _sortBy = 'frequency';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initLoad();
  }

  Future<void> _initLoad() async {
    final sw = Stopwatch()..start(); //<<<<<
    final isLoaded = await QuranPreloaderService.isFullyLoaded();
    if (!isLoaded) {
      setState(() => _isPreloading = true);
      await QuranPreloaderService.loadAllSurahs(
        onProgress: (surahId, total) async {
          if (mounted) {
            setState(() => _preloadProgress = surahId);
            // Refresh word list every 10 surahs so user sees words appearing
            if (surahId % 10 == 0) await _loadWords();
          }
        },
      );
      if (mounted) setState(() => _isPreloading = false);
    }
    await _loadWords();
    //<<<<<<<
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWords() async {

    final sw = Stopwatch()..start();
    
    setState(() => _isLoading = true);
    final knownSet = await WordProgressService.getAllKnownWords();
    final wordFreq = await WordProgressService.getWordFrequencies();

    final all = wordFreq.entries
        .map((e) => WordEntry(
              arabic: e.key,
              originalArabic: e.value.originalArabic.isNotEmpty
                  ? e.value.originalArabic
                  : e.key,
              urdu: e.value.urdu,
              frequency: e.value.frequency,
              isKnown: knownSet.contains(e.key),
            ))
        .toList();

    _applySort(all);

    if (mounted) {
      setState(() {
        _allWords = all;
        _knownWords = all.where((w) => w.isKnown).toList();
        _unknownWords = all.where((w) => !w.isKnown).toList();
        _isLoading = false;
      });
    }
  }

  void _applySort(List<WordEntry> list) {
    if (_sortBy == 'frequency') {
      list.sort((a, b) => b.frequency.compareTo(a.frequency));
    } else {
      list.sort((a, b) => a.arabic.compareTo(b.arabic));
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
    await WordProgressService.markAsKnown(word.arabic);
    WordProgressService.recalculateAllSurahProgress(); // fire and forget
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    final controller = messenger.showSnackBar(SnackBar(
      content: const Text('✓ یاد ہے — معنی چھپا دیا'),
      backgroundColor: Colors.green.shade800,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Undo',
        textColor: Colors.white,
        onPressed: () async {
          await WordProgressService.markAsUnknown(word.arabic);
          WordProgressService.recalculateAllSurahProgress(); // fire and forget
          if (mounted) await _loadWords();
        },
      ),
    ));

    // Auto dismiss and reload AFTER snackbar closes naturally
    controller.closed.then((reason) {
      if (reason != SnackBarClosedReason.action && mounted) {
        _loadWords();
      }
    });
  }

  Future<void> _markUnknown(WordEntry word) async {
    await WordProgressService.markAsUnknown(word.arabic);
    WordProgressService.recalculateAllSurahProgress(); // fire and forget
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    final controller = messenger.showSnackBar(SnackBar(
      content: const Text('معنی واپس آ گیا'),
      backgroundColor: Colors.grey.shade700,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Undo',
        textColor: Colors.white,
        onPressed: () async {
          await WordProgressService.markAsKnown(word.arabic);
          WordProgressService.recalculateAllSurahProgress(); // fire and forget
          if (mounted) await _loadWords();
        },
      ),
    ));

    controller.closed.then((reason) {
      if (reason != SnackBarClosedReason.action && mounted) {
        _loadWords();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
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
                  value: 'frequency', child: Text('By Frequency')),
              const PopupMenuItem(
                  value: 'alphabetical', child: Text('Alphabetical')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            color: const Color(0xFF1B4332),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatBadge(
                    label: 'Total Unique',
                    value: '14,870',
                    color: Colors.white70),
                _StatBadge(
                    label: 'Discovered',
                    value: '${_allWords.length}',
                    color: Colors.amber),
                _StatBadge(
                    label: 'Known',
                    value: '${_knownWords.length}',
                    color: Colors.greenAccent),
              ],
            ),
          ),
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
                      ? '← Swipe right to mark as Forgotten'
                      : 'Swipe left to mark as Remembered →',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
          Expanded(
            child: _isPreloading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Loading Quran vocabulary...',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 24),
                          LinearProgressIndicator(
                            value: _preloadProgress / 114,
                            backgroundColor: Colors.grey.shade300,
                            valueColor:
                                const AlwaysStoppedAnimation(Color(0xFF1B4332)),
                            minHeight: 8,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Surah $_preloadProgress of 114',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This happens only once',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  )
                : _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFF1B4332)))
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
}

// ── Stat Badge ────────────────────────────────────────────────────────────────
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

        return Dismissible(
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
      },
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
        return GoogleFonts.amiriQuran(
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
                  color: const Color(0xFF1B4332).withValues(alpha: 0.1),
                  border: Border.all(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.5)),
                ),
                child: Center(
                  child: Text(
                    '${word.frequency}×',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B4332),
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
                              fontSize: 13,
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
