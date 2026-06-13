// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:quran/quran.dart' as quran;
import '../models/word.dart';
import '../models/surah.dart';
import '../widgets/word_tile.dart';
import '../services/word_progress_service.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../widgets/word_detail_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/translation_service.dart';
import 'package:flutter/services.dart';




//.................................................

//......................................................

//.....................................
class SurahReaderScreen extends StatefulWidget {
  final Surah surah;
  final int? jumpToAyah;
  const SurahReaderScreen({super.key, required this.surah, this.jumpToAyah});

  @override
  State<SurahReaderScreen> createState() => _SurahReaderScreenState();
}

class _SurahReaderScreenState extends State<SurahReaderScreen> {
  // key = display ayah number (1-based, always correct Islamic numbering)
  // value = list of words for that ayah
  final Map<int, List<QuranWord>> _ayahCache = {};

  Set<String> _knownNormalizedWords = {};
  bool _isLoading = true;
  double _arabicFontSize = 32;
  double _urduFontSize = 16;

  // Translation
  final Map<String, String> _ayahTranslations = {}; // ayahNum → translation text
  bool _showTranslation = true;
  String _selectedScholar = 'ur.jalandhry';
// ayahNum → {scholar→text}

  // Bookmarks
  Set<String> _bookmarks = {}; // format: "surahId:ayahNum"

  // Pinch zoom
  double _pinchScale = 1.0;
  double _lastScale = 1.0;

  // Juz data cache
// ayahNum → label like "Juz 1"

  // How many real ayahs this surah has (Islamic standard numbering)
  // This is what the USER sees — always matches printed Quran

  int _totalAyahs = 0;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  // Surah 9 has no Bismillah. Surah 1 Bismillah IS ayah 1.
  // All others: Bismillah is shown as header only, not counted as ayah.
  //bool get _showBismillahHeader => widget.surah.id != 9;
  bool get _showBismillahHeader => widget.surah.id != 9 && widget.surah.id != 1;

  @override
  void initState() {
    super.initState();
    _loadKnownWords().then((_) => _fetchFromApi());
    _loadBookmarks();
    _loadScholar();
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('bookmarks') ?? [];
    setState(() => _bookmarks = list.toSet());
  }

  Future<void> _loadScholar() async {
    await TranslationService.init();
    setState(() => _selectedScholar = TranslationService.selectedScholar);
  }

  Future<void> _toggleBookmark(int ayahNum) async {
    final key = '${widget.surah.id}:$ayahNum';
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_bookmarks.contains(key)) {
        _bookmarks.remove(key);
      } else {
        _bookmarks.add(key);
      }
    });
    await prefs.setStringList('bookmarks', _bookmarks.toList());
    HapticFeedback.lightImpact();
  }

  Future<void> _loadTranslation(int ayahNum) async {
    if (_ayahTranslations.containsKey('$ayahNum')) return;
    final text = await TranslationService.getAyahTranslation(
        widget.surah.id, ayahNum);
    if (text != null && mounted) {
      setState(() => _ayahTranslations['$ayahNum'] = text);
    }
  }

  void _showScholarPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Select Translation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...TranslationService.scholars.entries.map((e) => ListTile(
            title: Text(e.value),
            trailing: _selectedScholar == e.key
                ? const Icon(Icons.check, color: Color(0xFF1B4332))
                : null,
            onTap: () async {
              await TranslationService.setScholar(e.key);
              setState(() {
                _selectedScholar = e.key;
                _ayahTranslations.clear();
                setState(() {
                _selectedScholar = e.key;
                _ayahTranslations.clear();
              });
              Navigator.pop(context);
              // Show loading snackbar
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 12),
                      Text('Switching translation...'),
                    ],
                  ),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              ); // reload with new scholar
              });
              // ignore: use_build_context_synchronously
              Navigator.pop(context);
            },
          )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Islamic standard verse counts — matches any printed Quran
  // The quran package sometimes includes Bismillah in count; we don't

  Future<void> _loadKnownWords() async {
    final known = await WordProgressService.getAllKnownWords();
    if (mounted) setState(() => _knownNormalizedWords = known);
  }

