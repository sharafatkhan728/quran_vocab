// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';


/// Paste your Play Store link here when app is published
const String kPlayStoreLink =
    'https://play.google.com/store/apps/details?id=com.qurankalima.app';

/// Share an ayah as a beautiful Islamic styled image card
class AyahShareCard {
  static final GlobalKey _cardKey = GlobalKey();

  /// Main entry point — shows preview bottom sheet then shares
  static Future<void> share({
    required BuildContext context,
    required int surahId,
    required String surahNameEnglish,
    required String surahNameArabic,
    required int ayahNumber,
    required String arabicText,
    required String translation,
    required String translationLang,
    required String scholarName,
    required String arabicFont,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SharePreviewSheet(
        cardKey: _cardKey,
        surahId: surahId,
        surahNameEnglish: surahNameEnglish,
        surahNameArabic: surahNameArabic,
        ayahNumber: ayahNumber,
        arabicText: arabicText,
        translation: translation,
        translationLang: translationLang,
        scholarName: scholarName,
        arabicFont: arabicFont,
      ),
    );
  }
}

class _SharePreviewSheet extends StatefulWidget {
  final GlobalKey cardKey;
  final int surahId;
  final String surahNameEnglish;
  final String surahNameArabic;
  final int ayahNumber;
  final String arabicText;
  final String translation;
  final String translationLang;
  final String scholarName;
  final String arabicFont;

  const _SharePreviewSheet({
    required this.cardKey,
    required this.surahId,
    required this.surahNameEnglish,
    required this.surahNameArabic,
    required this.ayahNumber,
    required this.arabicText,
    required this.translation,
    required this.translationLang,
    required this.scholarName,
    required this.arabicFont,
  });

  @override
  State<_SharePreviewSheet> createState() => _SharePreviewSheetState();
}

class _SharePreviewSheetState extends State<_SharePreviewSheet> {
  bool _sharing = false;
  int _selectedTheme = 0;

