// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kGreen  = Color(0xFF1B4332);
const kTeal   = Color(0xFF2D6A4F);
const kGold   = Color(0xFFD4AF37);
const kDarkBg = Color(0xFF0A1628);
const kLightBg= Color(0xFFFDF8F0);

class _TourStep {
  final String title;
  final String body;
  final Widget demo;
  _TourStep({required this.title, required this.body, required this.demo});
}
class _TourChapter {
  final String chapterTitle;
  final List<_TourStep> steps;
  const _TourChapter({required this.chapterTitle, required this.steps});
}
class AppTourScreen extends StatefulWidget {
  const AppTourScreen({super.key});
  @override
  State<AppTourScreen> createState() => _AppTourScreenState();
}
class _AppTourScreenState extends State<AppTourScreen> with TickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;
  bool _isAnimating = false;
  late List<_TourChapter> _chapters;
  late List<_TourStep> _allSteps;
  @override
  void initState() {
    super.initState();
    _chapters = _buildChapters();
    _allSteps = _chapters.expand((c) => c.steps).toList();
  }
  @override
  void dispose() { _pageCtrl.dispose(); super.dispose(); }
  void _next() {
    if (_isAnimating) return;
    HapticFeedback.lightImpact();
    if (_currentPage < _allSteps.length - 1) {
      setState(() => _isAnimating = true);
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut).then((_) {
        if (mounted) {
          setState(() {
            _currentPage++;
            _isAnimating = false;
          });
        }
      });
    } else { _finish(); }
  }
  void _back() {
    if (_isAnimating || _currentPage == 0) return;
    HapticFeedback.lightImpact();
    setState(() => _isAnimating = true);
    _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut).then((_) {
      if (mounted) {
        setState(() {
          _currentPage--;
          _isAnimating = false;
        });
      }
    });
  }
  void _skip() {
    if (_isAnimating) return;
    HapticFeedback.lightImpact();
    setState(() => _isAnimating = true);
    _pageCtrl.animateToPage(
        _allSteps.length - 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut).then((_) {
      if (mounted) {
        setState(() {
          _currentPage = _allSteps.length - 1;
          _isAnimating = false;
        });
      }
    });
  }
  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_tour_seen', true);
    if (mounted) Navigator.pop(context);
  }
  String _chapterOfStep(int step) {
    int count = 0;
    for (final ch in _chapters) {
      for (final _ in ch.steps) {
        if (count == step) return ch.chapterTitle;
        count++;
      }
    }
    return '';
  }
  List<_TourChapter> _buildChapters() => [
    _TourChapter(chapterTitle: 'CHAPTER 1 - WELCOME', steps: [
      _TourStep(
        title: 'Quran Kalima',
        body: 'Read the Quran with understanding.\nLearn Arabic vocabulary through word-by-word meanings, explore word roots and grammar, and build lasting knowledge with smart flashcard review.\n\nYour journey: Read -> Understand -> Explore -> Learn -> Review',
        demo: _buildWelcomeDemo(),
      ),
    ]),
    _TourChapter(chapterTitle: 'CHAPTER 2 - READ & UNDERSTAND', steps: [
      _TourStep(
        title: 'Open a Surah',
        body: 'Tap any Surah from the list to open the reader. The app remembers your last position in each Surah.',
        demo: _buildSurahListDemo(),
      ),
      _TourStep(
        title: 'Word-by-Word Meanings',
        body: 'Every Arabic word displays its meaning below it. Choose Urdu, English, or Hindi from Settings. Tap a word to see its grammar type shown in colour - verbs, nouns, prepositions and more.',
        demo: _buildWordByWordDemo(),
      ),
      _TourStep(
        title: 'Hide & Unhide Words',
        body: 'Long-press any word to mark it as Known or Unknown. Known words fade to 35% opacity so your attention stays on words you still need to learn.',
        demo: _buildHideDemo(),
      ),
      _TourStep(
        title: 'Explore a Word',
        body: 'Tap any word to open its detail panel. See the full meaning, root letters, grammar segments, and a Learn More button that opens the full morphology breakdown.',
        demo: _buildWordDetailDemo(),
      ),
    ]),
    _TourChapter(chapterTitle: 'CHAPTER 3 - BUILD VOCABULARY', steps: [
      _TourStep(
        title: 'Vocabulary Screen',
        body: 'The Vocabulary screen lists every Quranic word you have discovered, sorted by frequency or alphabetically. Each entry shows the word, its meaning, and how often it appears in the Quran. Known and Unknown tabs help you focus on what matters most.',
        demo: _buildVocabListDemo(),
      ),
      _TourStep(
        title: 'Swipe to Practice',
        body: 'On the Known and Unknown tabs, swipe to quickly mark words. Swipe right on a known word to mark it Forgotten. Swipe left on an unknown word to mark it Remembered.',
        demo: _buildSwipeDemo(),
      ),
    ]),
    _TourChapter(chapterTitle: 'CHAPTER 4 - FLASHCARDS', steps: [
      _TourStep(
        title: 'Start a Session',
        body: 'Flashcard sessions prioritize overdue review cards first, then difficult words, and finally new vocabulary up to your Daily Goal.',
        demo: _buildSessionStartDemo(),
      ),
      _TourStep(
        title: 'Flip the Card',
        body: 'Look at the Arabic word and try to remember its meaning BEFORE tapping to flip. The card shows the full meaning, root, transliteration, and a sample Ayah.',
        demo: _buildFlipDemo(),
      ),
      _TourStep(
        title: 'Known vs Unknown',
        body: 'After flipping, swipe the card left or right, or use the buttons below it. Mark Known only when you genuinely remembered the word without looking. Mark Unknown when you did not - honest self-assessment lets the spaced repetition system work correctly.',
        demo: _buildKnownUnknownDemo(),
      ),
    ]),
    _TourChapter(chapterTitle: 'CHAPTER 5 - KEEP IMPROVING', steps: [
      _TourStep(
        title: 'Daily Goal',
        body: 'Set your Daily Goal in Settings. It controls how many new vocabulary words you introduce each session. Even 5 words a day equals over 1,800 words per year.',
        demo: _buildDailyGoalDemo(),
      ),
      _TourStep(
        title: 'Review More Cards',
        body: 'After completing a session, tap Review More Cards to start another session immediately - without leaving the Flash Cards screen.',
        demo: _buildReviewMoreDemo(),
      ),
      _TourStep(
        title: 'Your Progress',
        body: 'The Progress screen shows your learning journey: how many words you know, your current streak, how many words you reviewed today and this week, and a heatmap of your activity over the past 12 weeks.',
        demo: _buildProgressDemo(),
      ),
      _TourStep(
        title: 'Progress Ring',
        body: 'The ring at the top of the Progress screen shows how much of the Quran\'s vocabulary you have covered so far. Every word you learn moves it closer to full.',
        demo: _buildProgressRingDemo(),
      ),
      _TourStep(
        title: 'Progress Breakdown & Milestones',
        body: 'Below the ring, progress bars break down your Known words, Discovered words, the 300 Core Words that make up most of the Quran, and Surahs you have fully completed. A milestone path and achievement badges mark your journey along the way.',
        demo: _buildCoverageChartDemo(),
      ),
    ]),
    _TourChapter(chapterTitle: 'CHAPTER 6 - YOUR JOURNEY', steps: [
      _TourStep(
        title: 'Your Learning Loop',
        body: 'Read the Quran -> notice unfamiliar words -> tap to study their meaning and root -> practice with flashcards -> review regularly. Over time, more words become familiar.',
        demo: _buildLoopDemo(),
      ),
      _TourStep(
        title: 'Consistency Is Key',
        body: 'Learning 5 words a day with honest review is far more powerful than rushing through 50 words and forgetting them all. Trust the spaced repetition system.\n\nBaraka Allahu Feek\nMay Allah bless your efforts.',
        demo: _buildFinalDemo(),
      ),
    ]),
  ];
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLast = _currentPage == _allSteps.length - 1;
    final isFirst = _currentPage == 0;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark ? kDarkBg : kLightBg,
        body: SafeArea(
          child: Column(
            children: [
              _buildProgressBar(isDark),
              const SizedBox(height: 6),
              Text(
                _chapterOfStep(_currentPage),
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                  color: kGold,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: PageView.builder(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _allSteps.length,
                  onPageChanged: (i) {
                    if (i != _currentPage)
                      setState(() => _currentPage = i);
                  },
                  itemBuilder: (_, i) => _buildStepPage(_allSteps[i], isDark),
                ),
              ),
              const SizedBox(height: 4),
              _buildNavButtons(isFirst, isLast, isDark),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildStepPage(_TourStep step, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    step.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : kGreen,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    step.body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.55,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 30),
                  step.demo,
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  Widget _buildProgressBar(bool isDark) {
    final progress = (_currentPage + 1) / _allSteps.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            '${_currentPage + 1} / ${_allSteps.length}',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.grey.shade400,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor:
                  isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(kGold),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildNavButtons(bool isFirst, bool isLast, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          if (!isFirst)
            Expanded(
              child: TextButton(
                onPressed: _back,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                    side: BorderSide(
                        color:
                            isDark ? Colors.white24 : Colors.grey.shade300),
                  ),
                ),
                child: Text(
                  'Back',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey.shade600),
                ),
              ),
            ),
          if (isFirst) const Spacer(),
          if (!isLast)
            TextButton(
              onPressed: _skip,
              child: Text(
                'Skip',
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.grey.shade500),
              ),
            ),
          if (!isLast) const SizedBox(width: 6),
          Expanded(
            child: ElevatedButton(
              onPressed: _next,
              style: ElevatedButton.styleFrom(
                backgroundColor: kGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
              ),
              child: Text(
                isLast ? 'Get Started' : 'Next',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
  // ═══ DEMO WIDGETS ═══
  Widget _buildWelcomeDemo() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (_, v, __) {
        return Transform.scale(
          scale: v,
          child: Container(
            width: 115,
            height: 115,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                  colors: [kGreen, kTeal],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              border: Border.all(
                  color: kGold.withValues(alpha: 0.5), width: 2),
              boxShadow: [
                BoxShadow(
                    color: kGreen.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 7))
              ],
            ),
            child: const Center(
                child: Text('\u{1F54C}', style: TextStyle(fontSize: 56))),
          ),
        );
      },
    );
  }
  Widget _buildSurahListDemo() {
    final items = const [
      {'num': '1', 'ar': 'الفاتحة', 'en': 'Al-Fatiha', 'verses': '7'},
      {'num': '2', 'ar': 'البقرة', 'en': 'Al-Baqarah', 'verses': '286'},
      {'num': '3', 'ar': 'ال عمران', 'en': 'Aal-Imran', 'verses': '200'},
      {'num': '4', 'ar': 'النساء', 'en': "An-Nisa'", 'verses': '176'},
      {'num': '5', 'ar': 'المائدة', 'en': 'Al-Ma-idah', 'verses': '120'},
    ];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (_, v, __) {
        return Opacity(
          opacity: v,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 270,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kGreen.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 14),
                      decoration: const BoxDecoration(
                          color: kGreen,
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(14))),
                      child: const Text(
                        'Surahs',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                    ),
                    ...items.map((e) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: Colors.grey, width: 0.5))),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                  color:
                                      kGold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Center(
                                  child: Text(e['num']!,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight.bold,
                                          color: kGreen))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e['ar']!,
                                    textDirection:
                                        TextDirection.rtl,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight:
                                            FontWeight.w600,
                                        color: kGreen),
                                  ),
                                  Text(
                                    '${e['en']}  \u{00B7}  ${e['verses']} Ayahs',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey
                                            .shade500),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                size: 16, color: Colors.grey),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const _PointerDemo(label: 'TAP TO OPEN'),
            ],
          ),
        );
      },
    );
  }
  Widget _buildWordByWordDemo() {
    final words = const [
      {'ar': 'بِا', 'mean': 'By', 'color': Colors.green},
      {'ar': 'اسْمِ', 'mean': 'Name', 'color': Colors.blue},
      {'ar': 'اللَّهِ', 'mean': 'Allah', 'color': Colors.blue},
    ];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (_, v, __) {
        return Opacity(
          opacity: v,
          child: Container(
            width: 275,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: kGreen.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Column(
              children: [
                const Text('بِسْمِ اللّٰه',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: kGreen)),
                const SizedBox(height: 10),
                ...words.map((w) {
                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                  color: w['color'] as Color,
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text(w['ar'] as String,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87)),
                          const SizedBox(width: 10),
                          Text(w['mean'] as String,
                              style:
                                  const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Container(
                          width: 30,
                          height: 2,
                          color: (w['color'] as Color)
                              .withValues(alpha: 0.4)),
                    ],
                  );
                }),
                const SizedBox(height: 6),
                const Text(
                    'Tap any word -> see root, meaning & more ->',
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        );
      },
    );
  }
  Widget _buildHideDemo() => const _HideDemoWidget();
  Widget _buildWordDetailDemo() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (_, v, __) {
        return Opacity(
          opacity: v,
          child: Container(
            width: 250,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: kGold.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('كِتٰب',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: kGreen)),
                  const SizedBox(height: 8),
                  _detailChip('Meaning', 'Book / Writing', Colors.teal),
                  const SizedBox(height: 5),
                  _detailChip('Root', 'ك-ت-ب', kGold),
                  const SizedBox(height: 5),
                  _detailChip('POS', 'Noun (N)', Colors.blue),
                  const SizedBox(height: 8),
                  const _WordDetailToggleDemo(),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [kGreen, kTeal]),
                        borderRadius: BorderRadius.circular(7)),
                    child: const Center(
                      child: Text('Learn More About This Word',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  Widget _detailChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style:
                  TextStyle(fontSize: 9, color: Colors.grey.shade600)),
          Text(value,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
  Widget _buildVocabListDemo() {
    final words = const [
      {'ar': 'اللّٰهُ', 'mean': 'Allah', 'freq': '980x', 'known': true},
      {'ar': 'رَبّ', 'mean': 'Lord', 'freq': '690x', 'known': true},
      {'ar': 'يَوْم', 'mean': 'Day', 'freq': '380x', 'known': false},
      {'ar': 'مَلِك', 'mean': 'King', 'freq': '170x', 'known': false},
    ];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (_, v, __) {
        return Opacity(
          opacity: v,
          child: Container(
            width: 255,
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: kGreen.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 7, horizontal: 12),
                    decoration: const BoxDecoration(
                        color: kGreen,
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(13))),
                    child: const Text('Vocabulary  (1,342 words)',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11))),
                ...words.map((w) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                                color: w['known'] == true
                                    ? Colors.green
                                    : Colors.orange,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Expanded(
                            child: Text(w['ar'] as String,
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600))),
                        const SizedBox(width: 5),
                        Text(w['mean'] as String,
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600)),
                        const SizedBox(width: 5),
                        Text(w['freq'] as String,
                            style: const TextStyle(
                                fontSize: 8, color: Colors.grey)),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Row(
                    children: [
                      Expanded(
                          child: _tabChip('All (1342)', true)),
                      const SizedBox(width: 3),
                      Expanded(
                          child: _tabChip('Known (541)', false)),
                      const SizedBox(width: 3),
                      Expanded(
                          child: _tabChip('Unknown (801)', false)),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
              ],
            ),
          ),
        );
      },
    );
  }
  Widget _tabChip(String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
          color: active ? kGreen.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 7.5,
            color: active ? kGreen : Colors.grey,
            fontWeight: active ? FontWeight.bold : FontWeight.normal),
      ),
    );
  }
  Widget _buildSwipeDemo() => const _SwipeDemo();
  Widget _buildSessionStartDemo() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (_, v, __) {
        return Opacity(
          opacity: v,
          child: Container(
            width: 255,
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: kGreen.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Session Ready',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: kGreen)),
                  const SizedBox(height: 6),
                  _sessionChip('\u{1F534}', 'Overdue Reviews', '12',
                      Colors.red),
                  const SizedBox(height: 4),
                  _sessionChip('\u{1F7E1}', 'Failed Cards', '5',
                      Colors.orange),
                  const SizedBox(height: 4),
                  _sessionChip(
                      '\u{1F7E2}', 'New Words (Daily Goal: 10)', '8',
                      Colors.green),
                  const SizedBox(height: 6),
                  const Text('Priority: Reviews -> Failed -> New',
                      style: TextStyle(fontSize: 8, color: Colors.grey)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  Widget _sessionChip(String emoji, String label, String count,
      Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 9))),
          Text(count,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(width: 3),
          const Icon(Icons.arrow_forward,
              size: 11, color: Colors.grey),
        ],
      ),
    );
  }
  Widget _buildFlipDemo() => const _FlipDemo();
  Widget _buildKnownUnknownDemo() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (_, v, __) {
        return Opacity(
          opacity: v,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 210,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 13),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    border:
                        Border.all(color: kGreen.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ]),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('رَبّ',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: kGreen)),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _kuButton(Icons.arrow_back, 'Unknown', Colors.red),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kGold.withValues(alpha: 0.1),
                              border: Border.all(color: kGold.withValues(alpha: 0.5))),
                          child: const Icon(Icons.flip, color: kGold, size: 17),
                        ),
                        _kuButton(Icons.arrow_forward, 'Known', Colors.green),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                  '<- Swipe or tap for Unknown  |  Known ->',
                  style: TextStyle(fontSize: 8, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }
  Widget _kuButton(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label == 'Unknown') Icon(icon, color: color, size: 14),
          if (label == 'Unknown') const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.bold, color: color)),
          if (label == 'Known') const SizedBox(width: 3),
          if (label == 'Known') Icon(icon, color: color, size: 14),
        ],
      ),
    );
  }
  Widget _buildDailyGoalDemo() => const _DailyGoalDemo();
  Widget _buildReviewMoreDemo() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (_, v, __) {
        return Opacity(
          opacity: v,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 250,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    border:
                        Border.all(color: kGreen.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ]),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Session Complete!',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: kGreen)),
                    const SizedBox(height: 4),
                    const Text('15 cards  +30 points',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 9),
                    Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                          color: kGreen,
                          borderRadius: BorderRadius.circular(7)),
                      child: const Center(
                        child: Text('Back to Quran',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: kGreen.withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(7)),
                      child: const Center(
                        child: Text('Review More Cards',
                            style: TextStyle(
                                color: kGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  Widget _buildProgressDemo() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (_, v, __) {
        return Opacity(
          opacity: v,
          child: Container(
            width: 255,
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border:
                    Border.all(color: kGreen.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Your Progress',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: kGreen)),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceAround,
                    children: [
                      _pStat('Known', '541'),
                      _pStat('Streak', '7 days'),
                      _pStat('Today', '5'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Last 7 Days',
                      style:
                          TextStyle(fontSize: 8, color: Colors.grey)),
                  const SizedBox(height: 4),
                  _heatmapRow(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  Widget _pStat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: kGold)),
        const SizedBox(height: 1),
        Text(label,
            style: const TextStyle(
                fontSize: 7.5, color: Colors.grey)),
      ],
    );
  }
  Widget _heatmapRow() {
    final colors = [
      Colors.green.shade300,
      Colors.green.shade500,
      Colors.green.shade700,
      Colors.green.shade500,
      Colors.green.shade300,
      Colors.green.shade700,
      Colors.green.shade500,
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        7,
        (i) => Container(
          width: 28,
          height: 25,
          decoration: BoxDecoration(
              color: colors[i],
              borderRadius: BorderRadius.circular(3)),
        ),
      ),
    );
  }
  Widget _buildProgressRingDemo() => const _ProgressRingDemo();
  Widget _buildCoverageChartDemo() => const _BreakdownDemo();
  Widget _buildLoopDemo() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (_, v, __) {
        return Opacity(
          opacity: v,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _loopStep('\u{1F4D6}', 'Read Quran', kGreen),
              _loopArrow(),
              _loopStep('\u{1F446}', 'Tap unfamiliar word', Colors.blue),
              _loopArrow(),
              _loopStep('\u{1F50D}',
                  'Explore root & grammar', Colors.purple),
              _loopArrow(),
              _loopStep('\u{1F3AF}', 'Practice flashcards', Colors.orange),
              _loopArrow(),
              _loopStep('\u{1F504}', 'Review until known', Colors.green),
              const SizedBox(height: 4),
              const Text(
                  'Repeat daily -> watch your vocabulary grow',
                  style: TextStyle(
                      fontSize: 8,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic)),
            ],
          ),
        );
      },
    );
  }
  Widget _loopStep(String emoji, String label, Color color) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
  Widget _loopArrow() => const Padding(
      padding: EdgeInsets.only(top: 1, bottom: 1),
      child: Text('\u{2193}',
          style: TextStyle(fontSize: 11, color: Colors.grey)));
  Widget _buildFinalDemo() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (_, v, __) {
        return Transform.scale(
          scale: v,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                      colors: [kGreen, kTeal]),
                  border: Border.all(
                      color: kGold.withValues(alpha: 0.5),
                      width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: kGreen.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 5))
                  ],
                ),
                child: const Center(
                    child:
                        Text('\u{2728}', style: TextStyle(fontSize: 48))),
              ),
              const SizedBox(height: 9),
              Text('Baraka Allahu Feek',
                  style: GoogleFonts.amiriQuran(
                      fontSize: 17,
                      color: kGold,
                      height: 1.6)),
              const Text('May Allah bless your efforts',
                  style:
                      TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }
}

