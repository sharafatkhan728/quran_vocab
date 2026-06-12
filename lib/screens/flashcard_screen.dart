import 'dart:math';
import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../providers/display_provider.dart';
import '../providers/user_provider.dart';
import '../services/srs_service.dart';
import '../services/word_progress_service.dart';
import '../services/quran_cache_service.dart';
import '../services/translation_service.dart';
import '../services/morphology_service.dart';
import 'morphology_sheet.dart';
import '../models/word.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── FlashWord model ─────────────────────────────────────────────────────────

class FlashWord {
  final String arabic;
  final String urdu;
  final int frequency;
  final String normalizedArabic;
  String transliteration = '';
  String root = '';
  String sampleAyahArabic = '';
  String sampleAyahTranslation = '';
  int sampleSurah = 0;
  int sampleAyahNum = 0;
  bool ayahLoaded = false;
  bool rootLoaded = false;
  int wordPositionInAyah = 1;

  FlashWord({
    required this.arabic,
    required this.urdu,
    required this.frequency,
  }) : normalizedArabic = arabic
            .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
            .trim() {
    transliteration = normalizedArabic;
  }

  Future<void> loadAyah() async {
    if (ayahLoaded) return;
    ayahLoaded = true;

    // Search the local Quran cache for correct ayah
    final found = QuranCacheService.findAyahForWord(normalizedArabic);
    if (found != null) {
      sampleAyahArabic = found['arabic'] as String;
      sampleSurah = found['surah'] as int;
      sampleAyahNum = found['ayah'] as int;
      wordPositionInAyah = found['wordPos'] as int? ?? 1;
      final trans = await TranslationService.getAyahTranslation(
          sampleSurah, sampleAyahNum);
      sampleAyahTranslation = trans ?? '';
      return;
    }

    // Fallback: search visited surahs
    final prefs = await SharedPreferences.getInstance();
    for (int i = 1; i <= 114; i++) {
      final raw = prefs.getStringList('surah_word_counts_$i');
      if (raw == null) continue;
      final has = raw.any((e) {
        final p = e.split('|||');
        return p.isNotEmpty && p[0] == normalizedArabic;
      });
      if (has) {
        sampleSurah = i;
        sampleAyahNum = 1;
        final trans = await TranslationService.getAyahTranslation(i, 1);
        sampleAyahTranslation = trans ?? '';
        break;
      }
    }
  }


  Future<void> loadRoot() async {
    if (rootLoaded || root.isNotEmpty) return;
    rootLoaded = true;
    if (!MorphologyService.isLoaded) return;

    // Search morphology data for this normalized word
    // Try all surahs that have this word
    final prefs = await SharedPreferences.getInstance();
    for (int s = 1; s <= 114; s++) {
      final counts = prefs.getStringList('surah_word_counts_$s');
      if (counts == null) continue;
      final hasWord = counts.any((e) {
        final p = e.split('|||');
        return p.isNotEmpty && p[0] == normalizedArabic;
      });
      if (!hasWord) continue;

      // Found a surah — search all ayahs for this word
      final wordKeys = MorphologyService.getAllKeysForWord(normalizedArabic, s);
      if (wordKeys != null && wordKeys.isNotEmpty) {
        root = wordKeys;
        return;
      }
      break;
    }
  }
}

