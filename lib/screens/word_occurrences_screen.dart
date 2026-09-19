import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../database/database_manager.dart';
import '../models/surah.dart';
import '../repositories/vocabulary_repository.dart';
import 'surah_reader_screen.dart';
import 'vocabulary_screen.dart';
import 'package:quran/quran.dart' as quran;
import '../providers/display_provider.dart';
import 'package:provider/provider.dart';

class WordOccurrencesScreen extends StatefulWidget {
  final WordEntry word;
  const WordOccurrencesScreen({super.key, required this.word});

  @override
  State<WordOccurrencesScreen> createState() => _WordOccurrencesScreenState();
}

class _WordOccurrencesScreenState extends State<WordOccurrencesScreen> {
  final List<OccurrenceEntry> _occurrences = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOccurrences();
  }

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

  /// Reads occurrences directly from SQLite via the already-existing
  /// vocab_word_id foreign key on ayah_words — instead of the old approach
  /// which re-scanned all 114 surahs / 6236 ayahs via the `quran` package
  /// and string-matched every word on every single screen open. This is a
  /// single indexed query instead of thousands of string comparisons.
  Future<void> _loadOccurrences() async {
    setState(() => _isLoading = true);

    // widget.word.arabic is already the arabic_clean form (comes straight
    // from vocab_words.arabic_clean via WordProgressService.getWordFrequencies
    // in vocabulary_screen.dart), so this resolves to the exact same vocab
    // row every other screen (LearningStateProvider, SrsService) uses.
    final vocab =
        await VocabularyRepository.getByArabicClean(widget.word.arabic);
    if (vocab == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT a.surah_id, a.ayah_number, aw.position, aw.arabic_text, aw.vocab_word_id
      FROM ayah_words aw
      JOIN ayahs a ON a.id = aw.ayah_id
      WHERE a.id IN (SELECT ayah_id FROM ayah_words WHERE vocab_word_id = ?)
      ORDER BY a.surah_id ASC, a.ayah_number ASC, aw.position ASC
    ''', [vocab.id]);

    // Group flat rows into one entry per ayah, preserving word order.
    final grouped = <String, List<Map<String, Object?>>>{};
    final order = <String>[];
    for (final r in rows) {
      final key = '${r['surah_id']}:${r['ayah_number']}';
      if (!grouped.containsKey(key)) order.add(key);
      grouped.putIfAbsent(key, () => []).add(r);
    }

    final entries = order.map((key) {
      final wordsInAyah = grouped[key]!;
      final tokens = wordsInAyah
          .map((r) => WordToken(
                arabic: r['arabic_text'] as String? ?? '',
                isHighlighted: (r['vocab_word_id'] as int?) == vocab.id,
              ))
          .toList();
      final first = wordsInAyah.first;
      return OccurrenceEntry(
        surahId: first['surah_id'] as int,
        ayahNumber: first['ayah_number'] as int,
        tokens: tokens,
      );
    }).toList();

    if (!mounted) return;
    setState(() {
      _occurrences
        ..clear()
        ..addAll(entries);
      _isLoading = false;
    });
  }

  void _openSurah(OccurrenceEntry o) {
    final surah = Surah(
      id: o.surahId,
      englishName: quran.getSurahName(o.surahId),
      arabicName: quran.getSurahNameArabic(o.surahId),
      urduName: quran.getSurahName(o.surahId),
      verseCount: quran.getVerseCount(o.surahId),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurahReaderScreen(
          surah: surah,
          jumpToAyah: o.ayahNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              widget.word.originalArabic,
              style: _arabicStyle(context, 26),
            ),
            Text(widget.word.urdu,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B4332),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            color: const Color(0xFF1B4332),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _InfoBadge(
                    label: 'Total in Quran',
                    value: '${widget.word.frequency}×'),
                _InfoBadge(
                    label: 'Surahs',
                    value: _isLoading
                        ? '...'
                        : '${_occurrences.map((o) => o.surahId).toSet().length}'),
                _InfoBadge(
                    label: 'Ayahs found',
                    value: _isLoading ? '...' : '${_occurrences.length}'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Tap any ayah to open it in the Quran reader',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF1B4332)))
                : _occurrences.isEmpty
                    ? const Center(
                        child: Text(
                            'No occurrences found.\n'
                            'Make sure vocabulary is fully loaded.',
                            textAlign: TextAlign.center))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _occurrences.length,
                        itemBuilder: (context, index) {
                          final o = _occurrences[index];
                          return GestureDetector(
                            onTap: () => _openSurah(o),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color(0xFFD4AF37)
                                        .withValues(alpha: 0.4)),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.open_in_new,
                                              size: 14,
                                              color: Colors.grey.shade400),
                                          const SizedBox(width: 4),
                                          Text('Open',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      Colors.grey.shade400)),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1B4332),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          '${o.surahId}:${o.ayahNumber}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    textDirection: TextDirection.rtl,
                                    spacing: 4,
                                    children: o.tokens.map((token) {
                                      return token.isHighlighted
                                          ? Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFD4AF37)
                                                    .withValues(alpha: 0.3),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color:
                                                      const Color(0xFFD4AF37),
                                                ),
                                              ),
                                              child: Text(
                                                token.arabic,
                                                style: _arabicStyle(
                                                        context, 20)
                                                    .copyWith(
                                                  color:
                                                      const Color(0xFF1B4332),
                                                  fontWeight:
                                                      FontWeight.bold,
                                                ),
                                              ),
                                            )
                                          : Text(
                                              token.arabic,
                                              style:
                                                  _arabicStyle(context, 26),
                                            );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class WordToken {
  final String arabic;
  final bool isHighlighted;
  WordToken({required this.arabic, required this.isHighlighted});
}

class OccurrenceEntry {
  final int surahId;
  final int ayahNumber;
  final List<WordToken> tokens;
  OccurrenceEntry(
      {required this.surahId, required this.ayahNumber, required this.tokens});
}

class _InfoBadge extends StatelessWidget {
  final String label;
  final String value;
  const _InfoBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.white60)),
      ],
    );
  }
}