class _HideDemoWidget extends StatefulWidget {
  const _HideDemoWidget();
  @override
  State<_HideDemoWidget> createState() => _HideDemoWidgetState();
}
class _HideDemoWidgetState extends State<_HideDemoWidget> with SingleTickerProviderStateMixin {
  bool _known = false;
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 80));
    _anim = Tween<double>(begin: 1.0, end: 0.35).animate(_ctrl);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  void _toggle() {
    setState(() => _known = !_known);
    if (_known) { _ctrl.forward(); } else { _ctrl.reverse(); }
  }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) {
              return AnimatedOpacity(
                opacity: _anim.value,
                duration: const Duration(milliseconds: 80),
                child: Container(
                  width: 175,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _known ? Colors.green.withValues(alpha: 0.4) : Colors.grey.shade300),
                    boxShadow: [
                      _known
                          ? BoxShadow(color: Colors.green.withValues(alpha: 0.12), blurRadius: 6)
                          : BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _known ? 'Known' : 'كِتٰب',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.bold, color: kGreen),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _known ? 'Word hidden' : 'Tap to mark Known',
                        style: const TextStyle(fontSize: 9, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 5),
          Text(
            _known ? 'TAP TO UNHIDE' : 'TAP TO MARK KNOWN',
            style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}


class _SwipeDemo extends StatefulWidget {
  const _SwipeDemo();
  @override
  State<_SwipeDemo> createState() => _SwipeDemoState();
}
class _SwipeDemoState extends State<_SwipeDemo> {
  double _dragX = 0;
  String _result = '';
  Color _resultColor = Colors.transparent;
  bool _swiping = false;
  void _onPanUpdate(DragUpdateDetails d) {
    setState(() { _dragX += d.delta.dx; _swiping = true; });
  }
  void _onPanEnd(DragEndDetails d) {
    if (_dragX.abs() < 40) {
      setState(() { _dragX = 0; _swiping = false; });
      return;
    }
    final wasKnown = _dragX > 0;
    if (wasKnown) { setState(() { _result = '<- Forgotten'; _resultColor = Colors.red; }); }
    else { setState(() { _result = 'Remembered ->'; _resultColor = Colors.green; }); }
    _dragX = 0;
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() { _result = ''; _resultColor = Colors.transparent; _swiping = false; });
    });
  }
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 195,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _swiping
                  ? (_dragX > 30 ? Colors.green.withValues(alpha: 0.08) : (_dragX < -30 ? Colors.red.withValues(alpha: 0.08) : Colors.white))
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _dragX.abs() > 20
                    ? (_dragX > 0 ? Colors.green.withValues(alpha: 0.5) : Colors.red.withValues(alpha: 0.5))
                    : Colors.grey.shade300,
              ),
              boxShadow: [
                if (_dragX.abs() > 20)
                  BoxShadow(
                    color: (_dragX > 0 ? Colors.green : Colors.red).withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: Offset(_dragX * 0.03, 0),
                  ),
                if (!_swiping)
                  BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
                      const SizedBox(width: 7),
                      const Text('رَبّ', textDirection: TextDirection.rtl, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: kGreen)),
                      const SizedBox(width: 7),
                      const Text('Lord / Master', style: TextStyle(fontSize: 13, color: Colors.black87)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  const Text('frequency: 690x | Root: ر-ب-ب', style: TextStyle(fontSize: 8, color: Colors.grey)),
                  if (_result.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(_result, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _resultColor)),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        const Text('<- Swipe left = Remembered | Swipe right = Forgotten ->', style: TextStyle(fontSize: 7.5, color: Colors.grey)),
      ],
    );
  }
}

