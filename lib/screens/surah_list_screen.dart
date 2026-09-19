// ignore_for_file: curly_braces_in_flow_control_structures, unused_local_variable

import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;
import 'package:quran_vocab/screens/payment_screen.dart';
import '../data/surah_data.dart';
import '../models/surah.dart';
import '../services/word_progress_service.dart';
import '../repositories/content_repository.dart';
import 'surah_reader_screen.dart';
import 'progress_screen.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/surah_search_delegate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'flashcard_screen.dart';
import '../providers/learning_state_provider.dart';
import '../database/database_manager.dart';

class SurahListScreen extends StatefulWidget {
  const SurahListScreen({super.key});

  @override
  State<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends State<SurahListScreen>
    with SingleTickerProviderStateMixin {
  // Built once instead of calling quran.getSurahName()/getSurahNameArabic()/
  // getVerseCount() repeatedly per card on every rebuild (scroll, theme
  // toggle, learning-state change) — cuts ~342 package calls down to 114,
  // done a single time up front.
  final List<Surah> _surahs = buildSurahList();
  double _totalProgress = 0;
  Map<int, double> _surahProgress = {};
  Map<int, int> _lastReadAyahs = {};
  List<Map<String, dynamic>> _bookmarks = [];
  int _knownCount = 0;
  int _streak = 0;

  late AnimationController _barCtrl;
  late Animation<double> _barAnim;

  LearningStateProvider? _learning;

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _barAnim = Tween<double>(begin: 0, end: 0).animate(
        CurvedAnimation(parent: _barCtrl, curve: Curves.easeOutCubic));
    _loadProgress();
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
    if (mounted) _loadProgress();
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    _learning?.removeListener(_onLearningChanged);
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final progressPercent = await WordProgressService.getProgressPercent();
    final sp = await WordProgressService.getAllSurahProgress();

    // Known word count from LearningStateProvider
    // ignore: use_build_context_synchronously
    final knownCount = context.read<LearningStateProvider>().knownCount;

    // Streak: count consecutive days with words_learned > 0
    int streak = 0;
    try {
      final db = await DatabaseManager.db;
      final today = DateTime.now();
      for (int d = 0; d < 365; d++) {
        final day = today.subtract(Duration(days: d));
        final key =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        final rows = await db.query('daily_stats',
            where: 'date_key = ?', whereArgs: [key], limit: 1);
        if (rows.isNotEmpty && (rows.first['words_learned'] as int? ?? 0) > 0) {
          streak++;
        } else {
          break;
        }
      }
    } catch (_) {}

    // ── Last-read positions from SQLite reading_progress ──────────────────
    final Map<int, int> lastRead = {};
    for (int i = 1; i <= 114; i++) {
      final ayah = await ContentRepository.getLastReadAyah(i);
      if (ayah > 1) lastRead[i] = ayah;
    }
    if (mounted) setState(() => _lastReadAyahs = lastRead);

    // ── Bookmarks from SQLite bookmarks table ─────────────────────────────
    final bmarks = await ContentRepository.getAllBookmarks();
    if (mounted) setState(() => _bookmarks = bmarks);

    if (mounted) {
      setState(() {
        _totalProgress = progressPercent;
        _surahProgress = sp;
        _knownCount = knownCount;
        _streak = streak;
      });
      // Animate bar to new value
      _barAnim = Tween<double>(begin: _barAnim.value, end: progressPercent / 100)
          .animate(CurvedAnimation(parent: _barCtrl, curve: Curves.easeOutCubic));
      _barCtrl
        ..reset()
        ..forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.volunteer_activism, color: Color.fromARGB(255, 255, 254, 253)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PaymentScreen()),
            ),
          ),        
        title: const Column(
          children: [
            Text('القرآن الكريم', style: TextStyle(fontSize: 22)),
            Text('Quran Kalima',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B4332),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => showSearch(
              context: context,
              delegate: SurahSearchDelegate(
                onSurahSelected: (surahId, ayahNumber) async {
                  final surah = Surah(
                    id: surahId,
                    englishName: quran.getSurahName(surahId),
                    arabicName: quran.getSurahNameArabic(surahId),
                    urduName: quran.getSurahName(surahId),
                    verseCount: quran.getVerseCount(surahId),
                  );
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SurahReaderScreen(
                        surah: surah,
                        jumpToAyahRequested: ayahNumber,
                      ),
                    ),
                  );
                  await Future.delayed(const Duration(milliseconds: 300));
                  _loadProgress();
                },
              ),
            ),
          ),
          Consumer<ThemeProvider>(
            builder: (context, theme, _) => IconButton(
              icon: Icon(theme.isDark ? Icons.light_mode : Icons.dark_mode),
              tooltip: 'Toggle theme',
              onPressed: () => theme.toggleTheme(),
            ),
          ),
IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProgressScreen()),
            ).then((_) => _loadProgress()),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_bookmarks.isNotEmpty)
                Container(
                  color: const Color(0xFF1B4332),
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bookmarks',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 36,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _bookmarks.length,
                          itemBuilder: (_, i) {
                            final b = _bookmarks[i];
                            return GestureDetector(
                              onTap: () async {
                                final surah = Surah(
                                  id: b['surahId'],
                                  englishName: quran.getSurahName(b['surahId']),
                                  arabicName:
                                      quran.getSurahNameArabic(b['surahId']),
                                  urduName: quran.getSurahName(b['surahId']),
                                  verseCount: quran.getVerseCount(b['surahId']),
                                );
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => SurahReaderScreen(
                                              surah: surah,
                                              jumpToAyahRequested: b['ayahId'],
                                            )));
                                _loadProgress();
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4AF37)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                      color: const Color(0xFFD4AF37)
                                          .withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  '${b['name']} ${b['ayahId']}',
                                  style: const TextStyle(
                                      color: Color(0xFFD4AF37),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              _buildProgressHeader(context),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                  itemCount: 114,
                  itemBuilder: (context, index) {
                    final surah = _surahs[index];
                    final id = surah.id;
                    return _SurahCard(
                      surah: surah,
                      surahProgress: _surahProgress[id] ?? 0,
                      lastReadAyah: _lastReadAyahs[id],
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SurahReaderScreen(
                              surah: surah,
                              jumpToAyah: _lastReadAyahs[id],
                            ),
                          ),
                        );
                        await Future.delayed(const Duration(milliseconds: 300));
                        _loadProgress();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          // Flashcard Entry Button
          Positioned(
            bottom: 20,
            left: 40,
            right: 40,
            child: _FlashcardEntryButton(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FlashcardScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressHeader(BuildContext context) {
    // ── Level system ──────────────────────────────────────────────────────
    final (levelEn, levelAr, levelColor) = _getLevel(_totalProgress);

    // ── Milestone detection ───────────────────────────────────────────────
    final milestone = _getMilestone(_totalProgress);

    // ── Comparison text ───────────────────────────────────────────────────
    final comparisonText = _getComparisonText(_totalProgress, _knownCount);

    return Container(
      color: const Color(0xFF1B4332),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: Level badge + streak + comparison ──────────────────
          Row(
            children: [
              // Level badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: levelColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: levelColor.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(levelAr,
                        style: TextStyle(
                            fontSize: 13,
                            color: levelColor,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 5),
                    Text(levelEn,
                        style: TextStyle(
                            fontSize: 10,
                            color: levelColor.withValues(alpha: 0.85))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Streak
              if (_streak > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.5)),
                  ),
                  child: Text('🔥 $_streak days',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600)),
                ),
              const Spacer(),
              // Comparison text
              Text(comparisonText,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.white38)),
            ],
          ),

          const SizedBox(height: 10),

          // ── Row 2: Percentage + known count ───────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_totalProgress.toStringAsFixed(1)}% of Quran',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '$_knownCount words known',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Row 3: Animated gradient bar ──────────────────────────────
          AnimatedBuilder(
            animation: _barAnim,
            builder: (_, __) {
              return Stack(
                children: [
                  // Background track
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  // Filled gradient bar
                  FractionallySizedBox(
                    widthFactor: _barAnim.value.clamp(0.0, 1.0),
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFD4AF37),
                            const Color(0xFF2ECC71),
                          ],
                          stops: const [0.0, 1.0],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2ECC71).withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Milestone tick marks
                  ...[10, 25, 50, 75].map((pct) {
                    return FractionallySizedBox(
                      widthFactor: pct / 100,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: 2,
                          height: 10,
                          color: Colors.white24,
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),

          // ── Row 4: Milestone badge (shown when at/past a milestone) ───
          if (milestone != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFD4AF37).withValues(alpha: 0.15),
                    const Color(0xFF1B4332),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Text(milestone.$1,
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(milestone.$2,
                            style: const TextStyle(
                                color: Color(0xFFD4AF37),
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                        Text(milestone.$3,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Level system ─────────────────────────────────────────────────────────
  (String, String, Color) _getLevel(double pct) {
    if (pct >= 75) return ('Master', 'متقدم', const Color(0xFFD4AF37));
    if (pct >= 50) return ('Advanced', 'متوسط متقدم', Colors.green.shade400);
    if (pct >= 25) return ('Intermediate', 'متوسط', Colors.teal.shade300);
    if (pct >= 10) return ('Beginner', 'مبتدئ', Colors.blue.shade300);
    return ('Starter', 'مبتدئ', Colors.grey.shade400);
  }

  // ── Milestone detection ───────────────────────────────────────────────────
  // Returns (emoji, title, arabic phrase) for the nearest passed milestone
  (String, String, String)? _getMilestone(double pct) {
    if (pct >= 75) return ('🏆', 'Three-Quarters of Quran!', 'ماشاء اللہ — أحسنت!');
    if (pct >= 50) return ('⭐', 'Half of Quran!', 'مبارك — نصف القرآن!');
    if (pct >= 25) return ('🌟', 'Quarter of Quran!', 'احسنت — ربع القرآن!');
    if (pct >= 10) return ('✨', 'First Milestone!', 'جزاك الله خيراً');
    return null;
  }

  // ── Comparison text ───────────────────────────────────────────────────────
  String _getComparisonText(double pct, int known) {
    if (known == 0) return 'Start learning today';
    if (pct >= 50) return 'Top learner 🏅';
    if (pct >= 25) return 'Better than most';
    if (pct >= 10) return 'Great progress!';
    return '$known words and counting';
  }
}

class _SurahCard extends StatefulWidget {
  final Surah surah;
  final double surahProgress;
  final int? lastReadAyah;
  final VoidCallback onTap;
  const _SurahCard({
    required this.surah,
    required this.surahProgress,
    required this.onTap,
    this.lastReadAyah,
  });

  int get id => surah.id;

  @override
  State<_SurahCard> createState() => _SurahCardState();
}

class _SurahCardState extends State<_SurahCard>
    with SingleTickerProviderStateMixin {
  static const _gold = Color(0xFFD4AF37);
  static const _green = Color(0xFF1B4332);

  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: Duration(
            milliseconds:
                300 + widget.id * 8 > 800 ? 800 : 300 + widget.id * 8));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    if (widget.id <= 20) {
      Future.delayed(Duration(milliseconds: widget.id * 40), () {
        if (mounted) _ctrl.forward();
      });
    } else {
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // getPlaceOfRevelation has no equivalent field on Surah — this one stays
    // a direct package call since it's the only per-card data not cached.
    final revelation = quran.getPlaceOfRevelation(widget.id);
    final isMakki = revelation.toLowerCase().contains('mecca') ||
        revelation.toLowerCase().contains('makk');

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1A2E1F), const Color(0xFF0F1F15)]
                    : [Colors.white, const Color(0xFFFBF8F0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: widget.surahProgress >= 100
                    ? _gold.withValues(alpha: 0.7)
                    : _gold.withValues(alpha: 0.15),
                width: widget.surahProgress >= 100 ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.3)
                      : _green.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(16),
                splashColor: _gold.withValues(alpha: 0.1),
                highlightColor: _gold.withValues(alpha: 0.05),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      // Progress circle
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: widget.surahProgress / 100,
                              strokeWidth: 4,
                              backgroundColor:
                                  Colors.grey.withValues(alpha: 0.2),
                              valueColor: AlwaysStoppedAnimation(
                                widget.surahProgress >= 100
                                    ? _gold
                                    : _green.withValues(alpha: 0.7),
                              ),
                            ),
                            Text(
                              '${widget.surahProgress.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: widget.surahProgress >= 100
                                    ? _gold
                                    : (isDark ? Colors.white70 : _green),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Names + info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '${widget.id}. ',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.grey.shade600,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              widget.surah.englishName,
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w700,
                                                color: isDark
                                                    ? Colors.white
                                                    : const Color(0xFF1A1A1A),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isMakki
                                                  ? Colors.orange
                                                      .withValues(alpha: 0.12)
                                                  : Colors.blue
                                                      .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isMakki
                                                    ? Colors.orange
                                                        .withValues(alpha: 0.4)
                                                    : Colors.blue
                                                        .withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: Text(
                                              isMakki ? 'Makki' : 'Madani',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                                color: isMakki
                                                    ? Colors.orange.shade700
                                                    : Colors.blue.shade700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${widget.surah.verseCount} ayahs',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: isDark
                                                    ? Colors.white54
                                                    : Colors.grey.shade500),
                                          ),
                                          // Last read indicator
                                          if (widget.lastReadAyah != null) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              'Last: ${widget.lastReadAyah}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFFD4AF37),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Arabic name
                                Text(
                                  quran.getSurahNameArabic(widget.id),
                                  textDirection: TextDirection.rtl,
                                  style: GoogleFonts.amiri(
                                    fontSize: 22,
                                    color: isDark ? Colors.white : _green,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right,
                          color: _gold.withValues(alpha: 0.5), size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlashcardEntryButton extends StatefulWidget {
  final VoidCallback onTap;
  const _FlashcardEntryButton({required this.onTap});

  @override
  State<_FlashcardEntryButton> createState() => _FlashcardEntryButtonState();
}

class _FlashcardEntryButtonState extends State<_FlashcardEntryButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _glow = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: SweepGradient(
            transform: GradientRotation(_glow.value * 3.14 * 2),
            colors: const [
              Color(0xFFD4AF37),
              Color(0xFFFFF0A0),
              Color(0xFFD4AF37),
              Color(0xFFB8860B),
              Color(0xFFD4AF37),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37)
                  .withValues(alpha: 0.3 + _glow.value * 0.3),
              blurRadius: 16 + _glow.value * 8,
              spreadRadius: 1,
            ),
          ],
        ),
        padding: const EdgeInsets.all(2),
        child: child,
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🃏', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              const Text('Flash Card Learning',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('SRS',
                    style: TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
