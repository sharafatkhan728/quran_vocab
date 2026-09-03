// ignore_for_file: use_build_context_synchronously

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../providers/display_provider.dart';
import '../providers/user_provider.dart';
import '../services/srs_service.dart';
import '../services/word_progress_service.dart';
import '../services/translation_service.dart';
import 'morphology_sheet.dart';
import '../repositories/vocabulary_repository.dart';
import '../models/word.dart';
import '../providers/learning_state_provider.dart';
import '../widgets/progress_graph.dart';

// ── FlashWord model ─────────────────────────────────────────────────────────
class FlashWord {
  final String arabic;
  final String normalizedForLookup;
  final String urdu;
  final int frequency;
  late final String normalizedArabic;
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
    required this.normalizedForLookup,
    required this.urdu,
    required this.frequency,
  }) : normalizedArabic = arabic
            .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
            .trim() {
    transliteration = normalizedArabic;
  }

  Future<void> loadAyah() async {
    if (ayahLoaded) return;
    try {
      final vocab =
          await VocabularyRepository.getByArabicClean(normalizedArabic);
      if (vocab == null) return;
      if (vocab.firstSurahId == 0) return;
      sampleSurah = vocab.firstSurahId;
      sampleAyahNum = vocab.firstAyahNumber;
      wordPositionInAyah = vocab.firstWordPosition;
      sampleAyahArabic =
          await VocabularyRepository.getAyahArabic(sampleSurah, sampleAyahNum);
      final scholarKey = TranslationLangService.selectedScholar;
      final source = TranslationService.scholars[scholarKey];
      if (source != null) {
        sampleAyahTranslation = await TranslationService.getAyahTranslation(
                sampleSurah, sampleAyahNum,
                scholar: scholarKey) ?? '';
      }
      // Reset so it reloads if language changes
      if (sampleAyahTranslation.isNotEmpty) ayahLoaded = true;
      ayahLoaded = true;
    } catch (_) {}
  }

  Future<void> loadRoot() async {
    if (rootLoaded || root.isNotEmpty) return;
    rootLoaded = true;
    try {
      // Root is already stored in vocab_words JOIN roots — no in-memory
      // corpus needed. VocabularyRepository.getByArabicClean() returns it
      // directly from the SQLite query.
      final vocab =
          await VocabularyRepository.getByArabicClean(normalizedArabic);
      if (vocab != null && vocab.root.isNotEmpty) {
        root = vocab.root;
      }
    } catch (_) {}
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
  SessionBuildResult? _sessionResult;
  bool _sessionDone = false;
  bool _isFlipped = false;
  bool _hasBeenFlipped = false;
  FlashWord? _lastCard;
  int _lastIndex = 0;
  bool _canUndo = false;
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
        vsync: this, duration: const Duration(milliseconds: 350));
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _dismissCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _flipAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOut));
    _entryScale = Tween<double>(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _entryFade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _dismissOffset = Tween<Offset>(begin: Offset.zero, end: const Offset(2, 0))
        .animate(
            CurvedAnimation(parent: _dismissCtrl, curve: Curves.easeInCubic));
    _dismissFade = Tween<double>(begin: 1, end: 0)
        .animate(CurvedAnimation(parent: _dismissCtrl, curve: Curves.easeIn));
    _loadSession();
    TranslationLangService.langNotifier
        .addListener(_onTranslationLangChanged);
  }

  void _onTranslationLangChanged() {
    // Reset ayah loaded flag so new language translation is fetched
    for (final card in _cards) {
      card.ayahLoaded = false;
      card.sampleAyahTranslation = '';
    }
    if (mounted) setState(() {});
    // Reload current card's translation immediately
    if (_cards.isNotEmpty && _currentIndex < _cards.length) {
      _cards[_currentIndex].loadAyah().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    _entryCtrl.dispose();
    _dismissCtrl.dispose();
    _audio.dispose();
    super.dispose();
        TranslationLangService.langNotifier
        .removeListener(_onTranslationLangChanged);
  }

  // ── Session loading ─────────────────────────────────────────────────────

  Future<void> _showLoadMoreWarning() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('⚠️ Today\'s Session Complete'),
        content: const Text(
          'You have completed today\'s learning session.\n\n'
          'Learning too many new words at once reduces retention.\n\n'
          'Consistent daily practice is far more effective.\n\n'
          'Do you still want to continue with new words today?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, I\'ll wait'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, continue',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      setState(() => _loading = true);
      final freq = await WordProgressService.getWordFrequencies();
      final knownCleans =
          context.read<LearningStateProvider>().allKnownCleans;
      final extra = await SrsService.buildExtraSession(
          freq.keys.toList(), 10, knownCleans: knownCleans);
      if (extra.isEmpty) {
        setState(() => _loading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No more new words available')));
        }
        return;
      }
      final cards = _buildCards(extra.words, freq);
      if (mounted) {
        setState(() {
          _cards = cards;
          _currentIndex = 0;
          _loading = false;
          _sessionDone = false;
          _isFlipped = false;
          _hasBeenFlipped = false;
        });
        _entryCtrl.reset();
        _entryCtrl.forward();
        _preloadCards(0);
      }
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadSession({bool forceNew = false}) async {
    setState(() {
      _loading = true;
      _sessionDone = false;
    });
    if (forceNew) {
      await SrsService.clearSession();
      _sessionPoints = 0;
      _sessionResult = null;
    }
    _totalPoints = await SrsService.getTotalPoints();

    await TranslationService.init();
    final freq = await WordProgressService.getWordFrequencies();

    if (!forceNew) {
      final saved = await SrsService.loadSession();
      if (saved != null &&
          saved.words.isNotEmpty &&
          saved.index < saved.words.length - 1) {
        final cards = _buildCards(saved.words, freq);
        if (mounted) {
          setState(() {
            _cards = cards;
            _currentIndex = saved.index;
            _loading = false;
            _isFlipped = false;
            _hasBeenFlipped = false;
          });
          _entryCtrl.forward();
          _preloadCards(_currentIndex);
        }
        return;
      }
    }

    await SrsService.startNewSession();
    // Read dailyGoal here — after providers have fully loaded
    final dailyGoal = context.read<UserProvider>().dailyGoal;
    final allWords = freq.keys.toList();
    final knownCleans =
        context.read<LearningStateProvider>().allKnownCleans;
    final result =
        await SrsService.buildSession(allWords, dailyGoal, knownCleans: knownCleans);

    if (result.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _sessionDone = false;
          _cards = [];
        });
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _showLoadMoreWarning());
      }
      return;
    }

    _sessionResult = result;
    final cards = _buildCards(result.words, freq);
    if (mounted) {
      setState(() {
        _cards = cards;
        _currentIndex = 0;
        _loading = false;
        _isFlipped = false;
        _hasBeenFlipped = false;
      });
      _entryCtrl.forward();
      _preloadCards(0);
    }
  }

  List<FlashWord> _buildCards(List<String> words, Map<String, WordData> freq) {
    return words.map((word) {
      final entry = freq[word];
      return FlashWord(
        arabic: entry?.originalArabic.isNotEmpty == true
            ? entry!.originalArabic
            : word,
        normalizedForLookup: word,
        urdu: entry?.urdu ?? '',
        frequency: entry?.frequency ?? 0,
      );
    }).toList();
  }

  Future<void> _preloadCards(int from) async {
    final end = (from + 5).clamp(0, _cards.length);
    await Future.wait([
      for (int i = from; i < end; i++)
        _cards[i].loadAyah().then((_) => _cards[i].loadRoot()).then((_) {
          if (mounted) setState(() {});
        }),
    ]);
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
    // Ensure ayah translation loads when card flips
    _current.loadAyah().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _swipeKnown() async {
    if (!_isFlipped) {
      _flip();
      return;
    }
    HapticFeedback.mediumImpact();
    final existingCard = await SrsService.getCard(_current.normalizedForLookup);
    final wasNew = existingCard?.totalReviews == 0;
    final pts = await SrsService.markKnown(_current.normalizedForLookup);
    // Single source of truth — LearningStateProvider handles known_words
    if (mounted) {
      await context
          .read<LearningStateProvider>()
          .setKnownByClean(_current.normalizedForLookup);
    }
    if (wasNew) await SrsService.recordNewCardReviewed();
    if (!mounted) return;
    setState(() {
      _sessionPoints += pts;
      _totalPoints += pts;
    });
    await _animateDismiss(toRight: true);
    if (!mounted) return;
    _nextCard();
  }

  Future<void> _swipeUnknown() async {
    if (!_isFlipped) {
      _flip();
      return;
    }
    HapticFeedback.mediumImpact();
    await SrsService.markUnknown(_current.normalizedForLookup);
    if (!mounted) return;
    // Mark as unknown in global learning state
    await context
        .read<LearningStateProvider>()
        .setUnknownByClean(_current.normalizedForLookup);
    if (!mounted) return;
    final remaining = _cards.length - _currentIndex - 1;
    if (remaining > 2) {
      final insertAt =
          _currentIndex + 1 + Random().nextInt(remaining.clamp(1, 5));
      final card = _cards[_currentIndex];
      _cards.insert(insertAt.clamp(0, _cards.length), card);
    }
    await _animateDismiss(toRight: false);
    if (!mounted) return;
    _nextCard();
  }

  Future<void> _deleteCard() async {
    // Delete = remove from SRS only. Word stays Known in Quran/Vocabulary.
    // Mark as known in global state so it's hidden from Quran reader.
    final word = _current.normalizedForLookup;
    final wasLastCard = _currentIndex == _cards.length - 1;

    await SrsService.deleteCard(word);
    if (mounted) {
      await context.read<LearningStateProvider>().setKnownByClean(word);
    }
    // Clear saved session so the deleted card is not restored on reopen.
    // A fresh session will be built next time, which will skip the deleted card.
    if (mounted) {
      await SrsService.clearSession();
    }
    if (!mounted) return;
    await _animateDismiss(toRight: true);
    if (!mounted) return;

    // Remove from in-memory list so the deleted card is never saved/restored.
    setState(() {
      _cards.removeAt(_currentIndex);
      _lastCard = null;
      _lastIndex = 0;
      _canUndo = false;
      _isFlipped = false;
      _hasBeenFlipped = false;
      _swipeHint = null;
    });

    if (wasLastCard || _cards.isEmpty) {
      SrsService.clearSession();
      setState(() => _sessionDone = true);
    } else if (_currentIndex < _cards.length) {
      _entryCtrl.reset();
      _entryCtrl.forward();
      _preloadCards(_currentIndex);
    }
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
        _canUndo = false;
      });
    } else {
      // Save current card so user can undo
      _lastCard = _current;
      _lastIndex = _currentIndex;
      setState(() {
        _currentIndex++;
        _isFlipped = false;
        _hasBeenFlipped = false;
        _swipeHint = null;
        _canUndo = true;
      });
      _entryCtrl.reset();
      _entryCtrl.forward();
      if (_currentIndex < _cards.length - 1) {
        SrsService.saveSession(
            _cards.map((c) => c.normalizedForLookup).toList(), _currentIndex);
      }
      _preloadCards(_currentIndex);
    }
  }

  Future<void> _undoLastSwipe() async {
    if (!_canUndo || _lastCard == null) return;
    HapticFeedback.lightImpact();
    // Go back to previous card
    setState(() {
      _currentIndex = _lastIndex;
      _isFlipped = false;
      _hasBeenFlipped = false;
      _swipeHint = null;
      _canUndo = false;
      _lastCard = null;
    });
    _flipCtrl.reset();
    _entryCtrl.reset();
    _entryCtrl.forward();
  }

  Future<void> _playAudio() async {
    final card = _current;
    if (card.sampleSurah == 0) return;
    HapticFeedback.lightImpact();
    try {
      final s = card.sampleSurah.toString().padLeft(3, '0');
      final a = card.sampleAyahNum.toString().padLeft(3, '0');
      final w = card.wordPositionInAyah.toString().padLeft(3, '0');
      final url = 'https://audio.qurancdn.com/wbw/${s}_${a}_$w.mp3';
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
        wordPos:
            _current.wordPositionInAyah > 0 ? _current.wordPositionInAyah : 1,
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
          if (_currentIndex == 0 && _sessionResult != null)
            _buildSessionBanner(isDark),
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
          if (!_isFlipped) return;
          setState(() {
            _dragX += d.delta.dx;
            if (_dragX > 50) {
              _swipeHint = 'known';
            } else if (_dragX < -50) {
              _swipeHint = 'unknown';
            } else {
              _swipeHint = null;
            }
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
            // Behind card 3
            Positioned(
              top: 0,
              left: 8,
              right: 8,
              child: Container(
                height: 170,
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
            // Behind card 2
            Positioned(
              top: 8,
              left: 4,
              right: 4,
              child: Container(
                height: 500,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F2518)
                      : const Color(0xFFF0EAD8),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(25)),
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
            // Main card
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

  Widget _buildFrontCard(DisplayProvider display, bool isDark) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.70,
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: _cardDecoration(isDark),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
            const SizedBox(height: 55),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _current.arabic,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style: _arabicStyle(display, isDark, 60),
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
            const SizedBox(height: 12),
            Text(
              _current.transliteration,
              style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.white54 : Colors.grey.shade500),
            ),
            const SizedBox(height: 14),
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
            if (_current.sampleAyahArabic.isNotEmpty)
              Flexible(
                child: Text(
                  _current.sampleAyahArabic,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style:
                      _arabicStyle(display, isDark, 25).copyWith(height: 1.9),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              Text('Loading ayah...',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
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

  Widget _buildBackCard(DisplayProvider display, bool isDark) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.70,
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: _cardDecoration(isDark),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                        _current.root.characters.join('  '),
                        textDirection: TextDirection.rtl,
                        style: _arabicStyle(display, isDark, 25)
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
            Text(_current.transliteration,
                style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white54 : Colors.grey.shade500)),
            const Divider(height: 20),
            Text(
              _current.urdu,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'JameelNoori',
                fontSize: display.urduFontSize + 20,
                color: isDark ? const Color(0xFF7EC8A0) : _teal,
                fontWeight: FontWeight.w700,
                height: 1.8,
              ),
            ),
            const SizedBox(height: 14),
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
                        _arabicStyle(display, isDark, 23).copyWith(height: 1.9),
                  ),
                  const SizedBox(height: 8),
                  if (_current.sampleAyahTranslation.isEmpty)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFD4AF37),
                      ),
                    )
                  else
                    Text(
                      _current.sampleAyahTranslation,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'JameelNoori',
                        fontSize: 16,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                        height: 1.5,
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_canUndo)
            GestureDetector(
              onTap: _undoLastSwipe,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.orange.withValues(alpha: 0.1),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.undo, color: Colors.orange, size: 16),
                    SizedBox(width: 6),
                    Text('Undo last swipe',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          Text(
            'Tap card to reveal meaning',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Undo button — only visible after a swipe
          if (_canUndo)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: _undoLastSwipe,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.orange.withValues(alpha: 0.1),
                    border:
                        Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.undo, color: Colors.orange, size: 16),
                      SizedBox(width: 6),
                      Text('Undo last swipe',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          Row(
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
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.5)),
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
                    border:
                        Border.all(color: Colors.green.withValues(alpha: 0.5)),
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
        ],
      ),
    );
  }

  // ── Summary screen ──────────────────────────────────────────────────────

  Widget _buildSummaryScreen(bool isDark) {
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF0EBE0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
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
                _summaryRow(
                    'Cards reviewed', '${_cards.length}', Icons.style, isDark),
                const Divider(height: 16),
                _summaryRow(
                    'Points earned', '+$_sessionPoints', Icons.stars, isDark),
                const Divider(height: 16),
                _summaryRow('Total points', '$_totalPoints', Icons.emoji_events,
                    isDark),
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
            // ── Progress graph ────────────────────────────────────────
            _ProgressGraphSection(isDark: isDark),
            const SizedBox(height: 24),
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => _loadSession(forceNew: true),
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: BorderSide(color: _green.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Review More Cards',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  } //

  Widget _statsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD4AF37))),
        ],
      ),
    );
  }

  Widget _buildSessionBanner(bool isDark) {
    final r = _sessionResult!;
    if (r.overdueCount == 0 && r.failedCount == 0) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1B4332).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFF1B4332).withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (r.overdueCount > 0)
            _bannerChip('📚 ${r.overdueCount} review', Colors.blue),
          if (r.failedCount > 0)
            _bannerChip('❌ ${r.failedCount} failed', Colors.red),
          if (r.newCount > 0) _bannerChip('🆕 ${r.newCount} new', Colors.green),
        ],
      ),
    );
  }

  Widget _bannerChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
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
              Text(
                _sessionResult == null ? '📖' : '✅',
                style: const TextStyle(fontSize: 64),
              ),
              const SizedBox(height: 16),
              Text(
                  _sessionResult == null
                      ? 'Open a Surah First!'
                      : 'All Caught Up!',
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
                  _sessionResult == null
                      ? '📖 Open any Surah from the Quran tab first.\n\n'
                          'Words you encounter will appear here for spaced repetition learning.\n\n'
                          'Start with Al-Fatiha or Al-Baqarah!'
                      : '⚠️ Learning too many words at once can cause forgetting.\n\n'
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
              if (_sessionResult != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B4332).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF1B4332).withValues(alpha: 0.2)),
                  ),
                  child: Column(children: [
                    _statsRow('📚 Overdue reviews',
                        '${_sessionResult!.overdueCount}'),
                    _statsRow(
                        '❌ Failed cards', '${_sessionResult!.failedCount}'),
                    _statsRow(
                        '🆕 New cards today', '${_sessionResult!.newCount}'),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              if (_sessionResult != null)
                OutlinedButton.icon(
                  onPressed: () => _showLoadMoreWarning(),
                  icon: const Icon(Icons.add_card),
                  label: const Text('Load More Cards (Not Recommended)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
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

/// Loads graph data and shows animated progress graph
class _ProgressGraphSection extends StatefulWidget {
  final bool isDark;
  const _ProgressGraphSection({required this.isDark});
  @override
  State<_ProgressGraphSection> createState() => _ProgressGraphSectionState();
}

class _ProgressGraphSectionState extends State<_ProgressGraphSection> {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);
  List<ProgressPoint>? _points;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pts = await ProgressGraphData.load();
    if (mounted) setState(() => _points = pts);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    if (_points == null) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: CircularProgressIndicator(
              color: Color(0xFFD4AF37), strokeWidth: 2),
        ),
      );
    }

    if (_points!.length < 2) {
      return const SizedBox.shrink();
    }

    final latest = _points!.last.percent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _gold.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: _green.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Quran Vocabulary Progress',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white : _green),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _gold.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${latest.toStringAsFixed(1)}% covered',
                  style: const TextStyle(
                      fontSize: 11, color: _gold, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'You know ${latest.toStringAsFixed(1)}% of all Quran word occurrences',
            style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          ProgressGraph(points: _points!, isDark: isDark),
        ],
      ),
    );
  }
}