  static const _themes = [
    _CardTheme(
      name: 'Forest',
      bg: Color(0xFF1B4332),
      surface: Color(0xFF0F2B1F),
      arabic: Color(0xFFD4AF37),
      text: Colors.white,
      accent: Color(0xFFD4AF37),
      border: Color(0xFFD4AF37),
    ),
    _CardTheme(
      name: 'Cream',
      bg: Color(0xFFFDF8F0),
      surface: Color(0xFFF5EED8),
      arabic: Color(0xFF1B4332),
      text: Color(0xFF1A1A1A),
      accent: Color(0xFF1B4332),
      border: Color(0xFFD4AF37),
    ),
    _CardTheme(
      name: 'Midnight',
      bg: Color(0xFF0A1628),
      surface: Color(0xFF111E35),
      arabic: Color(0xFF7EC8A0),
      text: Colors.white,
      accent: Color(0xFF7EC8A0),
      border: Color(0xFF2D6A4F),
    ),
    _CardTheme(
      name: 'Gold',
      bg: Color(0xFF3D2B00),
      surface: Color(0xFF2A1E00),
      arabic: Color(0xFFFFD700),
      text: Color(0xFFFFF5CC),
      accent: Color(0xFFFFD700),
      border: Color(0xFFD4AF37),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = _themes[_selectedTheme];

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1B4332),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          const Text('Share Ayah',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Choose a card theme',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 16),

          // Theme selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_themes.length, (i) {
              final t = _themes[i];
              final sel = _selectedTheme == i;
              return GestureDetector(
                onTap: () => setState(() => _selectedTheme = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: t.bg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel ? const Color(0xFFD4AF37) : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: sel
                      ? const Icon(Icons.check,
                          color: Color(0xFFD4AF37), size: 20)
                      : null,
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // Card preview
          RepaintBoundary(
            key: widget.cardKey,
            child: _AyahCard(
              theme: theme,
              surahId: widget.surahId,
              surahNameEnglish: widget.surahNameEnglish,
              surahNameArabic: widget.surahNameArabic,
              ayahNumber: widget.ayahNumber,
              arabicText: widget.arabicText,
              translation: widget.translation,
              translationLang: widget.translationLang,
              scholarName: widget.scholarName,
              arabicFont: widget.arabicFont,
            ),
          ),
          const SizedBox(height: 20),

          // Share button
          GestureDetector(
            onTap: _sharing ? null : () => _doShare(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: _sharing
                    ? Colors.white24
                    : const Color(0xFFD4AF37),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _sharing
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.share, color: Color(0xFF1B4332), size: 20),
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
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }

  Future<void> _doShare(BuildContext context) async {
    setState(() => _sharing = true);
    try {
      // Capture card as image
      final boundary = widget.cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = File(
          '${tempDir.path}/quran_ayah_${widget.surahId}_${widget.ayahNumber}.png');
      await file.writeAsBytes(pngBytes);

      final surahRef =
          'Surah ${widget.surahNameEnglish} (${widget.surahId}:${widget.ayahNumber})';
      final shareText =
          '$surahRef\n\nLearn Quran vocabulary with Quran Kalima:\n$kPlayStoreLink';

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: shareText,
          subject: 'Quran Ayah — $surahRef',
        ),
      );

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

/// The actual card that gets rendered and captured as image
class _AyahCard extends StatelessWidget {
  final _CardTheme theme;
  final int surahId;
  final String surahNameEnglish;
  final String surahNameArabic;
  final int ayahNumber;
  final String arabicText;
  final String translation;
  final String translationLang;
  final String scholarName;
  final String arabicFont;

  const _AyahCard({
    required this.theme,
    required this.surahId,
    required this.surahNameEnglish,
    required this.surahNameArabic,
    required this.ayahNumber,
    required this.arabicText,
    required this.translation,
    required this.translationLang,
    required this.scholarName,
    required this.arabicFont,
  });

    TextStyle _arabicStyle(double size, Color color) {
      switch (arabicFont) {
        case 'indopak':
          return TextStyle(
              fontFamily: 'IndoPak', fontSize: size, color: color, height: 2.0);
        case 'noorehuda':
          return TextStyle(
              fontFamily: 'NoorehudaFont',
              fontSize: size,
              color: color,
              height: 2.0);
        default:
          return GoogleFonts.amiriQuran(fontSize: size, color: color, height: 2.0);
      }
    }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.border, width: 2),
      ),
      child: Stack(
        children: [
          // Islamic geometric corner ornaments
          Positioned(top: 12, left: 12,
              child: _CornerOrnament(color: theme.border, rotate: 0)),
          Positioned(top: 12, right: 12,
              child: _CornerOrnament(color: theme.border, rotate: 90)),
          Positioned(bottom: 12, left: 12,
              child: _CornerOrnament(color: theme.border, rotate: 270)),
          Positioned(bottom: 12, right: 12,
              child: _CornerOrnament(color: theme.border, rotate: 180)),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Bismillah
                Text('﷽',
                    style: TextStyle(
                        fontSize: 28,
                        color: theme.arabic,
                        height: 1.5)),
                const SizedBox(height: 4),

                // Top border line
                _OrnamentLine(color: theme.border),
                const SizedBox(height: 16),

                // Arabic text
                Text(
                  arabicText,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style: _arabicStyle(22, theme.arabic),
                ),
                const SizedBox(height: 16),

                // Translation
                if (translation.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: theme.border.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      translation,
                      textDirection: translationLang == 'en'
                          ? TextDirection.ltr
                          : TextDirection.rtl,
                      textAlign: translationLang == 'en'
                          ? TextAlign.left
                          : TextAlign.right,
                      style: TextStyle(
                        fontFamily: translationLang == 'en'
                            ? null
                            : 'JameelNoori',
                        fontSize: translationLang == 'en' ? 13 : 15,
                        color: theme.text.withValues(alpha: 0.85),
                        height: 1.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (scholarName.isNotEmpty)
                    Text(
                      '— $scholarName',
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.accent.withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic),
                    ),
                  const SizedBox(height: 12),
                ],

                // Bottom divider
                _OrnamentLine(color: theme.border),
                const SizedBox(height: 12),

                // Reference
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      surahNameArabic,
                      textDirection: TextDirection.rtl,
                      style: GoogleFonts.amiriQuran(
                          fontSize: 16, color: theme.accent),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 1,
                      height: 14,
                      color: theme.border.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Surah $surahNameEnglish  •  $surahId : $ayahNumber',
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.text.withValues(alpha: 0.75),
                          letterSpacing: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // App branding footer
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: theme.border.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // App logo mini
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1B4332),
                          border: Border.all(
                              color: const Color(0xFFD4AF37), width: 1),
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
                                  color:
                                      theme.accent.withValues(alpha: 0.8))),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
          child: Row(
            children: [
              _diamond(color),
              const SizedBox(width: 4),
              _diamond(color, size: 6),
              const SizedBox(width: 4),
              _diamond(color),
            ],
          ),
        ),
        Expanded(
            child: Container(height: 0.5, color: color.withValues(alpha: 0.5))),
      ],
    );
  }

  Widget _diamond(Color c, {double size = 4}) {
    return Transform.rotate(
      angle: 0.785398,
      child: Container(
        width: size,
        height: size,
        color: c.withValues(alpha: 0.7),
      ),
    );
  }
}

class _CornerOrnament extends StatelessWidget {
  final Color color;
  final double rotate;
  const _CornerOrnament({required this.color, required this.rotate});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotate * 3.14159 / 180,
      child: CustomPaint(
        size: const Size(24, 24),
        painter: _CornerPainter(color: color),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  const _CornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, size.height), const Offset(0, 0), p);
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), p);
    canvas.drawLine(const Offset(6, 0), const Offset(6, 6), p);
    canvas.drawLine(const Offset(0, 6), const Offset(6, 6), p);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _CardTheme {
  final String name;
  final Color bg;
  final Color surface;
  final Color arabic;
  final Color text;
  final Color accent;
  final Color border;
  const _CardTheme({
    required this.name,
    required this.bg,
    required this.surface,
    required this.arabic,
    required this.text,
    required this.accent,
    required this.border,
  });
}