// Fetch all ayahs from Quran.com API using correct Islamic numbering
  Future<void> _fetchFromApi() async {
    setState(() => _isLoading = true);
    try {
      // Fetch all verses of this surah in one API call
      final url =
          'https://api.qurancdn.com/api/qdc/verses/by_chapter/${widget.surah.id}'
          '?words=true'
          '&word_fields=text_uthmani,translation,transliteration'
          '&word_translation_language=ur'
          //'&per_page=300'; // get all at once
          '&per_page=300&page=1'; // get all at once

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final verses = data['verses'] as List;

        ////below print line is temperary can be delete
        //print('API returned ${verses.length} verses for surah ${widget.surah.id}');

        for (final verse in verses) {
          final ayahNum = verse['verse_number'] as int;
          //if (ayahNum == 1 && widget.surah.id != 9) continue; // surah touba me bismillah nhi hai
          //final displayAyah = widget.surah.id == 9 ? ayahNum : ayahNum - 1;

          final displayAyah = ayahNum;

          //below print line is temperary can be delete
          //print('verse $ayahNum → display $displayAyah');

          final wordsJson = verse['words'] as List;
          final words = wordsJson
              .where((w) => w['char_type_name'] != 'end') // skip ۝ glyph
              .map((w) {
            final wordId = '${widget.surah.id}:$ayahNum:${w['position']}';
            final arabicText = (w['text_uthmani'] ?? w['text'] ?? '') as String;
            final normalized = WordProgressService.normalizeArabic(arabicText);
            final urduMeaning = (w['translation']?['text'] ?? '') as String;
            // Save urdu meaning for vocabulary screen
            WordProgressService.saveWordUrdu(normalized, urduMeaning);
            WordProgressService.saveWordOriginal(normalized, arabicText);
            return QuranWord(
              id: wordId,
              arabic: arabicText,
              urduMeaning: urduMeaning,
              transliteration: (w['transliteration']?['text'] ?? '') as String,
              isKnown: _knownNormalizedWords.contains(normalized),
            );
          }).toList();

          if (mounted) {
            setState(() => _ayahCache[displayAyah] = words);
          }
        }
        //.........

        // Save total unique words for this surah immediately after loading
        final allWords = _ayahCache.values
            .expand((words) => words)
            .map((w) => WordProgressService.normalizeArabic(w.arabic))
            .toSet();
        // Save this surah's word list for cross-surah progress tracking
        WordProgressService.saveSurahWordList(widget.surah.id, allWords);
        // Save word occurrence counts for frequency calculation
        final wordCounts = <String, int>{};
        for (final words in _ayahCache.values) {
          for (final w in words) {
            final norm = WordProgressService.normalizeArabic(w.arabic);
            wordCounts[norm] = (wordCounts[norm] ?? 0) + 1;
          }
        }
        WordProgressService.saveSurahWordCounts(widget.surah.id, wordCounts);

        // Also update known count immediately
        final knownCount = _ayahCache.values
            .expand((words) => words)
            .where((w) => w.isKnown)
            .map((w) => WordProgressService.normalizeArabic(w.arabic))
            .toSet()
            .length;
        WordProgressService.updateSurahKnownCount(widget.surah.id, knownCount);

        if (mounted) {
          setState(() => _totalAyahs = _ayahCache.keys.length);
        }
      } else {
        print('API STATUS ERROR: ${response.statusCode}');
        _buildFallback();
      }
    } catch (e) {
      print('FETCH ERROR: $e');

      if (mounted) {
        _buildFallback();

        setState(() {
          _totalAyahs = _ayahCache.keys.length;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        if (widget.jumpToAyah != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _itemScrollController.jumpTo(
              index: widget
                  .jumpToAyah!, // index = ayah number (index 0 = bismillah)
              alignment: 0.0,
            );
          });
        }
      }
    }
  }

