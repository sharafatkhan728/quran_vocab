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
import '../data/ruku_data.dart';

class SurahReaderScreen extends StatefulWidget {
  final Surah surah;
  final int? jumpToAyah;
  const SurahReaderScreen({super.key, required this.surah, this.jumpToAyah});

  @override
  State<SurahReaderScreen> createState() => _SurahReaderScreenState();
}

class _SurahReaderScreenState extends State<SurahReaderScreen> {
  bool _mushafMode = false;
  int _lastReadAyah = 0;
  // key = display ayah number (1-based, always correct Islamic numbering)
  // value = list of words for that ayah
  final Map<int, List<QuranWord>> _ayahCache = {};
  final Set<int> _translationLoading = {};

  Set<String> _knownNormalizedWords = {};
  bool _isLoading = true;
  double _arabicFontSize = 32;
  double _urduFontSize = 16;

  // Translation
  final Map<String, String> _ayahTranslations =
      {}; // ayahNum → translation text
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
    _loadLastRead();
    _itemPositionsListener.itemPositions.addListener(() {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return;
      final first = positions
          .where((p) => p.itemLeadingEdge >= 0)
          .fold<ItemPosition?>(
              null,
              (prev, curr) =>
                  prev == null || curr.index < prev.index ? curr : prev);
      if (first != null && first.index > 0) {
        _saveLastRead(first.index);
      }
    });
    _loadScholar().then((_) => _loadAllTranslationsInstant());
  }

  Future<void> _loadLastRead() async {
    final prefs = await SharedPreferences.getInstance();
    _lastReadAyah = prefs.getInt('last_read_${widget.surah.id}') ?? 0;
  }

  Future<void> _saveLastRead(int ayahNum) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_read_${widget.surah.id}', ayahNum);
  }

  void _loadAllTranslationsInstant() {
    // Load from bundled JSON — instant, no API needed
    final surahTrans = TranslationService.getSurahTranslations(widget.surah.id);
    if (surahTrans.isNotEmpty && mounted) {
      setState(() => _ayahTranslations.addAll(surahTrans));
    }
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
    final key = '$ayahNum';
    if (_ayahTranslations.containsKey(key)) return;
    if (_translationLoading.contains(ayahNum)) return;

    // Try instant local cache first
    final instant =
        TranslationService.getAyahTranslation(widget.surah.id, ayahNum);
    // getAyahTranslation is async but bundled data resolves instantly
    final text = await instant;
    if (mounted && text != null) {
      setState(() {
        _translationLoading.remove(ayahNum);
        _ayahTranslations[key] = text;
      });
      return;
    }

    // Still loading from API
    if (mounted) setState(() => _translationLoading.add(ayahNum));
    final apiText =
        await TranslationService.getAyahTranslation(widget.surah.id, ayahNum);
    if (mounted) {
      setState(() {
        _translationLoading.remove(ayahNum);
        if (apiText != null) _ayahTranslations[key] = apiText;
      });
    }
  }

  Widget _buildMushafAyah(int ayahNum, List<QuranWord>? words) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = context.read<ThemeProvider>();

    if (words == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Center(
            child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFF1B4332)),
        )),
      );
    }

    // Build continuous text — all words in one Wrap
    return Container(
      decoration: BoxDecoration(
        // Subtle Islamic border for mushaf feel
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          alignment: WrapAlignment.end,
          textDirection: TextDirection.rtl,
          spacing: 0,
          runSpacing: 4,
          children: [
            // Words
            ...words.map((word) => GestureDetector(
                  onTap: () => _showWordDetail(word),
                  onLongPress: () => _onWordLongPress(word),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedOpacity(
                      opacity: word.isKnown ? 0.35 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        word.arabic,
                        textDirection: TextDirection.rtl,
                        style: _mushafWordStyle(isDark, theme),
                      ),
                    ),
                  ),
                )),
            // Ayah end marker ﴾number﴿
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                ' ﴿${_toArabicNumeral(ayahNum)}﴾',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: 'AmiriQuran',
                  fontSize: _arabicFontSize - 4,
                  color: const Color(0xFFD4AF37),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _mushafWordStyle(bool isDark, ThemeProvider theme) {
    final color = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final size = _arabicFontSize;
    switch (theme.arabicFont) {
      case 'indopak':
        return TextStyle(
            fontFamily: 'IndoPak', fontSize: size, color: color, height: 2.2);
      case 'noorehuda':
        return TextStyle(
            fontFamily: 'NoorehudaFont',
            fontSize: size,
            color: color,
            height: 2.2);
      default:
        return GoogleFonts.amiriQuran(
            fontSize: size, color: color, height: 2.2);
    }
  }

  String _toArabicNumeral(int n) {
    const numerals = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((d) => numerals[int.parse(d)]).join();
  }

  Future<void> _preloadAllTranslations() async {
    try {
      final url =
          'https://api.alquran.cloud/v1/surah/${widget.surah.id}/$_selectedScholar';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final ayahs = data['data']['ayahs'] as List;
        final prefs = await SharedPreferences.getInstance();
        final Map<String, String> newTranslations = {};
        for (final a in ayahs) {
          final num = a['numberInSurah'] as int;
          final text = a['text'] as String;
          final cacheKey = 'trans_${_selectedScholar}_${widget.surah.id}_$num';
          await prefs.setString(cacheKey, text);
          newTranslations['$num'] = text;
        }
        if (mounted) setState(() => _ayahTranslations.addAll(newTranslations));
      }
    } catch (_) {}
  }

  void _showScholarPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Select Translation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...TranslationService.scholars.entries.map((e) => ListTile(
                title: Text(e.value.name),
                trailing: _selectedScholar == e.key
                    ? const Icon(Icons.check, color: Color(0xFF1B4332))
                    : null,
                onTap: () async {
                  Navigator.pop(sheetContext); // close sheet first, only once
                  await TranslationService.setScholar(e.key);
                  if (!mounted) return;
                  setState(() {
                    _selectedScholar = e.key;
                    _ayahTranslations.clear();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                          SizedBox(width: 12),
                          Text('Switching translation...'),
                        ],
                      ),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  _preloadAllTranslations();
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

        for (final verse in verses) {
          final ayahNum = verse['verse_number'] as int;
          final displayAyah = ayahNum;

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
        debugPrint('SurahReader: API status error ${response.statusCode}');
        _buildFallback();
      }
    } catch (e) {
      debugPrint('SurahReader: fetch error $e');

      if (mounted) {
        _buildFallback();

        setState(() {
          _totalAyahs = _ayahCache.keys.length;
        });
        // Preload all translations in background
        _preloadAllTranslations();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);

        // Preload all translations for this surah in background
        // TranslationService.preloadSurahTranslations(widget.surah.id);

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
    debugPrint('SurahReader: using fallback, totalAyahs=$_totalAyahs');
    if (_totalAyahs == 0) {
      _totalAyahs = quran.getVerseCount(widget.surah.id);
    }
    debugPrint('SurahReader: fallback totalAyahs set to $_totalAyahs');
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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: StatefulBuilder(
          builder: (ctx, setModal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Font Settings',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 20),
              Text('Arabic size: ${_arabicFontSize.round()}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface)),
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
              Text('Urdu size: ${_urduFontSize.round()}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface)),
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
              Text('Arabic Font Style',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              Consumer<ThemeProvider>(
                builder: (context, theme, _) => Wrap(
                  spacing: 8,
                  children: [
                    _FontChip(
                      label: 'Uthmani',
                      selected: theme.arabicFont == 'uthmani',
                      onTap: () => theme.setArabicFont('uthmani'),
                    ),
                    _FontChip(
                      label: 'Indo-Pak',
                      selected: theme.arabicFont == 'indopak',
                      onTap: () => theme.setArabicFont('indopak'),
                    ),
                    _FontChip(
                      label: 'Noorehuda',
                      selected: theme.arabicFont == 'noorehuda',
                      onTap: () => theme.setArabicFont('noorehuda'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
            IconButton(
              icon: Icon(
                _mushafMode ? Icons.view_agenda_outlined : Icons.menu_book,
                color: Colors.white,
              ),
              tooltip: _mushafMode ? 'Card Mode' : 'Mushaf Mode',
              onPressed: () => setState(() => _mushafMode = !_mushafMode),
            ),
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
              icon: Icon(
                  _showTranslation ? Icons.visibility : Icons.visibility_off),
              onPressed: () =>
                  setState(() => _showTranslation = !_showTranslation),
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
            : Column(
                children: [
                  // Resume banner
                  if (_lastReadAyah > 1)
                    GestureDetector(
                      onTap: () {
                        _itemScrollController.jumpTo(
                          index: _lastReadAyah,
                          alignment: 0.0,
                        );
                        setState(() => _lastReadAyah = 0); // hide after tap
                      },
                      child: Container(
                        width: double.infinity,
                        color: const Color(0xFF1B4332),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.restore,
                                color: Colors.white70, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Resume from Ayah $_lastReadAyah',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                            const Spacer(),
                            const Icon(Icons.arrow_forward_ios,
                                color: Color(0xFFD4AF37), size: 14),
                          ],
                        ),
                      ),
                    ),

                  Expanded(
                    child: GestureDetector(
                      onScaleStart: (_) => _lastScale = _pinchScale,
                      onScaleUpdate: (d) {
                        if (d.pointerCount < 2) return;
                        setState(() {
                          _pinchScale = (_lastScale * d.scale).clamp(0.7, 2.0);
                          _arabicFontSize = (26 * _pinchScale).clamp(14, 52);
                          _urduFontSize = (13 * _pinchScale).clamp(10, 26);
                        });
                      },
                      child: Stack(
                        children: [
                          // Mushaf parchment background
                          if (_mushafMode)
                            Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? const Color(0xFF0F1A0F)
                                    : const Color(0xFFFDF6E3),
                              ),
                            ),
                          // Mushaf decorative border frame
                          if (_mushafMode)
                            Positioned.fill(
                              child: Container(
                                margin: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFD4AF37)
                                        .withValues(alpha: 0.4),
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ScrollablePositionedList.builder(
                            itemScrollController: _itemScrollController,
                            itemPositionsListener: _itemPositionsListener,
                            padding: _mushafMode
                                ? const EdgeInsets.fromLTRB(12, 8, 12, 16)
                                : const EdgeInsets.all(16),

                            itemCount: _totalAyahs + 2,
                            itemBuilder: (context, index) {
                              // index 0 = bismillah header
                              if (index == 0) {
                                if (!_showBismillahHeader)
                                  return const SizedBox.shrink();
                                return _BismillahHeader();
                              }

                              if (index == _totalAyahs + 1) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(0, 16, 0, 32),
                                  child: Row(
                                    children: [
                                      if (widget.surah.id > 1)
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () {
                                              final prevId =
                                                  widget.surah.id - 1;
                                              Navigator.pushReplacement(
                                                  context,
                                                  MaterialPageRoute(
                                                      builder: (_) =>
                                                          SurahReaderScreen(
                                                            surah: Surah(
                                                              id: prevId,
                                                              englishName: quran
                                                                  .getSurahName(
                                                                      prevId),
                                                              arabicName: quran
                                                                  .getSurahNameArabic(
                                                                      prevId),
                                                              urduName: quran
                                                                  .getSurahName(
                                                                      prevId),
                                                              verseCount: quran
                                                                  .getVerseCount(
                                                                      prevId),
                                                            ),
                                                          )));
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1B4332)
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                    color:
                                                        const Color(0xFF1B4332)
                                                            .withValues(
                                                                alpha: 0.3)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Text('← Previous',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey)),
                                                  Text(
                                                      quran.getSurahName(
                                                          widget.surah.id - 1),
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                              0xFF1B4332))),
                                                  Text(
                                                      quran.getSurahNameArabic(
                                                          widget.surah.id - 1),
                                                      textDirection:
                                                          TextDirection.rtl,
                                                      style: GoogleFonts
                                                          .amiriQuran(
                                                              fontSize: 16)),
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
                                              final nextId =
                                                  widget.surah.id + 1;
                                              Navigator.pushReplacement(
                                                  context,
                                                  MaterialPageRoute(
                                                      builder: (_) =>
                                                          SurahReaderScreen(
                                                            surah: Surah(
                                                              id: nextId,
                                                              englishName: quran
                                                                  .getSurahName(
                                                                      nextId),
                                                              arabicName: quran
                                                                  .getSurahNameArabic(
                                                                      nextId),
                                                              urduName: quran
                                                                  .getSurahName(
                                                                      nextId),
                                                              verseCount: quran
                                                                  .getVerseCount(
                                                                      nextId),
                                                            ),
                                                          )));
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1B4332)
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                    color:
                                                        const Color(0xFF1B4332)
                                                            .withValues(
                                                                alpha: 0.3)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  const Text('Next →',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey)),
                                                  Text(
                                                      quran.getSurahName(
                                                          widget.surah.id + 1),
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                              0xFF1B4332))),
                                                  Text(
                                                      quran.getSurahNameArabic(
                                                          widget.surah.id + 1),
                                                      textDirection:
                                                          TextDirection.rtl,
                                                      style: GoogleFonts
                                                          .amiriQuran(
                                                              fontSize: 16)),
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

                              if (_mushafMode) {
                                return _buildMushafAyah(ayahNum, words);
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 2),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Theme.of(context).dividerColor),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    // Top row: known count + ayah badge
                                    Row(
                                      children: [
                                        // Known count + Bookmark together (left)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (words != null)
                                              Text(
                                                '${words.where((w) => w.isKnown).length}/${words.length}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              )
                                            else
                                              const SizedBox(),

                                            const SizedBox(width: 6),
                                            // Bookmark button (left)
                                            GestureDetector(
                                              onTap: () =>
                                                  _toggleBookmark(ayahNum),
                                              child: Icon(
                                                _bookmarks.contains(
                                                        '${widget.surah.id}:$ayahNum')
                                                    ? Icons.bookmark
                                                    : Icons.bookmark_border,
                                                color: _bookmarks.contains(
                                                        '${widget.surah.id}:$ayahNum')
                                                    ? const Color(0xFFD4AF37)
                                                    : Colors.grey,
                                                size: 20,
                                              ),
                                            ),
                                          ],
                                        ),

                                        const Spacer(),

                                        //
                                        // Ruku marker (center-right)
                                        if (RukuData.rukuEnds[widget.surah.id]
                                                ?.contains(ayahNum) ??
                                            false)
                                          Builder(
                                            builder: (_) {
                                              final rukuNumber = (RukuData
                                                          .rukuEnds[
                                                              widget.surah.id]
                                                          ?.indexOf(ayahNum) ??
                                                      -1) +
                                                  1;

                                              return Container(
                                                margin: const EdgeInsets.only(
                                                    right: 6),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.deepPurple
                                                      .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: Colors.deepPurple
                                                        .withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                child: Text(
                                                  'ع $rukuNumber',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.deepPurple,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),

                                        // Juz center
                                        Builder(builder: (_) {
                                          final juz = quran.getJuzNumber(
                                              widget.surah.id, ayahNum);
                                          final prevJuz = ayahNum > 1
                                              ? quran.getJuzNumber(
                                                  widget.surah.id, ayahNum - 1)
                                              : 0;
                                          if (juz != prevJuz) {
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                  right: 6),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.teal
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                    color: Colors.teal
                                                        .withValues(
                                                            alpha: 0.4)),
                                              ),
                                              child: Text('Juz $juz',
                                                  style: const TextStyle(
                                                      fontSize: 9,
                                                      color: Colors.teal)),
                                            );
                                          }
                                          return const SizedBox.shrink();
                                        }),

                                        // Ayah number (right)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1B4332),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text('﴾ $ayahNum ﴿',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12)),
                                        ),
                                      ],
                                    ),

                                    // Loading spinner per ayah
                                    if (words == null)
                                      const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 20),
                                        child: Center(
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFF1B4332)),
                                          ),
                                        ),
                                      )
                                    else
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Wrap(
                                            alignment: WrapAlignment.end,
                                            textDirection: TextDirection.rtl,
                                            children: words
                                                .map((word) => WordTile(
                                                      word: word,
                                                      arabicFontSize:
                                                          _arabicFontSize,
                                                      urduFontSize:
                                                          _urduFontSize,
                                                      onLongPress: () =>
                                                          _onWordLongPress(
                                                              word),
                                                      onTap: () =>
                                                          _showWordDetail(word),
                                                    ))
                                                .toList(),
                                          ),
                                          if (_showTranslation)
                                            Builder(builder: (ctx) {
                                              _loadTranslation(ayahNum);
                                              final text =
                                                  _ayahTranslations['$ayahNum'];
                                              if (text == null)
                                                return const SizedBox.shrink();
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 8),
                                                child: Text(
                                                  text,
                                                  textDirection:
                                                      TextDirection.rtl,
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                    fontFamily: 'JameelNoori',
                                                    fontSize: _urduFontSize + 2,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
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
                            }, // itemBuilder
                          ), // ScrollablePositionedList.builder
                        ], // Stack children
                      ), // Stack
                    ), // GestureDetector
                  ), // Expanded Expanded
                ], // Column
              ));
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
