import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/surah.dart';
import '../providers/display_provider.dart';
import '../repositories/search_repository.dart';
import '../services/word_glossary_service.dart';
import 'package:quran/quran.dart' as quran;
import 'surah_reader_screen.dart';

class VocabularySearchScreen extends StatefulWidget {
  const VocabularySearchScreen({super.key});

  @override
  State<VocabularySearchScreen> createState() => _VocabularySearchScreenState();
}

class _VocabularySearchScreenState extends State<VocabularySearchScreen>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);
  static const _teal = Color(0xFF2D6A4F);

  final TextEditingController _searchCtrl = TextEditingController();
  late TabController _tabs;

  List<SearchResult> _surahs = [];
  List<SearchResult> _words = [];
  List<SearchResult> _roots = [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onQueryChanged);
    _searchCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final q = _searchCtrl.text;
    if (q == _lastQuery) return;
    _lastQuery = q;
    if (q.trim().isEmpty) {
      setState(() {
        _surahs = [];
        _words = [];
        _roots = [];
        _loading = false;
      });
      return;
    }
    _search(q);
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final lang = WordGlossaryService.selectedLang;
    final result = await SearchRepository.searchAll(q, lang: lang);
    if (!mounted) return;
    setState(() {
      _surahs = result.surahs;
      _words = result.words;
      _roots = result.roots;
      _loading = false;
    });
    // Auto-switch to tab with most results
    if (result.surahs.isNotEmpty) {
      _tabs.animateTo(0);
    } else if (result.words.isNotEmpty) {
      _tabs.animateTo(1);
    } else if (result.roots.isNotEmpty) {
      _tabs.animateTo(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final display = context.watch<DisplayProvider>();

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F0E8),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          textDirection: TextDirection.rtl,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            hintText: 'Search Arabic, Urdu, or English...',
            hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
            border: InputBorder.none,
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white70),
                    onPressed: () => _searchCtrl.clear(),
                  )
                : null,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _gold,
          labelColor: _gold,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(text: 'Surahs (${_surahs.length})'),
            Tab(text: 'Words (${_words.length})'),
            Tab(text: 'Roots (${_roots.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _gold))
          : _searchCtrl.text.trim().isEmpty
              ? _buildEmptyState(isDark)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildSurahList(isDark),
                    _buildWordList(isDark, display),
                    _buildRootList(isDark, display),
                  ],
                ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🔍',
              style: TextStyle(
                  fontSize: 48,
                  color: _gold.withValues(alpha: 0.5))),
          const SizedBox(height: 16),
          Text(
            'Search Quranic Vocabulary',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : _green),
          ),
          const SizedBox(height: 8),
          Text(
            'Type Arabic, Urdu, or English',
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: ['اللہ', 'رحم', 'کتاب', 'mercy', 'Allah']
                .map((hint) => GestureDetector(
                      onTap: () => _searchCtrl.text = hint,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _green.withValues(alpha: 0.3)),
                        ),
                        child: Text(hint,
                            style: TextStyle(
                                fontSize: 14,
                                color:
                                    isDark ? Colors.white70 : _green)),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSurahList(bool isDark) {
    if (_surahs.isEmpty) return _noResults(isDark);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _surahs.length,
      itemBuilder: (_, i) {
        final r = _surahs[i];
        return _SurahResultCard(
          result: r,
          isDark: isDark,
          onTap: () => _openSurah(r.surahId),
        );
      },
    );
  }

  Widget _buildWordList(bool isDark, DisplayProvider display) {
    if (_words.isEmpty) return _noResults(isDark);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _words.length,
      itemBuilder: (_, i) {
        final r = _words[i];
        return _WordResultCard(
          result: r,
          isDark: isDark,
          display: display,
          onTap: () => _openSurah(r.surahId, ayah: r.ayahNumber),
        );
      },
    );
  }

  Widget _buildRootList(bool isDark, DisplayProvider display) {
    if (_roots.isEmpty) return _noResults(isDark);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _roots.length,
      itemBuilder: (_, i) {
        final r = _roots[i];
        return _RootResultCard(
          result: r,
          isDark: isDark,
          display: display,
        );
      },
    );
  }

  Widget _noResults(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off,
              size: 48,
              color: isDark ? Colors.white24 : Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No results found',
              style: TextStyle(
                  color:
                      isDark ? Colors.white38 : Colors.grey.shade500)),
        ],
      ),
    );
  }

  void _openSurah(int surahId, {int? ayah}) {
    if (surahId == 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurahReaderScreen(
          surah: Surah(
            id: surahId,
            englishName: quran.getSurahName(surahId),
            arabicName: quran.getSurahNameArabic(surahId),
            urduName: quran.getSurahName(surahId),
            verseCount: quran.getVerseCount(surahId),
          ),
          jumpToAyah: ayah,
        ),
      ),
    );
  }
}

