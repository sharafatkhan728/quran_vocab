// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/analytics_service.dart';
// Play Store link sirf ek jagah badalna hai (ayah_share_card.dart mein)
import 'ayah_share_card.dart' show kPlayStoreLink;

/// Progress screen se score share karne ka card (image + caption + Play Store link).
class ProgressShareCard {
  static Future<void> share({
    required BuildContext context,
    required double percent,
    required int knownCount,
    required int totalVocab,
    required int streak,
    required int completedSurahs,
  }) async {
    final cardKey = GlobalKey();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProgressSharePreviewSheet(
        cardKey: cardKey,
        percent: percent,
        knownCount: knownCount,
        totalVocab: totalVocab,
        streak: streak,
        completedSurahs: completedSurahs,
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

String _fmt(int n) => n
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

String _levelFor(double pct) {
  if (pct >= 75) return 'Master';
  if (pct >= 50) return 'Advanced';
  if (pct >= 25) return 'Intermediate';
  if (pct >= 10) return 'Beginner';
  return 'Starter';
}

String _levelEmoji(double pct) {
  if (pct >= 75) return '👑';
  if (pct >= 50) return '🚀';
  if (pct >= 25) return '🌟';
  if (pct >= 10) return '🌿';
  return '🌱';
}

String _motivation(double pct) {
  if (pct < 2) return 'Every great journey begins with a single word 🌱';
  if (pct < 10) return 'MashaAllah! The Quran is starting to speak to me 🌟';
  if (pct < 25) return 'Words I once couldn\'t read now feel familiar ✨';
  if (pct < 50) return 'Alhamdulillah! Understanding the Quran feels closer every day 💚';
  return 'MashaAllah! I\'m well on my way to understanding the Quran 🏆';
}

class _Milestone {
  final int words;
  final String label;
  const _Milestone(this.words, this.label);
}

const _milestones = [
  _Milestone(50, 'Beginner'),
  _Milestone(100, 'Seeker'),
  _Milestone(300, 'Core Words'),
  _Milestone(500, 'Student'),
  _Milestone(1000, 'Scholar'),
  _Milestone(3000, 'Hafiz Path'),
  _Milestone(7000, 'Advanced'),
];

({int target, int base, String label}) _nextGoal(int known, int total) {
  int base = 0;
  for (final m in _milestones) {
    if (known < m.words) return (target: m.words, base: base, label: m.label);
    base = m.words;
  }
  return (target: total, base: base, label: 'Complete');
}

// ── Preview sheet ────────────────────────────────────────────────────────────

class _ProgressSharePreviewSheet extends StatefulWidget {
  final GlobalKey cardKey;
  final double percent;
  final int knownCount;
  final int totalVocab;
  final int streak;
  final int completedSurahs;

  const _ProgressSharePreviewSheet({
    required this.cardKey,
    required this.percent,
    required this.knownCount,
    required this.totalVocab,
    required this.streak,
    required this.completedSurahs,
  });

  @override
  State<_ProgressSharePreviewSheet> createState() =>
      _ProgressSharePreviewSheetState();
}

class _ProgressSharePreviewSheetState
    extends State<_ProgressSharePreviewSheet> {
  bool _sharing = false;
  int _selectedTheme = 0;

  static const _themes = [
    // Forest
    _ShareTheme(
      bgTop: Color(0xFF1B4332),
      bgBottom: Color(0xFF0A2016),
      surface: Color(0xFF0F2B1F),
      accent: Color(0xFFD4AF37),
      text: Colors.white,
      border: Color(0xFFD4AF37),
      ctaText: Color(0xFF1B4332),
    ),
    // Cream
    _ShareTheme(
      bgTop: Color(0xFFFFFBF2),
      bgBottom: Color(0xFFF1E6C8),
      surface: Colors.white,
      accent: Color(0xFF1B4332),
      text: Color(0xFF1A1A1A),
      border: Color(0xFFD4AF37),
      ctaText: Color(0xFFFDF8F0),
    ),
    // Midnight
    _ShareTheme(
      bgTop: Color(0xFF0E1F3D),
      bgBottom: Color(0xFF050B16),
      surface: Color(0xFF111E35),
      accent: Color(0xFF7EC8A0),
      text: Colors.white,
      border: Color(0xFF3E8E6B),
      ctaText: Color(0xFF0A1628),
    ),
    // Gold
    _ShareTheme(
      bgTop: Color(0xFF4A3400),
      bgBottom: Color(0xFF1F1600),
      surface: Color(0xFF2A1E00),
      accent: Color(0xFFFFD700),
      text: Color(0xFFFFF5CC),
      border: Color(0xFFD4AF37),
      ctaText: Color(0xFF3D2B00),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = _themes[_selectedTheme];

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.95),
      decoration: const BoxDecoration(
        color: Color(0xFF1B4332),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text('Share My Progress',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Pick a style, then share to Status or any chat',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_themes.length, (i) {
                  final sel = _selectedTheme == i;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTheme = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [_themes[i].bgTop, _themes[i].bgBottom],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              sel ? const Color(0xFFD4AF37) : Colors.white24,
                          width: sel ? 3 : 1,
                        ),
                      ),
                      child: sel
                          ? const Icon(Icons.check,
                              color: Color(0xFFD4AF37), size: 18)
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),

              // Yehi widget image ban kar share hota hai
              RepaintBoundary(
                key: widget.cardKey,
                child: _ProgressCard(
                  theme: theme,
                  percent: widget.percent,
                  knownCount: widget.knownCount,
                  totalVocab: widget.totalVocab,
                  streak: widget.streak,
                  completedSurahs: widget.completedSurahs,
                ),
              ),
              const SizedBox(height: 20),

              GestureDetector(
                onTap: _sharing ? null : _doShare,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color:
                        _sharing ? Colors.white24 : const Color(0xFFD4AF37),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: _sharing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.share,
                                  color: Color(0xFF1B4332), size: 20),
                              SizedBox(width: 8),
                              Text('Share',
                                  style: TextStyle(
                                      color: Color(0xFF1B4332),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doShare() async {
    setState(() => _sharing = true);
    try {
      final boundary = widget.cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/quran_kalima_progress.png');
      await file.writeAsBytes(pngBytes);

      final pct = widget.percent.toStringAsFixed(1);
      final shareText =
          '🌟 Alhamdulillah! I\'ve learned the meaning of $pct% of the words in the Quran — '
          '${_fmt(widget.knownCount)} words so far 📖✨\n'
          '${widget.streak > 0 ? '🔥 ${widget.streak}-day learning streak\n' : ''}'
          '\n💡 Just 5 words a day = 1,800+ words a year. Small steps, big change.\n\n'
          '🏆 Can you beat my score?\n'
          '📲 Download Quran Kalima — free on Google Play:\n'
          '$kPlayStoreLink\n\n'
          '#QuranKalima #LearnQuran #QuranVocabulary #QuranWordByWord';

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: shareText,
          subject: 'My Quran Kalima progress',
        ),
      );

      unawaited(AnalyticsService.logEvent('progress_shared',
          parameters: {'percent': widget.percent.round()}));

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Share failed: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

// ── The card itself (captured as image) ──────────────────────────────────────

class _ProgressCard extends StatelessWidget {
  final _ShareTheme theme;
  final double percent;
  final int knownCount;
  final int totalVocab;
  final int streak;
  final int completedSurahs;

  const _ProgressCard({
    required this.theme,
    required this.percent,
    required this.knownCount,
    required this.totalVocab,
    required this.streak,
    required this.completedSurahs,
  });

  @override
  Widget build(BuildContext context) {
    // System font-size setting se card ka layout na bigde
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: LayoutBuilder(builder: (context, c) {
        // Status/Story ke liye lamba (portrait) card
        final minH = c.maxWidth * 1.75;
        return Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: minH),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [theme.bgTop, theme.bgBottom],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.border, width: 2),
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              // Islamic star pattern
              Positioned.fill(
                child: CustomPaint(
                    painter:
                        _PatternPainter(theme.border.withValues(alpha: 0.10))),
              ),
              // Upar se soft glow
              Positioned(
                top: -90,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        theme.accent.withValues(alpha: 0.22),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _topGroup(),
                    const SizedBox(height: 16),
                    _middleGroup(),
                    const SizedBox(height: 16),
                    _bottomGroup(),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ── Group 1: brand + headline + ring + level ───────────────────────────────
  Widget _topGroup() {
    final n = percent.round();
    return Column(
      children: [
        // Brand row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1B4332),
                border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
              ),
              child: const Center(
                child: Text('ق',
                    style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFFD4AF37),
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            Text('Quran Kalima',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: theme.text)),
            const SizedBox(width: 6),
            Text('کلمۂ قرآن',
                style: TextStyle(
                    fontSize: 12, color: theme.accent.withValues(alpha: 0.9))),
          ],
        ),
        const SizedBox(height: 14),

        // Alhamdulillah calligraphy
        Text('الحمد لله',
            textDirection: TextDirection.rtl,
            style: GoogleFonts.amiri(
                fontSize: 34, color: theme.accent, height: 1.3)),
        const SizedBox(height: 6),

        // Headline
        Text.rich(
          TextSpan(
            style: TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: theme.text),
            children: percent >= 1
                ? [
                    const TextSpan(text: 'I\'ve learned the meaning of\n'),
                    TextSpan(
                        text: '$n out of every 100 words',
                        style: TextStyle(
                            color: theme.accent,
                            fontSize: 19,
                            fontWeight: FontWeight.w800)),
                    const TextSpan(text: ' in the Quran!'),
                  ]
                : [
                    const TextSpan(
                        text: 'I\'ve started learning the meaning of\n'),
                    TextSpan(
                        text: 'the Quran\'s words',
                        style: TextStyle(
                            color: theme.accent,
                            fontSize: 19,
                            fontWeight: FontWeight.w800)),
                    const TextSpan(text: '!'),
                  ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),

        // Ring
        SizedBox(
          width: 178,
          height: 178,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(178, 178),
                painter: _RingPainter(
                  percent: percent,
                  track: theme.border.withValues(alpha: 0.22),
                  arc: theme.accent,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${percent.toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: theme.accent,
                          height: 1.1)),
                  Text('of Quran words',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.text.withValues(alpha: 0.7))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Level pill + motivation
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: theme.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.accent.withValues(alpha: 0.6)),
          ),
          child: Text('${_levelEmoji(percent)}  ${_levelFor(percent)} Level',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.accent)),
        ),
        const SizedBox(height: 8),
        Text(_motivation(percent),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontStyle: FontStyle.italic,
                color: theme.text.withValues(alpha: 0.85))),
      ],
    );
  }

  // ── Group 2: stats + next goal + ayah ──────────────────────────────────────
  Widget _middleGroup() {
    final goal = _nextGoal(knownCount, totalVocab);
    final remaining = goal.target - knownCount;
    final span = goal.target - goal.base;
    final frac =
        span <= 0 ? 1.0 : ((knownCount - goal.base) / span).clamp(0.0, 1.0);

    return Column(
      children: [
        // Stat tiles
        Row(
          children: [
            Expanded(child: _tile('📚', _fmt(knownCount), 'Words Learned')),
            const SizedBox(width: 8),
            Expanded(child: _tile('⭐', _levelFor(percent), 'Level')),
            const SizedBox(width: 8),
            Expanded(
              child: streak > 0
                  ? _tile('🔥', '$streak', 'Day Streak')
                  : _tile('🕌', '$completedSurahs', 'Surahs Done'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Next goal
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: theme.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.border.withValues(alpha: 0.3)),
          ),
          child: remaining <= 0
              ? Center(
                  child: Text('🏆 Every word completed — MashaAllah!',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.accent)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('🎯 Next goal: ${goal.label}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: theme.text)),
                        Text('${_fmt(remaining)} to go',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.accent)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 8,
                        backgroundColor: theme.border.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation(theme.accent),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),

        // Ayah box (Al-Qamar 54:17 — Quran seekhne ki hausla-afzai)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: theme.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.border.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(
                'وَلَقَدْ يَسَّرْنَا الْقُرْآنَ لِلذِّكْرِ فَهَلْ مِن مُّدَّكِرٍ',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: GoogleFonts.amiri(
                    fontSize: 17, color: theme.accent, height: 1.9),
              ),
              const SizedBox(height: 2),
              Text(
                '“We have made the Quran easy to remember — so will you remember?”',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                    color: theme.text.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 3),
              Text('— Al-Qamar 54:17',
                  style: TextStyle(
                      fontSize: 9.5,
                      color: theme.accent.withValues(alpha: 0.85))),
            ],
          ),
        ),
      ],
    );
  }

  // ── Group 3: call to action ────────────────────────────────────────────────
  Widget _bottomGroup() {
    return Column(
      children: [
        _OrnamentLine(color: theme.border),
        const SizedBox(height: 12),

        // Main CTA
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              theme.accent,
              theme.accent.withValues(alpha: 0.82),
            ]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: theme.accent.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            children: [
              Text('🏆 Can you beat my score?',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: theme.ctaText)),
              const SizedBox(height: 2),
              Text('Start your Quran journey today — it\'s free!',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: theme.ctaText.withValues(alpha: 0.85))),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Feature chips
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip('📖 Word-by-word'),
            _chip('🃏 Smart flashcards'),
            _chip('🌍 Urdu • English • Hindi'),
          ],
        ),
        const SizedBox(height: 12),

