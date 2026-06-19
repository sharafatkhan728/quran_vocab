import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/surah.dart';
import '../services/word_progress_service.dart';
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
  List<OccurrenceEntry> _occurrences = [];
  bool _isLoading = true;
  int _loadedSurahs = 0;
  int _totalSurahsToSearch = 0;

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
        return GoogleFonts.amiriQuran(
            fontSize: size, color: color, height: 1.8);
    }
  }

  Future<void> _loadOccurrences() async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = WordProgressService.normalizeArabic(widget.word.arabic);

    // Step 1: Find which surahs contain this word from local cache
    final List<int> surahsWithWord = [];
    for (int i = 1; i <= 114; i++) {
      final raw = prefs.getStringList('surah_word_counts_$i');
      if (raw == null) continue;
      final has = raw.any((e) {
        final p = e.split('|||');
        return p.isNotEmpty && p[0] == normalized;
      });
      if (has) surahsWithWord.add(i);
    }

    if (mounted) {
      setState(() {
        _totalSurahsToSearch = surahsWithWord.length;
        _isLoading = surahsWithWord.isNotEmpty;
      });
    }

    if (surahsWithWord.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Step 2: For each surah, read verse data from local cache
    // We saved verse-level data in surah_word_counts, but we need
    // ayah text — fetch from API only for matching surahs (much fewer calls)
    for (final surahId in surahsWithWord) {
      try {
        final url =
            'https://api.qurancdn.com/api/qdc/verses/by_chapter/$surahId'
            '?words=true&word_fields=text_uthmani'
            '&word_translation_language=ur&per_page=300&page=1';
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          if (mounted) setState(() => _loadedSurahs++);
          continue;
        }

        final data = json.decode(response.body);
        final verses = data['verses'] as List;
        final List<OccurrenceEntry> newEntries = [];

        for (final verse in verses) {
          final ayahNum = verse['verse_number'] as int;
          final wordsJson = verse['words'] as List;
          bool found = false;
          final List<WordToken> tokens = [];

          for (final w in wordsJson) {
            if (w['char_type_name'] == 'end') continue;
            final arabic = (w['text_uthmani'] ?? '') as String;
            final isMatch =
                WordProgressService.normalizeArabic(arabic) == normalized;
            if (isMatch) found = true;
            tokens.add(WordToken(arabic: arabic, isHighlighted: isMatch));
          }
          if (found) {
            newEntries.add(OccurrenceEntry(
              surahId: surahId,
              ayahNumber: ayahNum,
              tokens: tokens,
            ));
          }
        }

        // Show results immediately as each surah loads
        if (mounted) {
          setState(() {
            _occurrences.addAll(newEntries);
            _loadedSurahs++;
            if (_loadedSurahs >= _totalSurahsToSearch) {
              _isLoading = false;
            }
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loadedSurahs++);
      }
    }

    if (mounted) setState(() => _isLoading = false);
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF1B4332)),
                        SizedBox(height: 16),
                        Text('Finding all occurrences...'),
                      ],
                    ),
                  )
                : _occurrences.isEmpty && !_isLoading
                    ? const Center(
                        child: Text(
                            'No occurrences found.\n'
                            'Make sure vocabulary is fully loaded.',
                            textAlign: TextAlign.center))
                    : _occurrences.isEmpty && _isLoading
                        ? const Center(
                            child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                  color: Color(0xFF1B4332)),
                              SizedBox(height: 16),
                              Text('Searching...'),
                            ],
                          ))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount:
                                _occurrences.length + (_isLoading ? 1 : 0),
                            itemBuilder: (context, index) {
                              // Loading indicator at bottom
                              if (index == _occurrences.length) {
                                return Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    children: [
                                      const CircularProgressIndicator(
                                          color: Color(0xFF1B4332)),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Searching surah $_loadedSurahs of $_totalSurahsToSearch...',
                                        style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                );
                              }
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
                                      // Surah:Ayah badge + tap hint
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
                                                      color: Colors
                                                          .grey.shade400)),
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
                                      // Highlighted ayah text

                                      //chatgpt suggested wrap to handle long ayahs better, and it worked great! no more overflow errors 🎉

                                      Wrap(
                                        alignment: WrapAlignment.end,
                                        textDirection: TextDirection.rtl,
                                        spacing: 4,
                                        children: o.tokens.map((token) {
                                          return token.isHighlighted
                                              ? Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 4,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xFFD4AF37)
                                                            .withValues(
                                                                alpha: 0.3),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                    border: Border.all(
                                                      color: const Color(
                                                          0xFFD4AF37),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    token.arabic,
                                                    style: _arabicStyle(
                                                            context, 20)
                                                        .copyWith(
                                                      color: const Color(
                                                          0xFF1B4332),
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
