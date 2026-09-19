// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:quran/quran.dart' as quran;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../data/ruku_data.dart';
import '../models/surah.dart';
import '../models/word.dart';
import '../providers/theme_provider.dart';
import '../providers/display_provider.dart';
import '../database/database_importer.dart';
import '../database/database_manager.dart';
import '../repositories/content_repository.dart';
import '../services/translation_service.dart';
import '../services/word_glossary_service.dart';
import '../services/word_progress_service.dart';
import '../widgets/word_tile.dart';
import '../widgets/word_detail_dialog.dart';
import '../providers/learning_state_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/ayah_share_card.dart';

class SurahReaderScreen extends StatefulWidget {
  final Surah surah;
  final int? jumpToAyah;
  final int? jumpToAyahRequested;

  const SurahReaderScreen({super.key, required this.surah, this.jumpToAyah, this.jumpToAyahRequested});

  @override
  State<SurahReaderScreen> createState() => _SurahReaderScreenState();
}

class _SurahReaderScreenState extends State<SurahReaderScreen> {
  // ── State ─────────────────────────────────────────────────────────────────
  bool _mushafMode = false;
  int _lastReadAyah = 0;
  final bool _shouldJumpToTop = false;

  // ayahNumber → list of words — populated progressively
  final Map<int, List<QuranWord>> _ayahCache = {};
  bool _isLoading = true;

  // ── In-session cache (fast, resets when app process fully dies) ──────────
  static final Map<String, Map<int, List<QuranWord>>> _globalWordCache = {};
  static final Map<String, Map<int, String>> _globalTranslationCache = {};

  // Includes DatabaseImporter.contentCacheVersion so that whenever vocab or
  // morphology data is updated in a future app release (i.e. _vVocab or
  // _vMorphology is bumped), this key automatically changes — old disk/
  // memory caches simply stop matching and get silently rebuilt, with no
  // manual cache-clearing code needed anywhere.
  String get _wordCacheKey =>
      '${widget.surah.id}_${_selectedLang}_${DatabaseImporter.contentCacheVersion}';

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

  // ── Continuous Mushaf mode: separate scroll controller (not index-based) ──
  final ScrollController _mushafScrollController = ScrollController();
  // ayahNumber → GlobalKey anchored to that ayah's first word, used to
  // locate/scroll to a specific ayah inside the single continuous Wrap.
  final Map<int, GlobalKey> _ayahAnchorKeys = {};
  Timer? _mushafScrollDebounce;
  // Anchors the actual scroll viewport (not the whole screen/AppBar) so
  // _computeCurrentMushafAyah measures anchor positions from the right origin.
  final GlobalKey _mushafViewportKey = GlobalKey();

  bool get _showBismillahHeader => widget.surah.id != 9 && widget.surah.id != 1;

  /// Ruku number that ends at [ayahNum] in this surah, or null if this ayah
  /// isn't a ruku boundary. Used to show a "۩ Ruku N" divider after that ayah.
  int? _rukuEndingAt(int ayahNum) {
    final ends = RukuData.rukuEnds[widget.surah.id];
    if (ends == null) return null;
    final idx = ends.indexOf(ayahNum);
    return idx == -1 ? null : idx + 1;
  }

  LearningStateProvider? _learning;

  @override
  void initState() {
    super.initState();
    _selectedLang = WordGlossaryService.selectedLang;
    _loadReadingPrefs();
    _initData();
    _itemPositionsListener.itemPositions.addListener(_onScroll);
    _mushafScrollController.addListener(_onMushafScroll);
    TranslationLangService.langNotifier.addListener(_onTranslationLangChanged);
  }

  Future<void> _loadReadingPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showTranslation = prefs.getBool('show_ayah_translation') ?? true;
        if (prefs.getBool('mushaf_mode_default') ?? false) {
          _mushafMode = true;
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final learning = context.read<LearningStateProvider>();
    if (_learning != learning) {
      _learning?.removeListener(_onLearningStateChanged);
      _learning = learning;
      _learning!.addListener(_onLearningStateChanged);
    }
  }

  void _onLearningStateChanged() {
    // A known/unknown change anywhere (this screen, Vocabulary, Flashcards,
    // or a group-sync cascade to a related compound like وٱلذین when
    // ٱلذین is toggled) must be reflected here too. This only updates each
    // cached QuranWord's isKnown flag — it never touches scroll controllers
    // or _ayahCache's structure, so scroll position is unaffected.
    _refreshAllKnownFlags();
  }