class _PointerDemo extends StatefulWidget {
  final String label;
  const _PointerDemo({required this.label});
  @override
  State<_PointerDemo> createState() => _PointerDemoState();
}
class _PointerDemoState extends State<_PointerDemo> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _anim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _ctrl.repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (_, v, __) {
                return Transform.scale(
                  scale: v,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(4)),
                        child: Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 7.5, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 2),
                      AnimatedBuilder(
                        animation: _anim,
                        builder: (_, __) => Transform.translate(
                          offset: Offset(3 * _anim.value, 0),
                          child: const Text('\u{1F446}', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
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

class _FlipDemo extends StatefulWidget {
  const _FlipDemo();
  @override
  State<_FlipDemo> createState() => _FlipDemoState();
}
class _FlipDemoState extends State<_FlipDemo> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _flipped = false;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  void _flip() {
    HapticFeedback.selectionClick();
    if (_flipped) { _ctrl.reverse(); } else { _ctrl.forward(); }
    setState(() => _flipped = !_flipped);
  }
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _flip,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final angle = _ctrl.value * 3.14159265;
              final showBack = angle > 1.5708; // pi/2
              final displayAngle = showBack ? angle - 3.14159265 : angle;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(displayAngle),
                child: Container(
                  width: 210,
                  height: 190,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: showBack
                            ? kGold.withValues(alpha: 0.5)
                            : kGreen.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: showBack ? _cardBack() : _cardFront(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _flipped ? 'TAP TO FLIP BACK' : 'TAP TO REVEAL MEANING',
          style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
  Widget _cardFront() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('رَحْمٰن',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: kGreen)),
          SizedBox(height: 8),
          Text('What does this word mean?',
              style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
  Widget _cardBack() {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(3.14159265),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('رَحْمٰن',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kGreen)),
          const SizedBox(height: 6),
          _cardBackRow('Meaning', 'The Most Merciful'),
          _cardBackRow('Root', 'ر-ح-م'),
          _cardBackRow('Transliteration', 'Ar-Rahman'),
          const SizedBox(height: 4),
          const Text('Sample Ayah:',
              style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
          const Text('اَلرَّحْمٰنِ الرَّحِيْمِ',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 13, color: kTeal)),
        ],
      ),
    );
  }
  Widget _cardBackRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
                text: '$label: ',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
            TextSpan(
                text: value,
                style: const TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w600, color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}

class _DailyGoalDemo extends StatefulWidget {
  const _DailyGoalDemo();
  @override
  State<_DailyGoalDemo> createState() => _DailyGoalDemoState();
}
class _DailyGoalDemoState extends State<_DailyGoalDemo> {
  double _goal = 5;
  @override
  Widget build(BuildContext context) {
    final yearly = (_goal * 365).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 230,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kGreen.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Daily Word Goal',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, color: kGreen)),
              const SizedBox(height: 6),
              Text('${_goal.round()} words/day',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: kGold)),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: _goal,
                  min: 1,
                  max: 50,
                  divisions: 49,
                  activeColor: kGreen,
                  inactiveColor: kGreen.withValues(alpha: 0.15),
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    setState(() => _goal = v);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '\u2248 $yearly new words / year',
                  style: const TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w600, color: kTeal),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        const Text('DRAG THE SLIDER TO ADJUST',
            style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ProgressRingDemo extends StatefulWidget {
  const _ProgressRingDemo();
  @override
  State<_ProgressRingDemo> createState() => _ProgressRingDemoState();
}
class _ProgressRingDemoState extends State<_ProgressRingDemo> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  static const double _target = 0.41; // 41% known
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _anim = Tween<double>(begin: 0, end: _target)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(150, 150),
                    painter: _RingPainter(_anim.value),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${(_anim.value * 100).round()}%',
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: kGreen)),
                      const Text('known',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text('541 of 1,342 words',
                style: TextStyle(fontSize: 9, color: Colors.grey)),
          ],
        );
      },
    );
  }
}
class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 8;
    final bgPaint = Paint()
      ..color = kGreen.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);
    final fgPaint = Paint()
      ..shader = const SweepGradient(colors: [kTeal, kGold])
          .createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    const startAngle = -3.14159265 / 2;
    final sweepAngle = 2 * 3.14159265 * progress;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle, false, fgPaint);
  }
  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ── Word detail single-toggle demo (matches real WordDetailDialog control) ────
