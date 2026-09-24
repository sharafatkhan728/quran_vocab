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

/// Progress screen se score share karne ka card (image + text + Play Store link).
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
    _ShareTheme(
      bg: Color(0xFF1B4332),
      surface: Color(0xFF0F2B1F),
      accent: Color(0xFFD4AF37),
      text: Colors.white,
      border: Color(0xFFD4AF37),
    ),
    _ShareTheme(
      bg: Color(0xFFFDF8F0),
      surface: Color(0xFFF5EED8),
      accent: Color(0xFF1B4332),
      text: Color(0xFF1A1A1A),
      border: Color(0xFFD4AF37),
    ),
    _ShareTheme(
      bg: Color(0xFF0A1628),
      surface: Color(0xFF111E35),
      accent: Color(0xFF7EC8A0),
      text: Colors.white,
      border: Color(0xFF2D6A4F),
    ),
    _ShareTheme(
      bg: Color(0xFF3D2B00),
      surface: Color(0xFF2A1E00),
      accent: Color(0xFFFFD700),
      text: Color(0xFFFFF5CC),
      border: Color(0xFFD4AF37),
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
              const Text('Choose a card theme',
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
                        color: _themes[i].bg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel
                              ? const Color(0xFFD4AF37)
                              : Colors.white24,
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
          'I know $pct% of the Quran\'s words 📖 — ${_fmt(widget.knownCount)} words learned'
          '${widget.streak > 0 ? ', ${widget.streak}-day streak 🔥' : ''}\n\n'
          'Learn the Quran word by word with Quran Kalima:\n'
          '$kPlayStoreLink\n\n'
          '#QuranKalima #LearnQuran #QuranVocabulary';

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: BoxDecoration(
        color: theme.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.border, width: 2),
      ),
      child: Column(
        children: [
          Text('﷽',
              style: TextStyle(fontSize: 28, color: theme.accent, height: 1.5)),
          const SizedBox(height: 4),
          _OrnamentLine(color: theme.border),
          const SizedBox(height: 14),
          Text('My Quran Vocabulary Progress',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: theme.text)),
          const SizedBox(height: 2),
          Text('تقدمي في القرآن',
              textDirection: TextDirection.rtl,
              style: GoogleFonts.amiri(fontSize: 15, color: theme.accent)),
          const SizedBox(height: 16),

          // Percentage ring
          SizedBox(
            width: 170,
            height: 170,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(170, 170),
                  painter: _RingPainter(
                    percent: percent,
                    track: theme.border.withValues(alpha: 0.25),
                    arc: theme.accent,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${percent.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: theme.accent)),
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

          // Level pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: theme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.accent.withValues(alpha: 0.6)),
            ),
            child: Text('⭐ ${_levelFor(percent)}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.accent)),
          ),
          const SizedBox(height: 16),

          // Stats
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.border.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat(_fmt(knownCount), 'Words Known'),
                _divider(),
                _stat('$streak', 'Day Streak'),
                _divider(),
                _stat('$completedSurahs', 'Surahs Done'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _OrnamentLine(color: theme.border),
          const SizedBox(height: 12),

          Text('Learn the Quran word by word',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.text.withValues(alpha: 0.9))),
          const SizedBox(height: 12),

          // Branding footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.border.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1B4332),
                    border:
                        Border.all(color: const Color(0xFFD4AF37), width: 1),
                  ),
                  child: const Center(
                    child: Text('ق',
                        style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFFD4AF37),
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Quran Kalima',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.text,
                            letterSpacing: 0.5)),
                    Text('کلمۂ قرآن  •  Get on Play Store',
                        style: TextStyle(
                            fontSize: 9,
                            color: theme.accent.withValues(alpha: 0.8))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.accent)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 10, color: theme.text.withValues(alpha: 0.7))),
      ],
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 30, color: theme.border.withValues(alpha: 0.3));
}

class _RingPainter extends CustomPainter {
  final double percent;
  final Color track;
  final Color arc;
  const _RingPainter(
      {required this.percent, required this.track, required this.arc});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);

    final sweep = 2 * math.pi * (percent / 100).clamp(0.0, 1.0);
    if (sweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = arc
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.percent != percent || old.arc != arc || old.track != track;
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
  final Color bg;
  final Color surface;
  final Color accent;
  final Color text;
  final Color border;
  const _ShareTheme({
    required this.bg,
    required this.surface,
    required this.accent,
    required this.text,
    required this.border,
  });
}