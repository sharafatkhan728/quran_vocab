// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:quran/quran.dart' as quran;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/surah.dart';
import '../models/word.dart';
import '../providers/theme_provider.dart';
import '../providers/display_provider.dart';
import '../repositories/content_repository.dart';
import '../services/translation_service.dart';
import '../services/word_glossary_service.dart';
import '../services/word_progress_service.dart';
import '../widgets/word_tile.dart';
import '../widgets/word_detail_dialog.dart';

class SurahReaderScreen extends StatefulWidget {
  final Surah surah;
  final int? jumpToAyah;

  const SurahReaderScreen({super.key, required this.surah, this.jumpToAyah});

  @override
  State<SurahReaderScreen> createState() => _SurahReaderScreenState();
}

class _SurahReaderScreenState extends State<SurahReaderScreen> {
  // ── State ─────────────────────────────────────────────────────────────────
  bool _mushafMode = false;
  int _lastReadAyah = 0;

  // ayahNumber → list of words — populated progressively
  final Map<int, List<QuranWord>> _ayahCache = {};
  Set<String> _knownNormalizedWords = {};
  bool _isLoading = true;

  double _arabicFontSize = 32;
  double _urduFontSize = 16;

  // ayahNumber → translation text
  final Map<int, String> _ayahTranslations = {};
  bool _showTranslation = true;

  Set<String> _bookmarks = {};
  double _pinchScale = 1.0;
  double _lastScale = 1.0;

  int _totalAyahs = 0;
  String _selectedLang = 'ur';

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  bool get _showBismillahHeader => widget.surah.id != 9 && widget.surah.id != 1;

