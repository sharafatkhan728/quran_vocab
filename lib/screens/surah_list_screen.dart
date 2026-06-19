import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;
import '../models/surah.dart';
import '../services/word_progress_service.dart';
import 'surah_reader_screen.dart';
import 'progress_screen.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/surah_search_delegate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'flashcard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SurahListScreen extends StatefulWidget {
  const SurahListScreen({super.key});

  @override
  State<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends State<SurahListScreen> {
  double _totalProgress = 0;
  Map<int, double> _surahProgress = {};
  Map<int, int> _lastReadAyahs = {}; // surahId → ayahNum

  List<Map<String, dynamic>> _bookmarks = [];

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final progressPercent = await WordProgressService.getProgressPercent();
    final sp = await WordProgressService.getAllSurahProgress();
    final prefs = await SharedPreferences.getInstance();
    final Map<int, int> lastRead = {};
    for (int i = 1; i <= 114; i++) {
      final ayah = prefs.getInt('last_read_$i') ?? 0;
      if (ayah > 1) lastRead[i] = ayah;
    }
    if (mounted) setState(() => _lastReadAyahs = lastRead);

    final bList = prefs.getStringList('bookmarks') ?? [];
    final bmarks = <Map<String, dynamic>>[];
    for (final b in bList) {
      final parts = b.split(':');
      if (parts.length >= 2) {
        final sid = int.tryParse(parts[0]) ?? 0;
        final aid = int.tryParse(parts[1]) ?? 0;
        bmarks.add(
            {'surahId': sid, 'ayahId': aid, 'name': quran.getSurahName(sid)});
      }
    }
    if (mounted) setState(() => _bookmarks = bmarks);
    if (mounted) {
      setState(() {
        _totalProgress = progressPercent;
        _surahProgress = sp;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Column(
          children: [
            Text('القرآن الكريم', style: TextStyle(fontSize: 22)),
            Text('Quran Kareem',
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
                        jumpToAyah: ayahNumber,
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
                                              jumpToAyah: b['ayahId'],
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
                    final id = index + 1;

                    return _SurahCard(
                      id: id,
                      surahProgress: _surahProgress[id] ?? 0,
                      lastReadAyah: _lastReadAyahs[id],
                      onTap: () async {
                        final surah = Surah(
                          id: id,
                          englishName: quran.getSurahName(id),
                          arabicName: quran.getSurahNameArabic(id),
                          urduName: quran.getSurahName(id),
                          verseCount: quran.getVerseCount(id),
                        );

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
                          const Duration(milliseconds: 300),
                        );

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

  //................

  Widget _buildProgressHeader(BuildContext context) {
    return Container(
      color: const Color(0xFF1B4332),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overall: ${_totalProgress.toStringAsFixed(1)}%',
              style: const TextStyle(color: Colors.white70, fontSize: 17)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _totalProgress / 100,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SurahCard extends StatefulWidget {
  final int id;
  final double surahProgress;
  final int? lastReadAyah;
  final VoidCallback onTap;
  const _SurahCard(
      {required this.id,
      required this.surahProgress,
      required this.onTap,
      this.lastReadAyah});

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
    // Stagger entrance — only first 20 animate
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
                      // ── Left: Number + progress circle ──────────────
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Progress circle with % inside
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
                                            : (isDark
                                                ? Colors.white70
                                                : _green),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 5),
                              // Makki/Madani + ayah count
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),

                      // ── Center: Names + info ──────────────────────────
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // English + revelation type
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
                                              quran.getSurahName(widget.id),
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
                                            '${quran.getVerseCount(widget.id)} ayahs',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: isDark
                                                    ? Colors.white54
                                                    : Colors.grey.shade500),
                                          ),
                                          if (widget.lastReadAyah != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 3),
                                              child: Text(
                                                'Last Read: Ayah ${widget.lastReadAyah}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Color(0xFFD4AF37),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Arabic name — right side
                                Text(
                                  quran.getSurahNameArabic(widget.id),
                                  textDirection: TextDirection.rtl,
                                  style: GoogleFonts.amiriQuran(
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
                      // ── Right: Arrow ──────────────────────────────────
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
