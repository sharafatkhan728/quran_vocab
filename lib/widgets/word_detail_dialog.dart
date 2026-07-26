import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/word.dart';
import '../providers/display_provider.dart';
import '../providers/theme_provider.dart';
import '../services/word_progress_service.dart';
// import 'morphology_sheet.dart';
import '../screens/morphology_sheet.dart';

class WordDetailDialog extends StatefulWidget {
  final QuranWord word;
  final int surahId;
  final int ayahId;
  final bool isKnown;
  final List<QuranWord> ayahWords;
  final Function(bool) onKnownToggled;

  const WordDetailDialog({
    super.key,
    required this.word,
    required this.surahId,
    required this.ayahId,
    required this.isKnown,
    required this.ayahWords,
    required this.onKnownToggled,
  });

  @override
  State<WordDetailDialog> createState() => _WordDetailDialogState();
}

class _WordDetailDialogState extends State<WordDetailDialog> {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);
  static const _teal = Color(0xFF2D6A4F);

  late bool _isKnown;

  @override
  void initState() {
    super.initState();
    _isKnown = widget.isKnown;
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    final nowKnown = await WordProgressService.toggleWord(widget.word.arabic);
    if (mounted) {
      setState(() => _isKnown = nowKnown);
      widget.onKnownToggled(nowKnown);
    }
  }

  void _openMorphology() {
    Navigator.pop(context);
    final parts = widget.word.id.split(':');
    final wordPos = parts.length >= 3 ? int.tryParse(parts[2]) ?? 1 : 1;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MorphologySheet(
        word: widget.word,
        surahId: widget.surahId,
        ayahId: widget.ayahId,
        wordPos: wordPos,
        ayahWords: widget.ayahWords,
        isKnown: _isKnown,
        onKnownToggled: widget.onKnownToggled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final display = context.watch<DisplayProvider>();
    final theme = context.watch<ThemeProvider>();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D1B12) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _gold.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1A2E1F), const Color(0xFF0D1B12)]
                      : [const Color(0xFFF0F7F0), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  bottom: BorderSide(color: _gold.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                children: [
                  // Arabic word
                  Expanded(
                    child: Text(
                      widget.word.arabic,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: _arabicStyle(theme, isDark, 40),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Known toggle button
                  GestureDetector(
                    onTap: _toggle,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isKnown
                            ? Colors.green
                            : Colors.grey.withValues(alpha: 0.2),
                        border: Border.all(
                          color: _isKnown
                              ? Colors.green
                              : Colors.grey.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        _isKnown ? Icons.check : Icons.add,
                        color: _isKnown ? Colors.white : Colors.grey,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Close button
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withValues(alpha: 0.1),
                      ),
                      child:
                          const Icon(Icons.close, color: Colors.red, size: 16),
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Urdu meaning
                  if (widget.word.urduMeaning.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? _teal.withValues(alpha: 0.15)
                            : const Color(0xFFF0FAF4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _teal.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        widget.word.urduMeaning,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: 'JameelNoori',
                          fontSize: display.urduFontSize + 6,
                          color: isDark ? const Color(0xFF7EC8A0) : _teal,
                          fontWeight: FontWeight.w600,
                          height: 1.6,
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Grammar segments row
                  if (widget.word.segments.isNotEmpty)
                    _buildSegmentsRow(isDark, display),

                  const SizedBox(height: 16),

                  // Root info
                  if (widget.word.root.isNotEmpty)
                    _buildRootChip(isDark, theme),

                  const SizedBox(height: 16),

                  // Known / Unknown label
                  Center(
                    child: Text(
                      _isKnown ? '✓ یاد ہے' : 'نہیں جانتا',
                      style: TextStyle(
                        fontFamily: 'JameelNoori',
                        fontSize: 14,
                        color: _isKnown
                            ? Colors.green.shade600
                            : Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Learn More button
                  GestureDetector(
                    onTap: _openMorphology,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_green, _teal],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _gold.withValues(alpha: 0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: _green.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.school_outlined,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Learn More About This Word',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentsRow(bool isDark, DisplayProvider display) {
    final segments =
        widget.word.segments.where((s) => s.pos.isNotEmpty).toList();
    if (segments.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: segments.map((seg) {
        Color color;
        try {
          if (seg.colorHex.isNotEmpty && seg.colorHex != '#888888') {
            color = Color(int.parse(seg.colorHex.replaceFirst('#', '0xFF')));
          } else {
            color = _posToColor(seg.pos);
          }
        } catch (_) {
          color = _posToColor(seg.pos);
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _segTypeLabel(seg),
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRootChip(bool isDark, ThemeProvider theme) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _gold.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Root: ',
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.grey.shade600),
            ),
            Text(
              widget.word.root.characters.join('  '),
              textDirection: TextDirection.rtl,
              style: _arabicStyle(theme, isDark, 20).copyWith(color: _gold),
            ),
          ],
        ),
      ),
    );
  }

  String _segTypeLabel(WordSegment seg) {
    final typeStr = seg.type == SegType.prefix
        ? 'Prefix'
        : seg.type == SegType.suffix
            ? 'Suffix'
            : seg.pos;
    return typeStr;
  }

  Color _posToColor(String pos) {
    switch (pos) {
      case 'V':
        return Colors.red.shade400;
      case 'N':
        return Colors.blue.shade400;
      case 'PN':
        return Colors.blue.shade600;
      case 'P':
        return Colors.green.shade500;
      case 'CONJ':
        return Colors.green.shade400;
      case 'PRON':
        return Colors.orange.shade400;
      case 'DEM':
        return Colors.orange.shade300;
      case 'REL':
        return Colors.purple.shade400;
      default:
        return Colors.grey.shade500;
    }
  }

  TextStyle _arabicStyle(ThemeProvider theme, bool isDark, double size) {
    final color = isDark ? Colors.white : const Color(0xFF1A1A1A);
    // arabicFont now lives in DisplayProvider only
    final display = context.read<DisplayProvider>();
    switch (display.arabicFont) {
      case 'indopak':
        return TextStyle(
            fontFamily: 'IndoPak', fontSize: size, color: color, height: 1.6);
      case 'noorehuda':
        return TextStyle(
            fontFamily: 'NoorehudaFont',
            fontSize: size,
            color: color,
            height: 1.6);
      default:
        return GoogleFonts.amiriQuran(
            fontSize: size, color: color, height: 1.6);
    }
  }
}