        // Play Store style badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white38, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow_rounded,
                  color: Color(0xFF34D399), size: 28),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('GET IT ON',
                      style: TextStyle(
                          fontSize: 8,
                          letterSpacing: 1,
                          color: Colors.white70)),
                  Text('Google Play',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.1)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('Search “Quran Kalima” on Google Play',
            style: TextStyle(
                fontSize: 10, color: theme.text.withValues(alpha: 0.65))),
      ],
    );
  }

  // ── Small widgets ──────────────────────────────────────────────────────────
  Widget _tile(String emoji, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: theme.accent)),
          ),
          const SizedBox(height: 1),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 9.5, color: theme.text.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accent.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.text.withValues(alpha: 0.9))),
    );
  }
}

// ── Painters ─────────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double percent;
  final Color track;
  final Color arc;
  const _RingPainter(
      {required this.percent, required this.track, required this.arc});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 13.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke - 8) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);

    final p = (percent / 100).clamp(0.0, 1.0);
    if (p <= 0) return;
    // Chhota percent bhi dikhe
    final sweep = 2 * math.pi * math.max(p, 0.02);

    // Glow
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = arc.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 6
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Arc
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = arc
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    // End dot
    final endAngle = -math.pi / 2 + sweep;
    final endPoint = Offset(
      center.dx + radius * math.cos(endAngle),
      center.dy + radius * math.sin(endAngle),
    );
    canvas.drawCircle(endPoint, 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.percent != percent || old.arc != arc || old.track != track;
}