  @override
  void initState() {
    super.initState();
    _selectedLang = WordGlossaryService.selectedLang;
    _initData();
    _itemPositionsListener.itemPositions.addListener(_onScroll);
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final visible = positions.where((p) => p.itemLeadingEdge >= 0);
    if (visible.isEmpty) return;
    final first =
        visible.reduce((a, b) => a.itemLeadingEdge < b.itemLeadingEdge ? a : b);
    if (first.index > 0 && first.index <= _totalAyahs) {
      ContentRepository.saveLastReadAyah(widget.surah.id, first.index);
    }
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _initData() async {
    await Future.wait([
      _loadKnownWords(),
      _loadBookmarks(),
      _loadLastRead(),
    ]);

    final ayahRows = await ContentRepository.getAyahsForSurah(widget.surah.id);
    if (!mounted) return;
    setState(() {
      _totalAyahs = ayahRows.length;
      _isLoading = false;
    });

    if (widget.jumpToAyah != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_itemScrollController.isAttached) {
          _itemScrollController.jumpTo(
              index: widget.jumpToAyah!, alignment: 0.0);
        }
      });
    }

    _loadAllTranslations();
    await _loadWordsProgressively(ayahRows);
  }

  Future<void> _loadKnownWords() async {
    final known = await WordProgressService.getAllKnownWords();
    if (mounted) setState(() => _knownNormalizedWords = known);
  }

  Future<void> _loadLastRead() async {
    final ayah = await ContentRepository.getLastReadAyah(widget.surah.id);
    if (mounted) setState(() => _lastReadAyah = ayah);
  }

  Future<void> _loadBookmarks() async {
    final bmarks =
        await ContentRepository.getBookmarksForSurah(widget.surah.id);
    if (mounted) setState(() => _bookmarks = bmarks);
  }

  Future<void> _loadAllTranslations() async {
    final map =
        await TranslationService.getSurahTranslationsAsync(widget.surah.id);
    if (!mounted) return;
    setState(() {
      _ayahTranslations.clear();
      for (final e in map.entries) {
        final num = int.tryParse(e.key);
        if (num != null) _ayahTranslations[num] = e.value;
      }
    });
  }

  Future<void> _loadWordsProgressively(List<AyahRow> ayahRows) async {
    const batchSize = 5;
    for (int i = 0; i < ayahRows.length; i += batchSize) {
      if (!mounted) return;
      final end = (i + batchSize).clamp(0, ayahRows.length);
      final batch = ayahRows.sublist(i, end);

      final Map<int, List<QuranWord>> built = {};
      for (final ayah in batch) {
        built[ayah.ayahNumber] = await _buildWordsForAyah(ayah);
      }

      if (!mounted) return;
      setState(() => _ayahCache.addAll(built));
      await Future.delayed(Duration.zero);
    }
  }

  /// Builds word list from SQLite ayah_words table.
  /// Morphology positions match the glossary keys exactly — no split() mismatch.
  Future<List<QuranWord>> _buildWordsForAyah(AyahRow ayah) async {
    final wordRows = await ContentRepository.getWordsForAyah(ayah.id);
    final translations = await ContentRepository.getWordTranslationsForAyah(
        ayah.id, _selectedLang);
    final morphSegments = await ContentRepository.getSegmentsForAyah(ayah.id);

    final result = <QuranWord>[];
    for (final wr in wordRows) {
      final meaning = translations[wr.id]?[_selectedLang]?.text ?? '';
      final segRows = morphSegments[wr.id] ?? [];
      final segments = segRows.map(WordSegment.fromRow).toList();
      final normalized = WordProgressService.normalizeArabic(wr.arabicText);

      result.add(QuranWord(
        id: '${widget.surah.id}:${ayah.ayahNumber}:${wr.position}',
        arabic: wr.arabicText,
        urduMeaning: meaning,
        isKnown: _knownNormalizedWords.contains(normalized),
        isWaqf: wr.isWaqf == 1,
        segments: segments,
      ));
    }
    return result;
  }

  Future<void> _reloadWithNewLanguage() async {
    if (!mounted) return;
    _ayahCache.clear();
    setState(() => _isLoading = true);

    final ayahRows = await ContentRepository.getAyahsForSurah(widget.surah.id);
    if (!mounted) return;
    setState(() {
      _totalAyahs = ayahRows.length;
      _isLoading = false;
    });
    _loadAllTranslations();
    await _loadWordsProgressively(ayahRows);
  }

  // ── User interactions ─────────────────────────────────────────────────────

  Future<void> _toggleBookmark(int ayahNum) async {
    await ContentRepository.toggleBookmark(widget.surah.id, ayahNum);
    final updated =
        await ContentRepository.getBookmarksForSurah(widget.surah.id);
    if (mounted) setState(() => _bookmarks = updated);
    HapticFeedback.lightImpact();
  }

  Future<void> _onWordLongPress(QuranWord word) async {
    final nowKnown = await WordProgressService.toggleWord(word.arabic);
    final normalized = WordProgressService.normalizeArabic(word.arabic);
    if (!mounted) return;
    setState(() {
      if (nowKnown) {
        _knownNormalizedWords.add(normalized);
      } else {
        _knownNormalizedWords.remove(normalized);
      }
      for (final ayahNum in _ayahCache.keys) {
        _ayahCache[ayahNum] = _ayahCache[ayahNum]!.map((w) {
          if (WordProgressService.normalizeArabic(w.arabic) == normalized) {
            return w.copyWith(isKnown: nowKnown);
          }
          return w;
        }).toList();
      }
    });
    WordProgressService.recalculateAllSurahProgress();
    if (mounted) {
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
    if (word.isWaqf) return;
    final parts = word.id.split(':');
    final ayahNum = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => WordDetailDialog(
        word: word,
        surahId: widget.surah.id,
        ayahId: ayahNum,
        isKnown: _knownNormalizedWords
            .contains(WordProgressService.normalizeArabic(word.arabic)),
        ayahWords: _ayahCache[ayahNum] ?? [],
        onKnownToggled: (nowKnown) {
          final normalized = WordProgressService.normalizeArabic(word.arabic);
          setState(() {
            if (nowKnown) {
              _knownNormalizedWords.add(normalized);
            } else {
              _knownNormalizedWords.remove(normalized);
            }
            for (final ayah in _ayahCache.keys) {
              _ayahCache[ayah] = _ayahCache[ayah]!.map((w) {
                if (WordProgressService.normalizeArabic(w.arabic) ==
                    normalized) {
                  return w.copyWith(isKnown: nowKnown);
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

  // ── Settings UI ───────────────────────────────────────────────────────────

  void _showScholarPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Select Translation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...TranslationService.scholars.entries.map((e) => ListTile(
                title: Text(e.value.name),
                trailing: TranslationService.selectedScholar == e.key
                    ? const Icon(Icons.check, color: Color(0xFF1B4332))
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await TranslationService.setScholar(e.key);
                  if (!mounted) return;
                  setState(() => _ayahTranslations.clear());
                  await _loadAllTranslations();
                },
              )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: StatefulBuilder(
          builder: (_, setModal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Display Settings',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 20),
              Text('Arabic size: ${_arabicFontSize.round()}'),
              Slider(
                value: _arabicFontSize,
                min: 18,
                max: 50,
                divisions: 16,
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
                divisions: 10,
                activeColor: const Color(0xFF1B4332),
                onChanged: (v) {
                  setModal(() => _urduFontSize = v);
                  setState(() => _urduFontSize = v);
                },
              ),
              const SizedBox(height: 8),
              Text('Arabic Font',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              Consumer<ThemeProvider>(
                builder: (_, theme, __) => Wrap(
                  spacing: 8,
                  children: [
                    _fontChip('Uthmani', 'uthmani', theme, setModal),
                    _fontChip('IndoPak', 'indopak', theme, setModal),
                    _fontChip('Noorehuda', 'noorehuda', theme, setModal),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Meaning Language'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: WordGlossaryService.glossaries.entries.map((e) {
                  final sel = _selectedLang == e.key;
                  return GestureDetector(
                    onTap: () async {
                      setState(() => _selectedLang = e.key);
                      await WordGlossaryService.setLanguage(e.key);
                      setModal(() {});
                      await _reloadWithNewLanguage();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            sel ? const Color(0xFF1B4332) : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel
                              ? const Color(0xFF1B4332)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(e.value.name,
                          style: TextStyle(
                              color: sel ? Colors.white : Colors.grey,
                              fontSize: 12,
                              fontWeight:
                                  sel ? FontWeight.bold : FontWeight.normal)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fontChip(
      String label, String key, ThemeProvider theme, StateSetter setModal) {
    final display = context.read<DisplayProvider>();
    final sel = display.arabicFont == key;
    return GestureDetector(
      onTap: () {
        display.setArabicFont(key);
        setModal(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              color:
                  sel ? Colors.white : Theme.of(context).colorScheme.onSurface,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            )),
      ),
    );
  }

  // ── Arabic numeral helper ─────────────────────────────────────────────────

  String _toArabicNumeral(int n) {
    const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => d[int.parse(c)]).join();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFFDF8F0),
      appBar: AppBar(
        title: Column(children: [
          Text(widget.surah.arabicName, style: const TextStyle(fontSize: 20)),
          Text(
              '${widget.surah.englishName} • ${widget.surah.verseCount} verses',
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B4332),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
                _mushafMode ? Icons.view_agenda_outlined : Icons.menu_book),
            onPressed: () => setState(() => _mushafMode = !_mushafMode),
          ),
          Consumer<ThemeProvider>(
            builder: (_, theme, __) => IconButton(
              icon: Icon(theme.isDark ? Icons.light_mode : Icons.dark_mode),
              onPressed: theme.toggleTheme,
            ),
          ),
          IconButton(
              icon: const Icon(Icons.translate), onPressed: _showScholarPicker),
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
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1B4332)))
          : Column(
              children: [
                // Resume banner
                if (_lastReadAyah > 1)
                  GestureDetector(
                    onTap: () {
                      if (_itemScrollController.isAttached) {
                        _itemScrollController.jumpTo(
                            index: _lastReadAyah, alignment: 0.0);
                      }
                      setState(() => _lastReadAyah = 0);
                    },
                    child: Container(
                      width: double.infinity,
                      color: const Color(0xFF1B4332),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(children: [
                        const Icon(Icons.restore,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text('Resume from Ayah $_lastReadAyah',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        const Spacer(),
                        const Icon(Icons.arrow_forward_ios,
                            color: Color(0xFFD4AF37), size: 14),
                      ]),
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
                    child: _mushafMode
                        ? _buildMushafList(isDark)
                        : _buildCardList(isDark),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Card mode ─────────────────────────────────────────────────────────────

  Widget _buildCardList(bool isDark) {
    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      padding: const EdgeInsets.all(12),
      itemCount: _totalAyahs + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _showBismillahHeader
              ? _BismillahHeader()
              : const SizedBox.shrink();
        }
        if (index == _totalAyahs + 1) return _buildNavigation();
        final ayahNum = index;
        return _buildCardAyah(ayahNum, _ayahCache[ayahNum], isDark);
      },
    );
  }

  Widget _buildCardAyah(int ayahNum, List<QuranWord>? words, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1A0F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(children: [
              if (words != null)
                Text(
                  '${words.where((w) => w.isKnown && !w.isWaqf).length}/${words.where((w) => !w.isWaqf).length}',
                  style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white38 : Colors.grey.shade400),
                ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _toggleBookmark(ayahNum),
                child: Icon(
                  _bookmarks.contains('${widget.surah.id}:$ayahNum')
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  color: _bookmarks.contains('${widget.surah.id}:$ayahNum')
                      ? const Color(0xFFD4AF37)
                      : Colors.grey,
                  size: 18,
                ),
              ),
              const Spacer(),
              // Juz badge
              Builder(builder: (_) {
                final juz = quran.getJuzNumber(widget.surah.id, ayahNum);
                final prevJuz = ayahNum > 1
                    ? quran.getJuzNumber(widget.surah.id, ayahNum - 1)
                    : 0;
                if (juz != prevJuz) {
                  return Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                    ),
                    child: Text('Juz $juz',
                        style:
                            const TextStyle(fontSize: 9, color: Colors.teal)),
                  );
                }
                return const SizedBox.shrink();
              }),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B4332),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('﴾ $ayahNum ﴿',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: words == null
                ? const Center(
                    heightFactor: 2,
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF1B4332)),
                    ))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.start,
                            crossAxisAlignment: WrapCrossAlignment.start,
                            textDirection: TextDirection.rtl,
                            children: words
                                .map<Widget>((word) => WordTile(
                                      word: word,
                                      onTap: () => _showWordDetail(word),
                                      onLongPress: () => _onWordLongPress(word),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                      if (_showTranslation &&
                          _ayahTranslations.containsKey(ayahNum)) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Text(
                          _ayahTranslations[ayahNum]!,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: 'JameelNoori',
                            fontSize: _urduFontSize + 2,
                            color:
                                isDark ? Colors.white60 : Colors.grey.shade700,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Mushaf mode ───────────────────────────────────────────────────────────

  Widget _buildMushafList(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A1E11) : const Color(0xFFFEFAF0),
        border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.5), width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        padding: const EdgeInsets.all(12),
        itemCount: _totalAyahs + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _showBismillahHeader
                ? _BismillahHeader()
                : const SizedBox.shrink();
          }
          if (index == _totalAyahs + 1) return _buildNavigation();
          return _buildMushafAyah(index, _ayahCache[index], isDark);
        },
      ),
    );
  }

  Widget _buildMushafAyah(int ayahNum, List<QuranWord>? words, bool isDark) {
    if (words == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
            child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFF1B4332)),
        )),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.start,
            textDirection: TextDirection.rtl,
            children: [
              ...words.map<Widget>((word) => GestureDetector(
                    onTap: () => _showWordDetail(word),
                    onLongPress: () => _onWordLongPress(word),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AnimatedOpacity(
                        opacity: word.isKnown ? 0.35 : 1.0,
                        duration: const Duration(milliseconds: 80),
                        child: Text(
                          word.arabic,
                          textDirection: TextDirection.rtl,
                          style: _mushafStyle(isDark),
                        ),
                      ),
                    ),
                  )),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  ' ﴿${_toArabicNumeral(ayahNum)}﴾ ',
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
      ),
    );
  }

  TextStyle _mushafStyle(bool isDark) {
    final color = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final display = context.read<DisplayProvider>();
    switch (display.arabicFont) {
      case 'indopak':
        return TextStyle(
            fontFamily: 'IndoPak',
            fontSize: _arabicFontSize,
            color: color,
            height: 2.2);
      case 'noorehuda':
        return TextStyle(
            fontFamily: 'NoorehudaFont',
            fontSize: _arabicFontSize,
            color: color,
            height: 2.2);
      default:
        return GoogleFonts.amiriQuran(
            fontSize: _arabicFontSize, color: color, height: 2.2);
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Widget _buildNavigation() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
      child: Row(children: [
        if (widget.surah.id > 1)
          Expanded(child: _navCard(widget.surah.id - 1, false)),
        if (widget.surah.id > 1 && widget.surah.id < 114)
          const SizedBox(width: 10),
        if (widget.surah.id < 114)
          Expanded(child: _navCard(widget.surah.id + 1, true)),
      ]),
    );
  }

  Widget _navCard(int surahId, bool isNext) {
    return GestureDetector(
      onTap: () => Navigator.pushReplacement(
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
                  ))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1B4332).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: const Color(0xFF1B4332).withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment:
              isNext ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(isNext ? 'Next →' : '← Previous',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(quran.getSurahName(surahId),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF1B4332))),
            Text(quran.getSurahNameArabic(surahId),
                textDirection: TextDirection.rtl,
                style: GoogleFonts.amiriQuran(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

// ── Bismillah header ──────────────────────────────────────────────────────────

class _BismillahHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1B4332).withValues(alpha: 0.3)
            : const Color(0xFFF0F7F0),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF1B4332).withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          quran.basmala,
          textDirection: TextDirection.rtl,
          style: GoogleFonts.amiriQuran(
              fontSize: 24, color: const Color(0xFF1B4332)),
        ),
      ),
    );
  }
}