// ── Surah result card ─────────────────────────────────────────────────────────
class _SurahResultCard extends StatelessWidget {
  final SearchResult result;
  final bool isDark;
  final VoidCallback onTap;

  const _SurahResultCard({
    required this.result,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1B4332).withValues(alpha: 0.12),
                border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text('${result.surahId}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B4332))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.meaning,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
                  Text(result.subtitle,
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white38
                              : Colors.grey.shade500)),
                ],
              ),
            ),
            Text(
              result.arabic,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.amiriQuran(
                  fontSize: 20,
                  color: isDark
                      ? Colors.white
                      : const Color(0xFF1B4332)),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right,
                color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
                size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Word result card ──────────────────────────────────────────────────────────
class _WordResultCard extends StatelessWidget {
  final SearchResult result;
  final bool isDark;
  final DisplayProvider display;
  final VoidCallback onTap;

  const _WordResultCard({
    required this.result,
    required this.isDark,
    required this.display,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            // Frequency badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1B4332).withValues(alpha: 0.08),
                border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text('${result.frequency}×',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B4332))),
              ),
            ),
            const SizedBox(width: 12),
            // Meaning
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.meaning.isNotEmpty ? result.meaning : '—',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: 'JameelNoori',
                      fontSize: 14,
                      color: isDark
                          ? const Color(0xFF7EC8A0)
                          : const Color(0xFF2D6A4F),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(result.subtitle,
                      style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? Colors.white38
                              : Colors.grey.shade500)),
                ],
              ),
            ),
            // Arabic word
            Text(
              result.arabic,
              textDirection: TextDirection.rtl,
              style: _arabicStyle(display, isDark, 24),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _arabicStyle(DisplayProvider d, bool isDark, double size) {
    final color = isDark ? Colors.white : const Color(0xFF1A1A1A);
    switch (d.arabicFont) {
      case 'indopak':
        return TextStyle(
            fontFamily: 'IndoPak', fontSize: size, color: color, height: 1.6);
      case 'noorehuda':
        return TextStyle(
            fontFamily: 'NoorehudaFont',
            fontSize: size,
            color: color,
            height: 1.6);
      default:
        return GoogleFonts.amiriQuran(
            fontSize: size, color: color, height: 1.6);
    }
  }
}

// ── Root result card ──────────────────────────────────────────────────────────
class _RootResultCard extends StatelessWidget {
  final SearchResult result;
  final bool isDark;
  final DisplayProvider display;

  const _RootResultCard({
    required this.result,
    required this.isDark,
    required this.display,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
            ),
            child: Text(
              result.arabic,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.amiriQuran(
                  fontSize: 22, color: const Color(0xFFD4AF37)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.meaning.isNotEmpty ? result.meaning : result.arabic,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Colors.white : const Color(0xFF1A1A1A)),
                ),
                Text(result.subtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color:
                            isDark ? Colors.white38 : Colors.grey.shade500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}