/// Halki si Islamic 8-point-star pattern (do square ek doosre par rotate).
class _PatternPainter extends CustomPainter {
  final Color color;
  const _PatternPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    const step = 46.0;
    const r = 15.0;
    int row = 0;
    for (double y = 0; y < size.height + step; y += step) {
      final shift = row.isOdd ? step / 2 : 0.0;
      for (double x = -step; x < size.width + step; x += step) {
        _star(canvas, Offset(x + shift, y), r, paint);
      }
      row++;
    }
  }

  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    for (int k = 0; k < 2; k++) {
      final path = Path();
      final offset = k == 0 ? math.pi / 4 : 0.0;
      for (int i = 0; i < 4; i++) {
        final a = offset + (math.pi / 2) * i;
        final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.color != color;
}

class _OrnamentLine extends StatelessWidget {
  final Color color;
  const _OrnamentLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Container(height: 0.5, color: color.withValues(alpha: 0.5))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            _diamond(4),
            const SizedBox(width: 4),
            _diamond(6),
            const SizedBox(width: 4),
            _diamond(4),
          ]),
        ),
        Expanded(
            child: Container(height: 0.5, color: color.withValues(alpha: 0.5))),
      ],
    );
  }

  Widget _diamond(double size) => Transform.rotate(
        angle: 0.785398,
        child: Container(
            width: size, height: size, color: color.withValues(alpha: 0.7)),
      );
}

class _ShareTheme {
  final Color bgTop;
  final Color bgBottom;
  final Color surface;
  final Color accent;
  final Color text;
  final Color border;
  final Color ctaText;
  const _ShareTheme({
    required this.bgTop,
    required this.bgBottom,
    required this.surface,
    required this.accent,
    required this.text,
    required this.border,
    required this.ctaText,
  });
}