  void _refreshAllKnownFlags() {
    if (!mounted || _ayahCache.isEmpty) return;
    final learning = context.read<LearningStateProvider>();
    setState(() {
      for (final ayahNum in _ayahCache.keys) {
        _ayahCache[ayahNum] = _ayahCache[ayahNum]!.map((w) {
          final normalized = WordProgressService.normalizeArabic(w.arabic);
          return w.copyWith(isKnown: learning.isKnown(normalized));
        }).toList();
      }
    });
  }

  void _onTranslationLangChanged() {
    _loadAllTranslations();
  }

  @override
  void dispose() {
    _learning?.removeListener(_onLearningStateChanged);
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    _mushafScrollController.removeListener(_onMushafScroll);
    _mushafScrollController.dispose();
    _mushafScrollDebounce?.cancel();
    TranslationLangService.langNotifier.removeListener(_onTranslationLangChanged);
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

  // ── Continuous Mushaf mode: position tracking ─────────────────────────────

  GlobalKey _keyForAyah(int ayahNum) {
    return _ayahAnchorKeys.putIfAbsent(
        ayahNum, () => GlobalKey(debugLabel: 'ayah_anchor_$ayahNum'));
  }

  /// Finds the ayah whose anchor (first word) sits closest to the top of the
  /// Mushaf viewport, using each anchor's live render position. This is the
  /// continuous-flow equivalent of ItemPositionsListener for Card mode.
  int? _computeCurrentMushafAyah() {
    final viewportBox =
        _mushafViewportKey.currentContext?.findRenderObject();
    if (viewportBox is! RenderBox || !viewportBox.attached) return null;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;

    int? best;
    double bestDy = double.infinity;
    for (final entry in _ayahAnchorKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final renderBox = ctx.findRenderObject();
      if (renderBox is! RenderBox || !renderBox.attached) continue;
      final relativeDy = renderBox.localToGlobal(Offset.zero).dy - viewportTop;
      // Prefer the topmost anchor that is at or just above the viewport top
      // (small negative tolerance so an ayah that just scrolled past still counts).
      if (relativeDy >= -40 && relativeDy < bestDy) {
        bestDy = relativeDy;
        best = entry.key;
      }
    }
    return best;
  }

  void _onMushafScroll() {
    _mushafScrollDebounce?.cancel();
    _mushafScrollDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted || !_mushafMode) return;
      final current = _computeCurrentMushafAyah();
      if (current != null && current > 0 && current <= _totalAyahs) {
        ContentRepository.saveLastReadAyah(widget.surah.id, current);
      }
    });
  }

  /// Waits until a specific ayah's words have loaded into the cache (needed
  /// before its GlobalKey anchor exists in the widget tree in Mushaf mode).
  Future<void> _waitForAyahLoaded(int ayahNum,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final start = DateTime.now();
    while (!_ayahCache.containsKey(ayahNum)) {
      if (!mounted) return;
      if (DateTime.now().difference(start) > timeout) return;
      await Future.delayed(const Duration(milliseconds: 40));
    }
  }

  /// Unified ayah navigation — works in both Card mode (index-based jump)
  /// and Mushaf mode (GlobalKey anchor + ensureVisible), so callers don't
  /// need to know which mode is active.
  Future<void> _scrollToAyah(int ayahNum, {bool animate = false}) async {
    if (ayahNum <= 0 || !mounted) return;
    if (_mushafMode) {
      final ctx = _ayahAnchorKeys[ayahNum]?.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.05,
          duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
          curve: Curves.easeInOut,
        );
      }
    } else {
      if (_itemScrollController.isAttached) {
        if (animate) {
          _itemScrollController.scrollTo(
              index: ayahNum, duration: const Duration(milliseconds: 300));
        } else {
          _itemScrollController.jumpTo(index: ayahNum, alignment: 0.0);
        }
      }
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

    if (widget.jumpToAyahRequested != null) {
      final target = widget.jumpToAyahRequested!;
      if (_mushafMode) {
        // Mushaf anchors only exist once that ayah's words are built, so
        // wait for its specific batch to load rather than the whole surah.
        _waitForAyahLoaded(target).then((_) {
          if (mounted) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _scrollToAyah(target));
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_itemScrollController.isAttached) {
            _itemScrollController.jumpTo(index: target, alignment: 0.0);
          }
        });
      }
    } else if (_lastReadAyah > 1) {
      // Resume from where user left off last time
      final target = _lastReadAyah;
      if (_mushafMode) {
        _waitForAyahLoaded(target).then((_) {
          if (mounted) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _scrollToAyah(target));
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _itemScrollController.isAttached) {
            _itemScrollController.jumpTo(index: target, alignment: 0.0);
          }
        });
      }
    }

    _loadAllTranslations();
    await _loadWordsProgressively(ayahRows);
  }

  Future<void> _loadKnownWords() async {
    // LearningStateProvider is the source of truth — no separate load needed
    if (mounted) setState(() {});
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
    final scholar = TranslationLangService.selectedScholar;
    final cacheKey = '${widget.surah.id}_$scholar';
    final cached = _globalTranslationCache[cacheKey];
    if (cached != null) {
      if (!mounted) return;
      setState(() {
        _ayahTranslations
          ..clear()
          ..addAll(cached);
      });
      return;
    }

    final map = await TranslationService.getSurahTranslationsAsync(
        widget.surah.id,
        scholar: scholar);
    if (!mounted) return;
    final parsed = <int, String>{};
    for (final e in map.entries) {
      final num = int.tryParse(e.key);
      if (num != null) parsed[num] = e.value;
    }
    _globalTranslationCache[cacheKey] = parsed;
    setState(() {
      _ayahTranslations
        ..clear()
        ..addAll(parsed);
    });
  }

  // ── Disk cache — survives full app close/reopen ───────────────────────────
  // A surah's built words are written once to a small JSON file in the app's
  // documents folder. Next launch (even after fully closing the app), that
  // file is read back instantly instead of re-querying SQLite and rebuilding
  // every QuranWord/segment from scratch.

  Future<File> _wordCacheFile(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    // Version is baked into the folder name too — when vocab/morphology data
    // is updated, this path changes, so old cache files are simply left
    // behind unused (harmless) instead of being incorrectly reused.
    final cacheDir = Directory(
        '${dir.path}/surah_word_cache_v${DatabaseImporter.contentCacheVersion}');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/$key.json');
  }

  Map<String, dynamic> _wordToJson(QuranWord w) => {
        'id': w.id,
        'arabic': w.arabic,
        'urduMeaning': w.urduMeaning,
        'isWaqf': w.isWaqf,
        'segments': w.segments
            .map((s) => {
                  'segNum': s.segNum,
                  'type': s.type.index,
                  'pos': s.pos,
                  'root': s.root,
                  'lemma': s.lemma,
                  'tense': s.tense,
                  'person': s.person,
                  'gender': s.gender,
                  'number': s.number,
                  'grammaticalCase': s.grammaticalCase,
                  'voice': s.voice,
                  'state': s.state,
                  'verbForm': s.verbForm,
                  'segArabic': s.arabic,
                  'colorHex': s.colorHex,
                })
            .toList(),
      };

  QuranWord _wordFromJson(Map<String, dynamic> j) => QuranWord(
        id: j['id'] as String,
        arabic: j['arabic'] as String,
        urduMeaning: j['urduMeaning'] as String? ?? '',
        isWaqf: j['isWaqf'] as bool? ?? false,
        // isKnown is intentionally never cached — it's always recomputed
        // live from LearningStateProvider at render time everywhere in this
        // screen, so caching it here could only ever show a stale value.
        segments: ((j['segments'] as List?) ?? [])
            .map((sj) => WordSegment(
                  segNum: sj['segNum'] as int? ?? 0,
                  type: SegType.values[(sj['type'] as int?) ?? 0],
                  pos: sj['pos'] as String? ?? '',
                  root: sj['root'] as String? ?? '',
                  lemma: sj['lemma'] as String? ?? '',
                  tense: sj['tense'] as String? ?? '',
                  person: sj['person'] as String? ?? '',
                  gender: sj['gender'] as String? ?? '',
                  number: sj['number'] as String? ?? '',
                  grammaticalCase: sj['grammaticalCase'] as String? ?? '',
                  voice: sj['voice'] as String? ?? '',
                  state: sj['state'] as String? ?? '',
                  verbForm: sj['verbForm'] as String? ?? '',
                  arabic: sj['segArabic'] as String? ?? '',
                  colorHex: sj['colorHex'] as String? ?? '#888888',
                ))
            .toList(),
      );

  Future<Map<int, List<QuranWord>>?> _readDiskWordCache(
      String key, int expectedAyahCount) async {
    try {
      final file = await _wordCacheFile(key);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded.length != expectedAyahCount) return null; // incomplete/stale
      return decoded.map((k, v) => MapEntry(
            int.parse(k),
            (v as List)
                .map((wj) => _wordFromJson(wj as Map<String, dynamic>))
                .toList(),
          ));
    } catch (_) {
      return null; // corrupt/missing cache — falls back to normal SQLite load
    }
  }

  Future<void> _writeDiskWordCache(
      String key, Map<int, List<QuranWord>> data) async {
    try {
      final file = await _wordCacheFile(key);
      final jsonMap = data.map((ayahNum, words) => MapEntry(
            '$ayahNum',
            words.map(_wordToJson).toList(),
          ));
      await file.writeAsString(jsonEncode(jsonMap));
    } catch (_) {
      // Non-fatal — worst case the surah just loads from SQLite again.
    }
  }

  Future<void> _loadWordsProgressively(List<AyahRow> ayahRows) async {
    final key = _wordCacheKey;

    // 1) Already loaded this session? Reuse the in-memory copy — fastest.
    final memCache = _globalWordCache[key];
    if (memCache != null && memCache.length == ayahRows.length) {
      if (mounted) setState(() => _ayahCache.addAll(memCache));
      return;
    }

    // 2) Not in memory (e.g. app was fully closed and reopened) — check the
    // on-disk cache written during a previous session.
    final diskCache = await _readDiskWordCache(key, ayahRows.length);
    if (diskCache != null) {
      _globalWordCache[key] = diskCache;
      if (!mounted) return;
      setState(() => _ayahCache.addAll(diskCache));
      return;
    }

    // 3) Truly first time for this surah+language — build from SQLite as
    // before, batch by batch, and persist the result to disk for next time.
    const batchSize = 5;
    final cacheForSurah = _globalWordCache.putIfAbsent(key, () => {});
    for (int i = 0; i < ayahRows.length; i += batchSize) {
      if (!mounted) return;
      final end = (i + batchSize).clamp(0, ayahRows.length);
      final batch = ayahRows.sublist(i, end);

      final Map<int, List<QuranWord>> built = {};
      for (final ayah in batch) {
        final words = await _buildWordsForAyah(ayah);
        built[ayah.ayahNumber] = words;
        cacheForSurah[ayah.ayahNumber] = words;
      }

      if (!mounted) return;
      setState(() => _ayahCache.addAll(built));
      await Future.delayed(Duration.zero);
    }

    if (cacheForSurah.length == ayahRows.length) {
      unawaited(_writeDiskWordCache(key, cacheForSurah)); // don't block UI
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
      if (result.isEmpty) {
        debugPrint('DEBUG surah=${widget.surah.id} ayah=${ayah.ayahNumber} _selectedLang=$_selectedLang wordRows=${wordRows.length} translations=${translations.length} firstMeaning="$meaning"');
      }
      final segRows = morphSegments[wr.id] ?? [];
      final segments = segRows.map(WordSegment.fromRow).toList();
      final normalized = WordProgressService.normalizeArabic(wr.arabicText);

      if (!mounted) break;
      final learning = context.read<LearningStateProvider>();
      result.add(QuranWord(
        id: '${widget.surah.id}:${ayah.ayahNumber}:${wr.position}',
        arabic: wr.arabicText,
        urduMeaning: meaning,
        isKnown: learning.isKnown(normalized),
        isWaqf: wr.isWaqf == 1,
        segments: segments,
      ));
    }
    return result;
  }

  Future<void> _reloadWithNewLanguage() async {
    if (!mounted) return;

    // Save current visible ayah before clearing cache
    int savedAyah = 0;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      final visible = positions.where((p) => p.itemLeadingEdge >= 0);
      if (visible.isNotEmpty) {
        savedAyah = visible
            .reduce((a, b) => a.itemLeadingEdge < b.itemLeadingEdge ? a : b)
            .index;
      }
    }

    // Clear cache but do NOT set _isLoading = true
    // This keeps the list visible (with old meanings) during reload
    // instead of jumping to top with a loading spinner
    setState(() => _ayahCache.clear());

    final ayahRows = await ContentRepository.getAyahsForSurah(widget.surah.id);
    if (!mounted) return;
    setState(() => _totalAyahs = ayahRows.length);

    _loadAllTranslations();
    await _loadWordsProgressively(ayahRows);

    // Restore scroll position after words are loaded
    if (savedAyah > 0 && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_itemScrollController.isAttached) {
          _itemScrollController.jumpTo(
              index: savedAyah, alignment: 0.0);
        }
      });
    }
  }

  // ── User interactions ─────────────────────────────────────────────────────

  Future<void> _toggleBookmark(int ayahNum) async {
    await ContentRepository.toggleBookmark(widget.surah.id, ayahNum);
    final updated =
        await ContentRepository.getBookmarksForSurah(widget.surah.id);
    if (mounted) setState(() => _bookmarks = updated);
    HapticFeedback.lightImpact();
  }


    Future<void> _shareAyah(int ayahNum) async {
    final words = _ayahCache[ayahNum];
    // Build full Arabic text from cached words
    final arabicText = words != null
        ? words.map((w) => w.arabic).join(' ')
        : '';
    final translation = _ayahTranslations[ayahNum] ?? '';
    final scholar = TranslationService
            .scholars[TranslationLangService.selectedScholar]?.name ??
        '';

    final display = context.read<DisplayProvider>();
    await AyahShareCard.share(
      context: context,
      surahId: widget.surah.id,
      surahNameEnglish: widget.surah.englishName,
      surahNameArabic: widget.surah.arabicName,
      ayahNumber: ayahNum,
      arabicText: arabicText,
      translation: translation,
      translationLang: _selectedLang,
      scholarName: scholar,
      arabicFont: display.arabicFont,
    );
  }