// ── Screen ──────────────────────────────────────────────────────────────────

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});
  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen>
    with TickerProviderStateMixin {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);
  static const _teal = Color(0xFF2D6A4F);

  List<FlashWord> _cards = [];
  int _currentIndex = 0;
  int _totalPoints = 0;
  int _sessionPoints = 0;
  bool _loading = true;
  bool _sessionDone = false;
  bool _isFlipped = false;
  bool _hasBeenFlipped = false;
  String? _swipeHint;
  double _dragX = 0;
  bool _isDragging = false;

  late AnimationController _flipCtrl;
  late AnimationController _entryCtrl;
  late AnimationController _dismissCtrl;
  late Animation<double> _flipAnim;
  late Animation<double> _entryScale;
  late Animation<double> _entryFade;
  late Animation<Offset> _dismissOffset;
  late Animation<double> _dismissFade;

  final AudioPlayer _audio = AudioPlayer();

  @override
  void initState() {
    super.initState();

    _flipCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _dismissCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));

    _flipAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOut));
    _entryScale = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutBack));
    _entryFade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _dismissOffset = Tween<Offset>(begin: Offset.zero, end: const Offset(2, 0))
        .animate(CurvedAnimation(parent: _dismissCtrl, curve: Curves.easeIn));
    _dismissFade = Tween<double>(begin: 1, end: 0)
        .animate(CurvedAnimation(parent: _dismissCtrl, curve: Curves.easeIn));

    _loadSession();
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    _entryCtrl.dispose();
    _dismissCtrl.dispose();
    _audio.dispose();
    super.dispose();
  }

  // ── Session loading ─────────────────────────────────────────────────────

  Future<void> _loadSession({bool forceNew = false}) async {
    setState(() => _loading = true);
    _totalPoints = await SrsService.getTotalPoints();

    final freq = await WordProgressService.getWordFrequencies();
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.frequency.compareTo(a.value.frequency));
    final allWords =
        sorted.where((e) => e.value.urdu.isNotEmpty).map((e) => e.key).toList();

    for (final w in allWords.take(500)) {
      await SrsService.initCard(w);
    }

    final userProvider = context.read<UserProvider>();
    final dailyGoal = userProvider.dailyGoal;

    final saved = forceNew ? null : await SrsService.loadSession();
    List<String> sessionWords;
    int startIndex = 0;

    if (saved != null && saved.words.isNotEmpty) {
      sessionWords = saved.words;
      startIndex = saved.index;
    } else {
      sessionWords =
          await SrsService.buildSession(allWords.take(500).toList(), dailyGoal);
    }

    if (sessionWords.isEmpty) {
      if (mounted)
        setState(() {
          _loading = false;
          _sessionDone = true;
        });
      return;
    }

    final cards = sessionWords.map((word) {
      final entry = freq[word];
      return FlashWord(
        arabic: word,
        urdu: entry?.urdu ?? '',
        frequency: entry?.frequency ?? 0,
      );
    }).toList();

    if (mounted) {
      setState(() {
        _cards = cards;
        _currentIndex = startIndex.clamp(0, cards.length - 1);
        _loading = false;
        _isFlipped = false;
        _hasBeenFlipped = false;
      });
      _entryCtrl.forward();
      _preloadCards(_currentIndex);
    }
  }

  Future<void> _preloadCards(int from) async {
    for (int i = from; i < (from + 4).clamp(0, _cards.length); i++) {
      await _cards[i].loadAyah();
      await _cards[i].loadRoot();
      if (mounted) setState(() {});
    }
  }

  FlashWord get _current => _cards[_currentIndex];

  // ── Actions ──────────────────────────────────────────────────────────────

  void _flip() {
    if (_hasBeenFlipped) return;
    HapticFeedback.lightImpact();
    _flipCtrl.forward();
    setState(() {
      _isFlipped = true;
      _hasBeenFlipped = true;
    });
  }

  Future<void> _swipeKnown() async {
    if (!_isFlipped) {
      _flip();
      return;
    }
    HapticFeedback.mediumImpact();
    final pts = await SrsService.markKnown(_current.arabic);
    await WordProgressService.markAsKnown(_current.arabic);
    setState(() {
      _sessionPoints += pts;
      _totalPoints += pts;
    });
    await _animateDismiss(toRight: true);
    _nextCard();
  }

  Future<void> _swipeUnknown() async {
    if (!_isFlipped) {
      _flip();
      return;
    }
    HapticFeedback.mediumImpact();
    await SrsService.markUnknown(_current.arabic);
    final remaining = _cards.length - _currentIndex - 1;
    if (remaining > 2) {
      final insertAt =
          _currentIndex + 1 + Random().nextInt(remaining.clamp(1, 5));
      final card = _cards[_currentIndex];
      _cards.insert(insertAt.clamp(0, _cards.length), card);
    }
    await _animateDismiss(toRight: false);
    _nextCard();
  }

  Future<void> _deleteCard() async {
    await SrsService.deleteCard(_current.arabic);
    await _animateDismiss(toRight: true);
    _nextCard();
  }

  Future<void> _animateDismiss({required bool toRight}) async {
    _dismissOffset = Tween<Offset>(
      begin: Offset(_dragX / MediaQuery.of(context).size.width, 0),
      end: Offset(toRight ? 2.0 : -2.0, 0),
    ).animate(CurvedAnimation(parent: _dismissCtrl, curve: Curves.easeIn));
    _dismissCtrl.reset();
    await _dismissCtrl.forward();
  }

  void _nextCard() {
    _dismissCtrl.reset();
    _flipCtrl.reset();
    _dragX = 0;
    if (_currentIndex + 1 >= _cards.length) {
      SrsService.clearSession();
      setState(() {
        _sessionDone = true;
        _isFlipped = false;
      });
    } else {
      setState(() {
        _currentIndex++;
        _isFlipped = false;
        _hasBeenFlipped = false;
        _swipeHint = null;
      });
      _entryCtrl.reset();
      _entryCtrl.forward();
      SrsService.saveSession(
          _cards.map((c) => c.arabic).toList(), _currentIndex);
      _preloadCards(_currentIndex);
    }
  }

  
  Future<void> _playAudio() async {
    final card = _current;
    if (card.sampleSurah == 0) return;
    HapticFeedback.lightImpact();
    try {
      final s = card.sampleSurah.toString().padLeft(3, '0');
      final a = card.sampleAyahNum.toString().padLeft(3, '0');
      final w = card.wordPositionInAyah.toString().padLeft(3, '0');
      final url = 'https://audio.qurancdn.com/wbw/${s}_${a}_${w}.mp3';
      await _audio.setUrl(url);
      await _audio.play();
    } catch (_) {}
  }

  void _openMorphology() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MorphologySheet(
        word: QuranWord(
          id: '0:0:0',
          arabic: _current.arabic,
          urduMeaning: _current.urdu,
          transliteration: _current.transliteration,
        ),
        surahId: _current.sampleSurah > 0 ? _current.sampleSurah : 1,
        ayahId: _current.sampleAyahNum > 0 ? _current.sampleAyahNum : 1,
        wordPos: 1,
        ayahWords: [],
        isKnown: false,
        onKnownToggled: (_) {},
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0A1628) : const Color(0xFFF0EBE0),
        appBar: AppBar(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          title: const Text('Flash Cards'),
        ),
        body: const Center(child: CircularProgressIndicator(color: _gold)),
      );
    }

    if (_sessionDone) return _buildSummaryScreen(isDark);
    if (_cards.isEmpty) return _buildAllDoneScreen(isDark);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF0EBE0),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: const Text('Flash Cards'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              const Icon(Icons.stars, color: _gold, size: 18),
              const SizedBox(width: 4),
              Text('$_totalPoints',
                  style: const TextStyle(
                      color: _gold, fontWeight: FontWeight.bold)),
            ]),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildProgress(isDark),
          Expanded(child: _buildCardArea(isDark)),
          _isFlipped ? _buildActionButtons(isDark) : _buildFlipHint(isDark),
        ],
      ),
    );
  }

  Widget _buildProgress(bool isDark) {
    final progress = (_currentIndex + 1) / _cards.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_currentIndex + 1} / ${_cards.length}',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.grey.shade600)),
              Row(children: [
                const Icon(Icons.stars, color: _gold, size: 14),
                const SizedBox(width: 4),
                Text('+$_sessionPoints',
                    style: const TextStyle(
                        fontSize: 12,
                        color: _gold,
                        fontWeight: FontWeight.bold)),
              ]),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(_gold),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardArea(bool isDark) {
    final display = context.watch<DisplayProvider>();
    final screenW = MediaQuery.of(context).size.width;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: GestureDetector(
        onTap: _flip,
        onHorizontalDragStart: (_) => setState(() => _isDragging = true),
        onHorizontalDragUpdate: (d) {
          if (!_isFlipped) return; // block drag before flip
          setState(() {
            _dragX += d.delta.dx;
            if (_dragX > 50)
              _swipeHint = 'known';
            else if (_dragX < -50)
              _swipeHint = 'unknown';
            else
              _swipeHint = null;
          });
        },
        onHorizontalDragEnd: (d) {
          setState(() => _isDragging = false);
          if (!_isFlipped) {
            setState(() {
              _dragX = 0;
              _swipeHint = null;
            });
            return;
          }
          final v = d.primaryVelocity ?? 0;
          if (_dragX > 80 || v > 400) {
            _swipeKnown();
          } else if (_dragX < -80 || v < -400) {
            _swipeUnknown();
          } else {
            setState(() {
              _dragX = 0;
              _swipeHint = null;
            });
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Behind card 3 (deepest) ──────────────────────────────
            Positioned(
              top: 0,
              left: 12,
              right: 12,
              child: Container(
                height: 24,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0A1E11)
                      : const Color(0xFFE8E2CF),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(color: _gold.withValues(alpha: 0.15)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
            // ── Behind card 2 ────────────────────────────────────────
            Positioned(
              top: 10,
              left: 6,
              right: 6,
              child: Container(
                height: 22,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F2518)
                      : const Color(0xFFF0EAD8),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(color: _gold.withValues(alpha: 0.25)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            // ── Main card ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: AnimatedBuilder(
                animation: Listenable.merge([_entryCtrl, _dismissCtrl]),
                builder: (_, child) {
                  if (_dismissCtrl.isAnimating) {
                    return SlideTransition(
                      position: _dismissOffset,
                      child:
                          FadeTransition(opacity: _dismissFade, child: child),
                    );
                  }
                  final tx = _isDragging ? _dragX : 0.0;
                  final rot = tx / screenW * 0.12;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..translate(tx, 0.0)
                      ..rotateZ(rot),
                    child: ScaleTransition(
                      scale: _entryScale,
                      child: FadeTransition(opacity: _entryFade, child: child),
                    ),
                  );
                },
                child: Stack(
                  children: [
                    // Flip animation
                    AnimatedBuilder(
                      animation: _flipAnim,
                      builder: (_, __) {
                        final angle = _flipAnim.value * pi;
                        final showFront = angle < pi / 2;
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0007)
                            ..rotateY(angle),
                          child: showFront
                              ? _buildFrontCard(display, isDark)
                              : Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()..rotateY(pi),
                                  child: _buildBackCard(display, isDark),
                                ),
                        );
                      },
                    ),
                    // Swipe overlay
                    if (_swipeHint != null && _isFlipped)
                      Positioned.fill(
                        child: AnimatedOpacity(
                          opacity: (_dragX.abs() / 120).clamp(0, 0.85),
                          duration: Duration.zero,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              color: _swipeHint == 'known'
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : Colors.red.withValues(alpha: 0.3),
                            ),
                            child: Center(
                              child: Text(
                                _swipeHint == 'known' ? '✓ Known' : '✗ Unknown',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: _swipeHint == 'known'
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Card decoration (same for front and back) ──────────────────────────

  BoxDecoration _cardDecoration(bool isDark) => BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A2E1F), const Color(0xFF0D1B12)]
              : [Colors.white, const Color(0xFFFDF9F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _gold.withValues(alpha: 0.45), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      );

  // ── Front card ──────────────────────────────────────────────────────────

  Widget _buildFrontCard(DisplayProvider display, bool isDark) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 460),
      decoration: _cardDecoration(isDark),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: frequency + delete
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _gold.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.repeat, size: 12, color: _gold),
                    const SizedBox(width: 4),
                    Text('${_current.frequency}× in Quran',
                        style: const TextStyle(
                            fontSize: 11,
                            color: _gold,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
                GestureDetector(
                  onTap: _deleteCard,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withValues(alpha: 0.1),
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Arabic word + audio button
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _current.arabic,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style: _arabicStyle(display, isDark, 52),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _playAudio,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue.withValues(alpha: 0.1),
                      border:
                          Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.volume_up_rounded,
                        color: Colors.blue, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Transliteration
            Text(
              _current.transliteration,
              style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.white54 : Colors.grey.shade500),
            ),
            const SizedBox(height: 14),

            // Divider
            Row(children: [
              Expanded(child: Divider(color: _gold.withValues(alpha: 0.3))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('✦',
                    style: TextStyle(color: _gold.withValues(alpha: 0.5))),
              ),
              Expanded(child: Divider(color: _gold.withValues(alpha: 0.3))),
            ]),
            const SizedBox(height: 12),

            // Sample ayah (Arabic only — no translation on front)
            if (_current.sampleAyahArabic.isNotEmpty)
              Flexible(
                child: Text(
                  _current.sampleAyahArabic,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style:
                      _arabicStyle(display, isDark, 17).copyWith(height: 1.9),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              Text('Loading ayah...',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),

            const SizedBox(height: 14),

            // Tap to flip hint
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _gold.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.touch_app, size: 14, color: _gold),
                  const SizedBox(width: 6),
                  Text('Tap to Reveal Meaning',
                      style: TextStyle(
                          fontSize: 12,
                          color: _gold.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Back card ──────────────────────────────────────────────────────────

  Widget _buildBackCard(DisplayProvider display, bool isDark) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 460),
      decoration: _cardDecoration(isDark),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Arabic + root + audio
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Root box
                if (_current.root.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _gold.withValues(alpha: 0.35)),
                    ),
                    child: Column(children: [
                      Text('Root',
                          style: TextStyle(
                              fontSize: 9, color: Colors.grey.shade400)),
                      const SizedBox(height: 2),
                      Text(
                        // Space between each root letter
                        _current.root.characters.join('  '),
                        textDirection: TextDirection.rtl,
                        style: _arabicStyle(display, isDark, 16)
                            .copyWith(color: _gold),
                      ),
                    ]),
                  ),
                const SizedBox(width: 10),
                Text(
                  _current.arabic,
                  textDirection: TextDirection.rtl,
                  style: _arabicStyle(display, isDark, 36),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _playAudio,
                  child:
                      const Icon(Icons.volume_up, color: Colors.blue, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Frequency
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.repeat, size: 12, color: _gold),
                const SizedBox(width: 4),
                Text('${_current.frequency}× in Quran',
                    style: const TextStyle(fontSize: 11, color: _gold)),
              ],
            ),
            const SizedBox(height: 4),

            // Transliteration
            Text(_current.transliteration,
                style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white54 : Colors.grey.shade500)),

            const Divider(height: 20),

            // Urdu meaning — JameelNoori font
            Text(
              _current.urdu,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'JameelNoori',
                fontSize: display.urduFontSize + 6,
                color: isDark ? const Color(0xFF7EC8A0) : _teal,
                fontWeight: FontWeight.w700,
                height: 1.8,
              ),
            ),
            const SizedBox(height: 14),

            // Sample ayah with translation
            if (_current.sampleAyahArabic.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _green.withValues(alpha: 0.2)),
                ),
                child: Column(children: [
                  Text(
                    _current.sampleAyahArabic,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                    style:
                        _arabicStyle(display, isDark, 17).copyWith(height: 1.9),
                  ),
                  if (_current.sampleAyahTranslation.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _current.sampleAyahTranslation,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'JameelNoori',
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                        height: 1.5,
                      ),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
            ],

            // Learn More button
            GestureDetector(
              onTap: _openMorphology,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_green, _teal],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _gold.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.school_outlined, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text('Learn More About This Word',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlipHint(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      child: Text(
        'Tap card to reveal meaning',
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white38 : Colors.grey.shade400),
      ),
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: _swipeUnknown,
            child: Container(
              width: 110,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.red.withValues(alpha: 0.1),
                border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_back, color: Colors.red, size: 18),
                  const SizedBox(width: 4),
                  Text('Unknown',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.red.shade400,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: _flip,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold.withValues(alpha: 0.1),
                border: Border.all(color: _gold.withValues(alpha: 0.5)),
              ),
              child: const Icon(Icons.flip, color: _gold, size: 22),
            ),
          ),
          GestureDetector(
            onTap: _swipeKnown,
            child: Container(
              width: 110,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.green.withValues(alpha: 0.1),
                border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Known',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.green.shade400,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward,
                      color: Colors.green, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary screen ──────────────────────────────────────────────────────

  Widget _buildSummaryScreen(bool isDark) {
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF0EBE0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🌟', style: TextStyle(fontSize: 72)),
              const SizedBox(height: 16),
              Text('Session Complete!',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : _green)),
              const SizedBox(height: 8),
              Text('بارک اللہ فیک',
                  style: GoogleFonts.amiriQuran(fontSize: 28, color: _gold)),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
                  border: Border.all(color: _gold.withValues(alpha: 0.3)),
                ),
                child: Column(children: [
                  _summaryRow('Cards reviewed', '${_cards.length}', Icons.style,
                      isDark),
                  const Divider(height: 16),
                  _summaryRow(
                      'Points earned', '+$_sessionPoints', Icons.stars, isDark),
                  const Divider(height: 16),
                  _summaryRow('Total points', '$_totalPoints',
                      Icons.emoji_events, isDark),
                ]),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _gold.withValues(alpha: 0.2)),
                ),
                child: Text(
                  'Consistency is better than speed.\n'
                  'قليل دائم خير من كثير منقطع',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                      height: 1.5),
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Back to Quran',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllDoneScreen(bool isDark) {
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF0EBE0),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: const Text('Flash Cards'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('✅', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text('All Caught Up!',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : _green)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _gold.withValues(alpha: 0.25)),
                ),
                child: Text(
                  '⚠️ Learning too many words at once can cause forgetting.\n\n'
                  'Go slow and consistent — 5 words a day = 1,825 words a year!\n\n'
                  'Come back tomorrow for your next session. 🌙',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                      height: 1.6),
                ),
              ),
              const SizedBox(height: 16),
              // Option to load more anyway
              OutlinedButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('⚠️ Warning'),
                      content: const Text(
                          'Learning too many words at once may cause you to forget them faster.\n\n'
                          'We recommend consistent daily practice.\n\n'
                          'Do you still want to load more cards?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('No, I\'ll wait')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Yes, continue',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    _loadSession(forceNew: true);
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _gold,
                  side: BorderSide(color: _gold.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Load More Cards'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14)),
                child: const Text('Back to Quran'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, IconData icon, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Icon(icon, size: 18, color: _gold),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black87)),
        ]),
        Text(value,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: _gold)),
      ],
    );
  }

  TextStyle _arabicStyle(DisplayProvider d, bool isDark, double size) {
    final color = isDark ? Colors.white : const Color(0xFF1A1A1A);
    switch (d.arabicFont) {
      case 'indopak':
        return TextStyle(
            fontFamily: 'IndoPak', fontSize: size, color: color, height: 1.4);
      case 'noorehuda':
        return TextStyle(
            fontFamily: 'NoorehudaFont',
            fontSize: size,
            color: color,
            height: 1.4);
      default:
        return GoogleFonts.amiriQuran(
            fontSize: size, color: color, height: 1.4);
    }
  }
}
