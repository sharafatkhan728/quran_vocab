// ignore_for_file: curly_braces_in_flow_control_structures, unused_local_variable

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;
import 'package:quran_vocab/providers/user_provider.dart';
import 'package:quran_vocab/screens/payment_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../services/surah_list_cache.dart';
import '../data/juz_manzil_data.dart';

enum SurahListViewMode { surah, juz, manzil }

class SurahListScreen extends StatefulWidget {
  const SurahListScreen({super.key});

  @override
  State<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends State<SurahListScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _dueTodayCount = 0;
  Set<int> _favorites = {};
  static const String _favKey = 'favorite_surahs';
  SurahListViewMode _viewMode = SurahListViewMode.surah;

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
    WidgetsBinding.instance.addObserver(this);
    _barCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _barAnim = Tween<double>(begin: 0, end: 0)
        .animate(CurvedAnimation(parent: _barCtrl, curve: Curves.easeOutCubic));
    // Show yesterday's last-known numbers instantly from disk while the
    // real SQLite queries run in the background — so this screen never
    // starts from a blank/0% state on a fresh app launch.
    _loadCachedSnapshot();
    _loadProgress();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_favKey) ?? [];
    if (mounted) {
      setState(() {
        _favorites = ids.map((e) => int.tryParse(e) ?? 0).toSet();
      });
    }
  }

  Future<void> _toggleFavorite(int surahId) async {
    setState(() {
      if (_favorites.contains(surahId)) {
        _favorites.remove(surahId);
      } else {
        _favorites.add(surahId);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _favKey, _favorites.map((e) => '$e').toList());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // Best-effort final save of whatever this screen currently holds —
      // covers the case where a recent toggle's own save is still
      // in-flight when the app gets backgrounded/killed.
      unawaited(_saveCachedSnapshot());
    }
  }

  Future<void> _loadCachedSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(SurahListCache.cacheKey);
      if (raw == null || !mounted) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _totalProgress = (data['totalProgress'] as num?)?.toDouble() ?? 0;
        _knownCount = data['knownCount'] as int? ?? 0;
        _streak = data['streak'] as int? ?? 0;
        _dueTodayCount = data['dueTodayCount'] as int? ?? 0;
        final sp = (data['surahProgress'] as Map?) ?? {};
        _surahProgress = sp.map(
            (k, v) => MapEntry(int.parse(k as String), (v as num).toDouble()));
        final lr = (data['lastReadAyahs'] as Map?) ?? {};
        _lastReadAyahs =
            lr.map((k, v) => MapEntry(int.parse(k as String), v as int));
        final bm = (data['bookmarks'] as List?) ?? [];
        _bookmarks =
            bm.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
      // Pre-fill the progress bar at its cached value (no animating up
      // from 0) — the real animation still plays once fresh data arrives.
      _barAnim =
          Tween<double>(begin: _totalProgress / 100, end: _totalProgress / 100)
              .animate(_barCtrl);
    } catch (_) {
      // Missing/corrupt cache — harmless, _loadProgress() fills it fresh.
    }
  }

  Future<void> _saveCachedSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'totalProgress': _totalProgress,
        'knownCount': _knownCount,
        'streak': _streak,
        'dueTodayCount': _dueTodayCount,
        'surahProgress': _surahProgress.map((k, v) => MapEntry('$k', v)),
        'lastReadAyahs': _lastReadAyahs.map((k, v) => MapEntry('$k', v)),
        'bookmarks': _bookmarks,
      };
      await prefs.setString(SurahListCache.cacheKey, jsonEncode(data));
    } catch (_) {
      // Non-fatal — worst case next launch just rebuilds from DB again.
    }
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
    if (!mounted) return;
    // Fast path first: LearningStateProvider.knownCount is already an
    // in-memory value (no DB query), so update + persist it immediately.
    // This is what guarantees the disk cache reflects a tap even if the
    // app is killed a split-second later — before the fuller reload below
    // (which needs several sequential DB queries for %, per-surah
    // breakdown, streak, etc.) has a chance to finish.
    final learning = context.read<LearningStateProvider>();
    setState(() => _knownCount = learning.knownCount);
    unawaited(_saveCachedSnapshot());

    // Slow path: full recompute for the parts that DO need DB queries.
    _loadProgress();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _barCtrl.dispose();
    _learning?.removeListener(_onLearningChanged);
    super.dispose();
  }

  Future<int> _loadDueTodayCount() async {
    try {
      final db = await DatabaseManager.db;
      final sessionRows = await db.query('user_meta',
          where: 'key = ?', whereArgs: ['srs_total_sessions'], limit: 1);
      final currentSession = sessionRows.isEmpty
          ? 0
          : int.tryParse(sessionRows.first['value'] as String) ?? 0;

      final dueRows = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM srs_cards
      WHERE is_deleted = 0 AND total_reviews > 0 AND next_review_session <= ?
    ''', [currentSession]);
      final due = (dueRows.first['cnt'] as int?) ?? 0;

      final failedRows = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM srs_cards
      WHERE is_deleted = 0 AND fail_count > 0 AND stage = 0 AND next_review_session <= ?
    ''', [currentSession]);
      final failed = (failedRows.first['cnt'] as int?) ?? 0;

      final today = DateTime.now();
      final todayKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final todayRows = await db.query('daily_stats',
          where: 'date_key = ?', whereArgs: [todayKey], limit: 1);
      final learnedToday = todayRows.isEmpty
          ? 0
          : (todayRows.first['words_learned'] as int? ?? 0);

      // ignore: use_build_context_synchronously
      final goal = mounted ? context.read<UserProvider>().dailyGoal : 5;
      final remainingNew = (goal - learnedToday).clamp(0, goal);

      return due + failed + remainingNew;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _loadProgress() async {
    final progressPercent = await WordProgressService.getProgressPercent();
    final sp = await WordProgressService.getAllSurahProgress();

    // Known word count from LearningStateProvider
    // ignore: use_build_context_synchronously
    final knownCount = context.read<LearningStateProvider>().knownCount;

    // Streak: count consecutive days with words_learned > 0.
    // Single bulk query for the last year + in-memory walk, instead of up
    // to 365 sequential single-row DB queries.
    int streak = 0;
    try {
      final db = await DatabaseManager.db;
      final today = DateTime.now();
      final cutoff = today.subtract(const Duration(days: 365));
      final cutoffKey =
          '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-'
          '${cutoff.day.toString().padLeft(2, '0')}';
      final rows = await db
          .query('daily_stats', where: 'date_key >= ?', whereArgs: [cutoffKey]);
      final dailyMap = <String, int>{
        for (final r in rows)
          r['date_key'] as String: (r['words_learned'] as int? ?? 0),
      };
      for (int d = 0; d < 365; d++) {
        final day = today.subtract(Duration(days: d));
        final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}';
        if ((dailyMap[key] ?? 0) > 0) {
          streak++;
        } else {
          break;
        }
      }
    } catch (_) {}

    // ── Last-read positions from SQLite reading_progress ──────────────────
    // Single query for all 114 surahs instead of 114 sequential calls to
    // ContentRepository.getLastReadAyah().
    final Map<int, int> lastRead = {};
    try {
      final db = await DatabaseManager.db;
      final rows = await db
          .query('reading_progress', columns: ['surah_id', 'last_ayah']);
      for (final r in rows) {
        final ayah = r['last_ayah'] as int? ?? 0;
        if (ayah > 1) lastRead[r['surah_id'] as int] = ayah;
      }
    } catch (_) {}
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
      _barAnim = Tween<double>(
              begin: _barAnim.value, end: progressPercent / 100)
          .animate(
              CurvedAnimation(parent: _barCtrl, curve: Curves.easeOutCubic));
      _barCtrl
        ..reset()
        ..forward();

      // Persist this freshly computed snapshot so the NEXT app launch can
      // show it instantly instead of waiting on these same DB queries.
      unawaited(_saveCachedSnapshot());

      // Due-count is the least urgent of these — SRS/daily_stats queries
      // right after a cold DB open are the slowest part of this whole
      // reload (visible as GC pauses in logcat on emulators). Let it
      // resolve separately so it never delays the rest of the screen
      // (which the cache already displayed instantly anyway).
      _loadDueTodayCount().then((dueCount) {
        if (!mounted) return;
        setState(() => _dueTodayCount = dueCount);
        unawaited(_saveCachedSnapshot());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.volunteer_activism,
              color: Color.fromARGB(255, 255, 254, 253)),
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
              _buildQuickAccessRow(),
              _buildProgressHeader(context),
              _buildViewModeSelector(),
              Expanded(
                child: _viewMode == SurahListViewMode.surah
                    ? ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                        itemCount: 114,
                        itemBuilder: (context, index) {
                          final surah = _surahs[index];
                          final id = surah.id;
                          return _SurahCard(
                            surah: surah,
                            surahProgress: _surahProgress[id] ?? 0,
                            lastReadAyah: _lastReadAyahs[id],
                            isFavorite: _favorites.contains(id),
                            onToggleFavorite: () => _toggleFavorite(id),
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
                              await Future.delayed(
                                  const Duration(milliseconds: 300));
                              _loadProgress();
                            },
                          );
                        },
                      )
                    : _buildJuzOrManzilList(
                        isJuz: _viewMode == SurahListViewMode.juz),
              ),
            ],
          ),
          // Flashcard Entry Button
          Positioned(
            bottom: 20,
            left: 40,
            right: 40,
            child: _FlashcardEntryButton(
              dueCount: _dueTodayCount,
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

  Widget _buildViewModeSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _modeChip('Surah', SurahListViewMode.surah),
          const SizedBox(width: 8),
          _modeChip('Juz', SurahListViewMode.juz),
          const SizedBox(width: 8),
          _modeChip('Manzil', SurahListViewMode.manzil),
        ],
      ),
    );
  }

  Widget _modeChip(String label, SurahListViewMode mode) {
    final selected = _viewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _viewMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1B4332) : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF1B4332)
                  : const Color(0xFFD4AF37).withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? Colors.white : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAt(int surahId, int ayahNumber) async {
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
  }

  Widget _buildJuzOrManzilList({required bool isJuz}) {
    final count = isJuz ? 30 : 7;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: count,
      itemBuilder: (context, index) {
        final num = index + 1;
        final start = isJuz
            ? JuzManzilData.juzStarts[num]!
            : JuzManzilData.manzilStarts[num]!;
        final range = isJuz
            ? JuzManzilData.juzSurahRange(num)
            : JuzManzilData.manzilSurahRange(num);
        final startSurahName = quran.getSurahName(start.$1);
        final rangeLabel = range.$1 == range.$2
            ? quran.getSurahName(range.$1)
            : '${quran.getSurahName(range.$1)} → ${quran.getSurahName(range.$2)}';

        return GestureDetector(
          onTap: () => _openAt(start.$1, start.$2),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Theme.of(context).cardColor,
              border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                  ),
                  child: Center(
                    child: Text('$num',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Color(0xFF1B4332))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isJuz ? 'Juz $num' : 'Manzil $num',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('Starts: $startSurahName ${start.$2}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      Text(rangeLabel,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickAccessRow() {
    if (_favorites.isEmpty && _bookmarks.isEmpty) return const SizedBox.shrink();
    return Container(
      color: const Color(0xFF1B4332),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_favorites.isNotEmpty)
            SizedBox(
              height: 22,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _favorites.map((id) {
                  final surah = _surahs.firstWhere((s) => s.id == id,
                      orElse: () => _surahs[0]);
                  return _quickChip(
                    icon: Icons.star,
                    label: '${surah.id}. ${surah.englishName}',
                    color: const Color(0xFFD4AF37),
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
                      _loadProgress();
                    },
                  );
                }).toList(),
              ),
            ),
          if (_favorites.isNotEmpty && _bookmarks.isNotEmpty)
            const SizedBox(height: 4),
          if (_bookmarks.isNotEmpty)
            SizedBox(
              height: 22,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _bookmarks.map((b) => _quickChip(
                      icon: Icons.bookmark,
                      label: '${b['name']} ${b['ayahId']}',
                      color: const Color(0xFF7EC8A0),
                      onTap: () async {
                        final surah = Surah(
                          id: b['surahId'],
                          englishName: quran.getSurahName(b['surahId']),
                          arabicName: quran.getSurahNameArabic(b['surahId']),
                          urduName: quran.getSurahName(b['surahId']),
                          verseCount: quran.getVerseCount(b['surahId']),
                        );
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SurahReaderScreen(
                              surah: surah,
                              jumpToAyahRequested: b['ayahId'],
                            ),
                          ),
                        );
                        _loadProgress();
                      },
                    )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _quickChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 9, color: color),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 9.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressHeader(BuildContext context) {
    final (levelEn, levelAr, levelColor) = _getLevel(_totalProgress);
    final milestone = _getMilestone(_totalProgress);

    return Container(
      color: const Color(0xFF1B4332),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${_totalProgress.toStringAsFixed(1)}%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      height: 1)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('of Quran',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11)),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: levelColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: levelColor.withValues(alpha: 0.5)),
                ),
                child: Text(levelEn,
                    style: TextStyle(
                        fontSize: 10,
                        color: levelColor,
                        fontWeight: FontWeight.bold)),
              ),
              if (_streak > 0) ...[
                const SizedBox(width: 6),
                const Icon(Icons.local_fire_department,
                    size: 15, color: Colors.orange),
                const SizedBox(width: 2),
                Text('$_streak',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          AnimatedBuilder(
            animation: _barAnim,
            builder: (_, __) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(height: 6, color: Colors.white12),
                  FractionallySizedBox(
                    widthFactor: _barAnim.value.clamp(0.0, 1.0),
                    child: Container(
                      height: 6,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFD4AF37), Color(0xFF2ECC71)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text('$_knownCount words known',
                  style: TextStyle(
                      fontSize: 10, color: Colors.white.withValues(alpha: 0.5))),
              if (milestone != null) ...[
                const Spacer(),
                Text('${milestone.$1} ${milestone.$2}',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFD4AF37),
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
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
    if (pct >= 75)
      return ('🏆', 'Three-Quarters of Quran!', 'ماشاء اللہ — أحسنت!');
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
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  const _SurahCard({
    required this.surah,
    required this.surahProgress,
    required this.onTap,
    required this.isFavorite,
    required this.onToggleFavorite,
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
                                  const Color.fromARGB(255, 211, 212, 204).withValues(alpha: 0.2),
                              valueColor: AlwaysStoppedAnimation(
                                widget.surahProgress >= 100
                                    ? _gold
                                    : const Color.fromARGB(255, 92, 179, 105).withValues(alpha: 0.7),
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
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: widget.onToggleFavorite,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            widget.isFavorite ? Icons.star : Icons.star_border,
                            color: widget.isFavorite
                                ? _gold
                                : (isDark ? Colors.white38 : Colors.grey.shade400),
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
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
  final int dueCount;
  const _FlashcardEntryButton({required this.onTap, this.dueCount = 0});

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
                  color: widget.dueCount > 0
                      ? Colors.orange.withValues(alpha: 0.9)
                      : const Color(0xFFD4AF37).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.dueCount > 0 ? '${widget.dueCount} due' : 'SRS',
                  style: TextStyle(
                      color: widget.dueCount > 0
                          ? Colors.white
                          : const Color(0xFFD4AF37),
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