Future<void> _onWordLongPress(QuranWord word) async {
    final normalized = WordProgressService.normalizeArabic(word.arabic);
    final learning = context.read<LearningStateProvider>();
    final nowKnown = await learning.toggleByClean(normalized);
    if (!mounted) return;
    // Refresh every cached word's isKnown from the provider — not just the
    // toggled one — so a related compound (e.g. وٱلذین when ٱلذین is
    // toggled) updates in the UI too, without waiting for a manual scroll
    // or mode switch to trigger a rebuild.
    _refreshAllKnownFlags();
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
        isKnown: context.read<LearningStateProvider>()
            .isKnown(WordProgressService.normalizeArabic(word.arabic)),
        ayahWords: _ayahCache[ayahNum] ?? [],
        onKnownToggled: (_) => _refreshAllKnownFlags(),
      ),
    );
  }

  // ── Settings UI ───────────────────────────────────────────────────────────

  void _showTranslationPicker() {
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
                trailing: TranslationLangService.selectedScholar == e.key
                    ? const Icon(Icons.check, color: Color(0xFF1B4332))
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  // Use TranslationLangService — single source of truth
                  // This fires langNotifier which triggers _onTranslationLangChanged
                  await TranslationLangService.setScholar(e.key);
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFFDF8F0),
      appBar: AppBar(
        title: Column(children: [
          Text('${widget.surah.id}. ${widget.surah.arabicName}', style: const TextStyle(fontSize: 18)),
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
            onPressed: () {
              // Save current scroll position before mode switch, using
              // whichever position-tracking mechanism the CURRENT mode uses.
              int savedAyah = _lastReadAyah;
              if (_mushafMode) {
                savedAyah = _computeCurrentMushafAyah() ?? _lastReadAyah;
              } else {
                final positions = _itemPositionsListener.itemPositions.value;
                if (positions.isNotEmpty) {
                  final visible =
                      positions.where((p) => p.itemLeadingEdge >= 0);
                  if (visible.isNotEmpty) {
                    savedAyah = visible
                        .reduce((a, b) =>
                            a.itemLeadingEdge < b.itemLeadingEdge ? a : b)
                        .index;
                  }
                }
              }
              setState(() => _mushafMode = !_mushafMode);
              // Restore scroll position in the NEW mode after it rebuilds.
              if (savedAyah > 0 && mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (_mushafMode) {
                    await _waitForAyahLoaded(savedAyah);
                    if (mounted) _scrollToAyah(savedAyah);
                  } else if (_itemScrollController.isAttached) {
                    _itemScrollController.jumpTo(
                        index: savedAyah, alignment: 0.0);
                  }
                });
              }
            },
          ),
          Consumer<ThemeProvider>(
            builder: (_, theme, __) => IconButton(
              icon: Icon(theme.isDark ? Icons.light_mode : Icons.dark_mode),
              onPressed: theme.toggleTheme,
            ),
          ),
          IconButton(
              icon: const Icon(Icons.translate),
              onPressed: _showTranslationPicker),
          IconButton(
            icon: Icon(
                _showTranslation ? Icons.visibility : Icons.visibility_off),
            onPressed: () =>
                setState(() => _showTranslation = !_showTranslation),
          ),
          IconButton(
              icon: const Icon(Icons.arrow_upward),
              onPressed: _shouldJumpToTop
                  ? null
                  : () {
                      if (_mushafMode) {
                        _mushafScrollController.jumpTo(0);
                      } else if (_itemScrollController.isAttached) {
                        _itemScrollController.jumpTo(
                            index: 1, alignment: 0.0);
                      }
                    },
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
                if (!_shouldJumpToTop && _lastReadAyah > 1)
                  GestureDetector(
                    onTap: () async {
                      final target = _lastReadAyah;
                      setState(() => _lastReadAyah = 0);
                      if (_mushafMode) {
                        await _waitForAyahLoaded(target);
                      }
                      if (mounted) _scrollToAyah(target);
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
                      ? _buildMushafContinuous(isDark)
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
              ? _BismillahHeader(surah: widget.surah, knownWords: context.read<LearningStateProvider>().knownCount)
              : const SizedBox.shrink();
        }
        if (index == _totalAyahs + 1) return _buildNavigation();
        final ayahNum = index;
        final rukuNum = _rukuEndingAt(ayahNum);
        return Column(
          children: [
            _buildCardAyah(ayahNum, _ayahCache[ayahNum], isDark),
            if (rukuNum != null) _RukuDivider(rukuNumber: rukuNum),
          ],
        );
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
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _shareAyah(ayahNum),
                child: const Icon(Icons.share_outlined,
                    color: Colors.grey, size: 18),
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
                                .map<Widget>((word) {
                                  final normalized = WordProgressService
                                      .normalizeArabic(word.arabic);
                                  final lp = context
                                      .read<LearningStateProvider>();
                                  final live = word.copyWith(
                                      isKnown: lp.isKnown(normalized));
                                  return WordTile(
                                    word: live,
                                    onTap: () => _showWordDetail(live),
                                    onLongPress: () =>
                                        _onWordLongPress(live),
                                  );
                                })
                                .toList(),
                          ),
                        ),
                      ),
                      if (_showTranslation &&
                          _ayahTranslations.containsKey(ayahNum)) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Builder(builder: (_) {
                          final scholar =
                              TranslationLangService.selectedScholar;
                          final isUrdu = scholar.startsWith('ur');
                          return Text(
                            _ayahTranslations[ayahNum]!,
                            textDirection: isUrdu
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            textAlign: isUrdu
                                ? TextAlign.right
                                : TextAlign.left,
                            style: TextStyle(
                              fontFamily:
                                  isUrdu ? 'JameelNoori' : null,
                              fontSize: _urduFontSize + 2,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade700,
                              height: 1.7,
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Mushaf mode (continuous paragraph flow) ───────────────────────────────

  Widget _buildMushafContinuous(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A1E11) : Colors.white,
        border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.5), width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SingleChildScrollView(
        key: _mushafViewportKey,
        controller: _mushafScrollController,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showBismillahHeader) _BismillahHeader(surah: widget.surah, knownWords: context.read<LearningStateProvider>().knownCount),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                textDirection: TextDirection.rtl,
                children: _buildContinuousWords(isDark),
              ),
            ),
            const SizedBox(height: 12),
            _buildNavigation(),
          ],
        ),
      ),
    );
  }

  /// Flattens every loaded ayah's words into ONE list of inline widgets, so
  /// they render as a single continuous Wrap — ayah 2 can start on the same
  /// visual line where ayah 1 ends, exactly like a printed Mushaf. Each
  /// ayah's first word carries a GlobalKey anchor (via _keyForAyah) so we can
  /// later locate/scroll to that ayah with Scrollable.ensureVisible, since
  /// there is no per-ayah list index to jump to anymore.
  List<Widget> _buildContinuousWords(bool isDark) {
    final children = <Widget>[];
    for (int ayahNum = 1; ayahNum <= _totalAyahs; ayahNum++) {
      final words = _ayahCache[ayahNum];
      // Words load progressively in ayah order, so the first gap means
      // everything after it isn't ready yet.
      if (words == null) break;

      for (int i = 0; i < words.length; i++) {
        final word = words[i];
        final normalized = WordProgressService.normalizeArabic(word.arabic);
        final isKnown =
            context.read<LearningStateProvider>().isKnown(normalized);
        Widget wordWidget = GestureDetector(
          onTap: () => _showWordDetail(word),
          onLongPress: () => _onWordLongPress(word),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: 
              Text(
                word.arabic,
                textDirection: TextDirection.rtl,
                style: _mushafStyle(isDark).copyWith(
                  decoration: isKnown
                      ? TextDecoration.underline
                      : TextDecoration.none,
                  decorationColor: isDark
                      ? Colors.white.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.25),
                  decorationThickness: 1.0,
                ),
              ),
          ),
        );
        if (i == 0) {
          // Anchor the ayah's first word so _scrollToAyah can find it later.
          wordWidget =
              KeyedSubtree(key: _keyForAyah(ayahNum), child: wordWidget);
        }
        children.add(wordWidget);
      }

      // Ayah-end marker — plain English numeral in parentheses.
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            '($ayahNum)',
            style: TextStyle(
              fontSize: (_arabicFontSize * 0.42).clamp(11, 18),
              fontWeight: FontWeight.w600,
              color: const Color(0xFFD4AF37),
            ),
          ),
        ),
      ));

      final rukuNum = _rukuEndingAt(ayahNum);
      if (rukuNum != null) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.6)),
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
              ),
              child: Text(
                '۩ $rukuNum',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFD4AF37),
                ),
              ),
            ),
          ),
        ));
      }
    }
    return children;
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
        return GoogleFonts.amiri(
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
                style: GoogleFonts.amiri(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

// ── Bismillah header ──────────────────────────────────────────────────────────

class _BismillahHeader extends StatefulWidget {
  final Surah surah;
  final int knownWords;
  const _BismillahHeader({required this.surah, required this.knownWords});

  @override
  State<_BismillahHeader> createState() => _BismillahHeaderState();
}

class _BismillahHeaderState extends State<_BismillahHeader>
    with TickerProviderStateMixin {
  static const _gold = Color(0xFFD4AF37);
  static const _green = Color(0xFF1B4332);

  late AnimationController _entryCtrl;
  late AnimationController _shimmerCtrl;
  late Animation<double> _entryFade;
  late Animation<double> _entryScale;
  late Animation<double> _shimmer;

  int _surahKnownCount = 0;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _shimmerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));

    _entryFade = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _entryScale = Tween<double>(begin: 0.94, end: 1.0).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
        CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut));

    _entryCtrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _shimmerCtrl.forward();
      });
    });

    _loadSurahKnownCount();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSurahKnownCount() async {
    try {
      final db = await DatabaseManager.db;
      final rows = await db.rawQuery('''
        SELECT COUNT(DISTINCT kw.vocab_word_id) as cnt
        FROM known_words kw
        JOIN vocab_words v ON v.id = kw.vocab_word_id
        JOIN ayah_words aw ON aw.vocab_word_id = v.id
        JOIN ayahs a ON a.id = aw.ayah_id
        WHERE a.surah_id = ?
      ''', [widget.surah.id]);
      final cnt = (rows.first['cnt'] as int?) ?? 0;
      if (mounted) setState(() => _surahKnownCount = cnt);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final display = context.read<DisplayProvider>();
    final revelation = quran.getPlaceOfRevelation(widget.surah.id);
    final isMakki = revelation.toLowerCase().contains('mecca') ||
        revelation.toLowerCase().contains('makk');

    TextStyle arabicStyle;
    switch (display.arabicFont) {
      case 'indopak':
        arabicStyle = TextStyle(
            fontFamily: 'IndoPak',
            fontSize: display.arabicFontSize.clamp(24, 40),
            color: isDark ? _gold : _green,
            height: 2.0);
        break;
      case 'noorehuda':
        arabicStyle = TextStyle(
            fontFamily: 'NoorehudaFont',
            fontSize: display.arabicFontSize.clamp(24, 40),
            color: isDark ? _gold : _green,
            height: 2.0);
        break;
      default:
        arabicStyle = GoogleFonts.amiri(
            fontSize: display.arabicFontSize.clamp(24, 40),
            color: isDark ? _gold : _green,
            height: 2.0);
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_entryCtrl, _shimmerCtrl]),
      builder: (_, __) {
        return FadeTransition(
          opacity: _entryFade,
          child: ScaleTransition(
            scale: _entryScale,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          const Color(0xFF1B4332),
                          const Color(0xFF0D2418),
                          const Color(0xFF1A3A28),
                        ]
                      : [
                          const Color(0xFFFBF6E8),
                          const Color(0xFFF0F7F0),
                          const Color(0xFFFAF3E0),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: _gold.withValues(alpha: isDark ? 0.5 : 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _gold.withValues(alpha: isDark ? 0.15 : 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CustomPaint(
                  painter: _GeometricBorderPainter(isDark: isDark),
                  child: Stack(
                    children: [
                      // Shimmer overlay
                      if (_shimmerCtrl.isAnimating)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment(_shimmer.value - 0.5, 0),
                                  end: Alignment(_shimmer.value + 0.5, 0),
                                  colors: [
                                    Colors.transparent,
                                    _gold.withValues(alpha: 0.18),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                        child: Column(
                          children: [
                            // ── Ornamental row + Bismillah text ────────
                            Row(
                              children: [
                                // Left ornament
                                Text('❧',
                                    style: TextStyle(
                                        fontSize: 22,
                                        color: _gold.withValues(alpha: 0.7))),
                                // Bismillah text
                                Expanded(
                                  child: Text(
                                    quran.basmala,
                                    textDirection: TextDirection.rtl,
                                    textAlign: TextAlign.center,
                                    style: arabicStyle,
                                  ),
                                ),
                                // Right ornament
                                Text('❧',
                                    style: TextStyle(
                                        fontSize: 22,
                                        color: _gold.withValues(alpha: 0.7))),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // ── Info strip ─────────────────────────────
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Makki/Madani badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isMakki
                                        ? Colors.amber.withValues(alpha: 0.15)
                                        : Colors.teal.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isMakki
                                          ? Colors.amber.withValues(alpha: 0.5)
                                          : Colors.teal.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Text(
                                    isMakki ? '🕋 Makki' : '🕌 Madani',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isMakki
                                          ? (isDark
                                              ? Colors.amber.shade300
                                              : Colors.amber.shade800)
                                          : (isDark
                                              ? Colors.teal.shade300
                                              : Colors.teal.shade700),
                                    ),
                                  ),
                                ),

                                if (_surahKnownCount > 0) ...[
                                  const SizedBox(width: 8),
                                  // Known words in this surah
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.green.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.green
                                              .withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle_outline,
                                            size: 12,
                                            color: isDark
                                                ? Colors.green.shade300
                                                : Colors.green.shade700),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$_surahKnownCount words known',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.green.shade300
                                                : Colors.green.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Geometric border painter ──────────────────────────────────────────────────
class _GeometricBorderPainter extends CustomPainter {
  final bool isDark;
  static const _gold = Color(0xFFD4AF37);

  const _GeometricBorderPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _gold.withValues(alpha: isDark ? 0.18 : 0.12)
      ..style = PaintingStyle.fill;

    const dotR = 3.0;
    const spacing = 20.0;

    // Top edge dots
    for (double x = spacing; x < size.width - spacing; x += spacing) {
      canvas.drawCircle(Offset(x, 6), dotR * 0.6, paint);
    }
    // Bottom edge dots
    for (double x = spacing; x < size.width - spacing; x += spacing) {
      canvas.drawCircle(Offset(x, size.height - 6), dotR * 0.6, paint);
    }

    // Corner diamond ornaments
    final diamondPaint = Paint()
      ..color = _gold.withValues(alpha: isDark ? 0.25 : 0.18)
      ..style = PaintingStyle.fill;

    void drawDiamond(Offset center, double r) {
      final path = Path()
        ..moveTo(center.dx, center.dy - r)
        ..lineTo(center.dx + r, center.dy)
        ..lineTo(center.dx, center.dy + r)
        ..lineTo(center.dx - r, center.dy)
        ..close();
      canvas.drawPath(path, diamondPaint);
    }

    drawDiamond(const Offset(14, 14), 6);
    drawDiamond(Offset(size.width - 14, 14), 6);
    drawDiamond(Offset(14, size.height - 14), 6);
    drawDiamond(Offset(size.width - 14, size.height - 14), 6);
  }

  @override
  bool shouldRepaint(_GeometricBorderPainter old) => old.isDark != isDark;
}

// ── Ruku divider ───────────────────────────────────────────────────────────
class _RukuDivider extends StatelessWidget {
  final int rukuNumber;
  const _RukuDivider({required this.rukuNumber});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gold = const Color(0xFFD4AF37);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: gold.withValues(alpha: 0.4))),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: gold.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(20),
              color: gold.withValues(alpha: isDark ? 0.12 : 0.08),
            ),
            child: Text(
              '۩ Ruku $rukuNumber',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? gold : const Color(0xFF7A5C10),
              ),
            ),
          ),
          Expanded(child: Divider(color: gold.withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}