//...................................................................

  void _buildFallback() {
    print('FALLBACK CALLED'); //temporary print line
    print('_totalAyahs before = $_totalAyahs'); //temporary print line
    // Use Islamic verse counts if API failed before setting _totalAyahs
    if (_totalAyahs == 0) {
      //_totalAyahs = _islamicVerseCount(widget.surah.id); ?????????
      _totalAyahs = quran.getVerseCount(widget.surah.id);
    }
    print('_totalAyahs after = $_totalAyahs'); /////tteemporary print line
    for (int ayah = 1; ayah <= _totalAyahs; ayah++) {
      if (_ayahCache.containsKey(ayah)) continue;
      try {
        final arabicText = quran.getVerse(widget.surah.id, ayah);
        final urduText = quran.getVerseTranslation(
          widget.surah.id,
          ayah,
          translation: quran.Translation.urdu,
        );
        final arabicWords = arabicText.split(' ');
        final urduWords = urduText.split(' ');
        _ayahCache[ayah] = List.generate(arabicWords.length, (i) {
          final wordId = '${widget.surah.id}:$ayah:${i + 1}';
          final normalized =
              WordProgressService.normalizeArabic(arabicWords[i]);
          return QuranWord(
            id: wordId,
            arabic: arabicWords[i],
            urduMeaning: i < urduWords.length ? urduWords[i] : '',
            isKnown: _knownNormalizedWords.contains(normalized),
          );
        });
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _onWordLongPress(QuranWord word) async {
    final nowKnown = await WordProgressService.toggleWord(word.arabic);
    final normalized = WordProgressService.normalizeArabic(word.arabic);

    if (mounted) {
      setState(() {
        if (nowKnown) {
          _knownNormalizedWords.add(normalized);
        } else {
          _knownNormalizedWords.remove(normalized);
        }
        // Update ALL cached ayahs — same Arabic word hidden everywhere
        for (final ayahNum in _ayahCache.keys) {
          _ayahCache[ayahNum] = _ayahCache[ayahNum]!.map((w) {
            final wNorm = WordProgressService.normalizeArabic(w.arabic);
            if (wNorm == normalized) {
              return QuranWord(
                id: w.id,
                arabic: w.arabic,
                urduMeaning: w.urduMeaning,
                transliteration: w.transliteration,
                isKnown: nowKnown,
              );
            }
            return w;
          }).toList();
        }
      });

      // Update surah-level progress
      // Recalculate progress for ALL surahs — because this word
      // may appear in multiple surahs across the Quran

      
      WordProgressService.recalculateAllSurahProgress(); // fire and forget
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(nowKnown ? '✓ یاد ہے — معنی چھپا دیا' : 'معنی واپس آ گیا'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            nowKnown ? Colors.green.shade800 : Colors.grey.shade700,
      ));
    }
  }

  void _showWordDetail(QuranWord word) {
    final parts = word.id.split(':');
    final ayahId = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => WordDetailDialog(
        word: word,
        surahId: widget.surah.id,
        ayahId: ayahId,
        isKnown: _knownNormalizedWords
            .contains(WordProgressService.normalizeArabic(word.arabic)),
        ayahWords: _ayahCache[ayahId] ?? [],
        onKnownToggled: (nowKnown) {
          final normalized = WordProgressService.normalizeArabic(word.arabic);
          setState(() {
            if (nowKnown) {
              _knownNormalizedWords.add(normalized);
            } else {
              _knownNormalizedWords.remove(normalized);
            }
            for (final ayahNum in _ayahCache.keys) {
              _ayahCache[ayahNum] = _ayahCache[ayahNum]!.map((w) {
                final wNorm = WordProgressService.normalizeArabic(w.arabic);
                if (wNorm == normalized) {
                  return QuranWord(
                    id: w.id,
                    arabic: w.arabic,
                    urduMeaning: w.urduMeaning,
                    transliteration: w.transliteration,
                    isKnown: nowKnown,
                  );
                }
                return w;
              }).toList();
            }
          });
          WordProgressService.recalculateAllSurahProgress();
        },
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Font Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Text('Arabic size: ${_arabicFontSize.round()}'),
              Slider(
                value: _arabicFontSize,
                min: 18,
                max: 50,
                divisions: 12,
                activeColor: const Color(0xFF1B4332),
                onChanged: (v) {
                  setModal(() => _arabicFontSize = v);
                  setState(() => _arabicFontSize = v);
                },
              ),
              Text('Urdu size: ${_urduFontSize.round()}'),
              Slider(
                value: _urduFontSize,
                min: 10,
                max: 30,
                divisions: 12,
                activeColor: const Color(0xFF1B4332),
                onChanged: (v) {
                  setModal(() => _urduFontSize = v);
                  setState(() => _urduFontSize = v);
                },
              ),
              const SizedBox(height: 16),
              const Text('Arabic Font Style'),
              const SizedBox(height: 8),
              Consumer<ThemeProvider>(
                builder: (context, theme, _) => Row(
                  children: [
                    _FontChip(
                      label: 'Uthmani',
                      selected: theme.arabicFont == 'uthmani',
                      onTap: () => theme.setArabicFont('uthmani'),
                    ),
                    const SizedBox(width: 8),
                    _FontChip(
                      label: 'Indo-Pak',
                      selected: theme.arabicFont == 'indopak',
                      onTap: () => theme.setArabicFont('indopak'),
                    ),
                    const SizedBox(width: 8),
                    _FontChip(
                      label: 'Noorehuda',
                      selected: theme.arabicFont == 'noorehuda',
                      onTap: () => theme.setArabicFont('noorehuda'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F0),
      appBar: AppBar(
        title: Column(children: [
          Text(widget.surah.arabicName, style: const TextStyle(fontSize: 20)),
          Text('${widget.surah.englishName} • $_totalAyahs verses',
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B4332),
        foregroundColor: Colors.white,
        actions: [
          Consumer<ThemeProvider>(
            builder: (context, theme, _) => IconButton(
              icon: Icon(theme.isDark ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => theme.toggleTheme(),
            ),
          ),

          IconButton(
            icon: const Icon(Icons.translate),
            tooltip: 'Translation',
            onPressed: _showScholarPicker,
          ),
          IconButton(
            icon: Icon(_showTranslation ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _showTranslation = !_showTranslation),
          ),
          
          IconButton(
              icon: const Icon(Icons.text_fields), onPressed: _showSettings),
        ],
      ),
      body: _isLoading && _ayahCache.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF1B4332)),
                  SizedBox(height: 16),
                  Text('Loading word-by-word data...'),
                ],
              ),
            )
          : GestureDetector(
              onScaleStart: (_) => _lastScale = _pinchScale,
              onScaleUpdate: (d) {
                if (d.pointerCount < 2) return;
                setState(() {
                  _pinchScale = (_lastScale * d.scale).clamp(0.7, 2.0);
                  _arabicFontSize = (26 * _pinchScale).clamp(14, 52);
                  _urduFontSize = (13 * _pinchScale).clamp(10, 26);
                });
              },
              child: ScrollablePositionedList.builder(          
                itemScrollController: _itemScrollController,
                itemPositionsListener: _itemPositionsListener,
                padding: const EdgeInsets.all(16),
                              
                itemCount: _totalAyahs + 2,
                itemBuilder: (context, index) {
                  // index 0 = bismillah header
                  if (index == 0) {
                    if (!_showBismillahHeader) return const SizedBox.shrink();
                    return _BismillahHeader();
                  }

                  if (index == _totalAyahs + 1) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
                    child: Row(
                      children: [
                        if (widget.surah.id > 1)
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                final prevId = widget.surah.id - 1;
                                Navigator.pushReplacement(context,
                                  MaterialPageRoute(builder: (_) => SurahReaderScreen(
                                    surah: Surah(
                                      id: prevId,
                                      englishName: quran.getSurahName(prevId),
                                      arabicName: quran.getSurahNameArabic(prevId),
                                      urduName: quran.getSurahName(prevId),
                                      verseCount: quran.getVerseCount(prevId),
                                    ),
                                  )));
                              },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1B4332).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF1B4332).withValues(alpha: 0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('← Previous',
                                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    Text(quran.getSurahName(widget.surah.id - 1),
                                        style: const TextStyle(fontWeight: FontWeight.bold,
                                            color: Color(0xFF1B4332))),
                                    Text(quran.getSurahNameArabic(widget.surah.id - 1),
                                        textDirection: TextDirection.rtl,
                                        style: GoogleFonts.amiriQuran(fontSize: 16)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(width: 10),
                        if (widget.surah.id < 114)
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                final nextId = widget.surah.id + 1;
                                Navigator.pushReplacement(context,
                                  MaterialPageRoute(builder: (_) => SurahReaderScreen(
                                    surah: Surah(
                                      id: nextId,
                                      englishName: quran.getSurahName(nextId),
                                      arabicName: quran.getSurahNameArabic(nextId),
                                      urduName: quran.getSurahName(nextId),
                                      verseCount: quran.getVerseCount(nextId),
                                    ),
                                  )));
                              },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1B4332).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF1B4332).withValues(alpha: 0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text('Next →',
                                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    Text(quran.getSurahName(widget.surah.id + 1),
                                        style: const TextStyle(fontWeight: FontWeight.bold,
                                            color: Color(0xFF1B4332))),
                                    Text(quran.getSurahNameArabic(widget.surah.id + 1),
                                        textDirection: TextDirection.rtl,
                                        style: GoogleFonts.amiriQuran(fontSize: 16)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }

                // index 1 → ayah 1, index 2 → ayah 2, etc.
                final ayahNum = index;
                final words = _ayahCache[ayahNum];
                // Pre-load translation as soon as ayah is visible
                if (_showTranslation) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _loadTranslation(ayahNum);
                  });
                }
                return Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Top row: known count + ayah badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (words != null)
                            Text(
                              '${words.where((w) => w.isKnown).length}/${words.length} known',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            )
                          else
                            const SizedBox(),
                          // Ayah number badge
                          
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B4332),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('﴾ $ayahNum ﴿',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                          // Juz/Ruku markers
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (ayahNum == 1 || 
                                  quran.getJuzNumber(widget.surah.id, ayahNum) !=
                                  quran.getJuzNumber(widget.surah.id, ayahNum - 1 < 1 ? 1 : ayahNum - 1))
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    'Juz ${quran.getJuzNumber(widget.surah.id, ayahNum)}',
                                    style: const TextStyle(fontSize: 9, color: Colors.teal),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    
                      const SizedBox(height: 8),
                      // Bookmark row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _toggleBookmark(ayahNum),
                            child: Icon(
                              _bookmarks.contains('${widget.surah.id}:$ayahNum')
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              color: _bookmarks.contains('${widget.surah.id}:$ayahNum')
                                  ? const Color(0xFFD4AF37)
                                  : Colors.grey,
                              size: 25,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),


                      // Loading spinner per ayah
                      if (words == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF1B4332)),
                            ),
                          ),
                        )
                      
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.end,
                              textDirection: TextDirection.rtl,
                              children: words
                                  .map((word) => WordTile(
                                        word: word,
                                        arabicFontSize: _arabicFontSize,
                                        urduFontSize: _urduFontSize,
                                        onLongPress: () => _onWordLongPress(word),
                                        onTap: () => _showWordDetail(word),
                                      ))
                                  .toList(),
                            ),
                            if (_showTranslation)
                              Builder(builder: (ctx) {
                                _loadTranslation(ayahNum);
                                final text = _ayahTranslations['$ayahNum'];
                                if (text == null) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    text,
                                    textDirection: TextDirection.rtl,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontFamily: 'JameelNoori',
                                      fontSize: _urduFontSize + 2,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      height: 1.7,
                                    ),
                                  ),
                                );
                              }),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          ), 
          
    );
  }
}

// ── Bismillah header widget ───────────────────────────────────────────────────
class _BismillahHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          quran.basmala,
          textDirection: TextDirection.rtl,
          style: GoogleFonts.amiriQuran(fontSize: 24).copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

// ── Word detail bottom sheet ──────────────────────────────────────────────────
//??????????????

class _FontChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FontChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