class _WordDetailToggleDemo extends StatefulWidget {
  const _WordDetailToggleDemo();
  @override
  State<_WordDetailToggleDemo> createState() => _WordDetailToggleDemoState();
}
class _WordDetailToggleDemoState extends State<_WordDetailToggleDemo> {
  bool _known = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _known = !_known);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _known ? Colors.green : Colors.grey.withValues(alpha: 0.2),
          border: Border.all(
              color: _known ? Colors.green : Colors.grey.withValues(alpha: 0.4),
              width: 1.5),
        ),
        child: Icon(
          _known ? Icons.check : Icons.add,
          color: _known ? Colors.white : Colors.grey,
          size: 18,
        ),
      ),
    );
  }
}

// ── Progress Breakdown & Milestones demo (matches real Progress screen) ──────
class _BreakdownDemo extends StatefulWidget {
  const _BreakdownDemo();
  @override
  State<_BreakdownDemo> createState() => _BreakdownDemoState();
}
class _BreakdownDemoState extends State<_BreakdownDemo> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  static const _bars = [
    ('Words Known', 0.38, Colors.green),
    ('Words Discovered', 0.55, kTeal),
    ('300 Core Words', 0.62, kGold),
    ('Surahs Completed', 0.06, Color(0xFF00897B)),
  ];
  static const _milestones = [
    ('Beginner', true),
    ('Seeker', true),
    ('80% Quran', false),
    ('Scholar', false),
  ];
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        return Container(
          width: 255,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: kGreen.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ]),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Progress Breakdown',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kGreen)),
              const SizedBox(height: 8),
              ..._bars.map((b) {
                final (label, value, color) = b;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 8.5, color: Colors.grey.shade600)),
                      const SizedBox(height: 2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: value * _anim.value,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(color),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: _milestones.map((m) {
                  final (label, reached) = m;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: reached ? kGold.withValues(alpha: 0.15) : Colors.transparent,
                      border: Border.all(
                          color: reached ? kGold : Colors.grey.withValues(alpha: 0.3)),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 8,
                            color: reached ? kGold : Colors.grey,
                            fontWeight: reached ? FontWeight.bold : FontWeight.normal)),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}