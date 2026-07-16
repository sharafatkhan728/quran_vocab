import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/word.dart';
import '../providers/display_provider.dart';
import '../services/morphology_service.dart';
import '../services/word_glossary_service.dart';

class WordTile extends StatelessWidget {
  final QuranWord word;
  final double arabicFontSize;
  final double urduFontSize;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const WordTile({
    super.key,
    required this.word,
    required this.arabicFontSize,
    required this.urduFontSize,
    required this.onTap,
    required this.onLongPress,
  });

  // POS → color mapping
  static Color _posColor(String pos, bool isDark) {
    switch (pos) {
      case 'V':
        return Colors.red.shade400; // verb
      case 'N':
        return Colors.blue.shade400; // noun
      case 'PN':
        return Colors.blue.shade600; // proper noun
      case 'P':
        return Colors.green.shade500; // preposition/particle
      case 'CONJ':
        return Colors.green.shade400; // conjunction
      case 'PRON':
        return Colors.orange.shade400; // pronoun
      case 'DEM':
        return Colors.orange.shade300; // demonstrative
      case 'REL':
        return Colors.purple.shade400; // relative
      case 'ADJ':
        return Colors.teal.shade400; // adjective
      case 'NEG':
        return Colors.red.shade300; // negation
      default:
        return isDark ? Colors.white70 : Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final display = context.watch<DisplayProvider>();

    final segments = word.segments.where((s) => s.pos.isNotEmpty).toList();

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Arabic — NEVER fades, NEVER moves
            segments.length > 1
                ? _buildSegmentedWord(segments, display, isDark)
                : _buildSingleWord(display, isDark),

            const SizedBox(height: 2),

            // Urdu/meaning — hides when known, but keeps space to avoid shift
            // Urdu/meaning — keeps BOTH width and height

            if (word.urduMeaning.isNotEmpty)
              SizedBox(
                width: 50,
                child: Visibility(
                  visible: !word.isKnown,
                  maintainState: true,
                  maintainAnimation: true,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _buildMeaning(isDark),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeaning(bool isDark) {
    final lang = WordGlossaryService.selectedLang;
    final meaningText = word.urduMeaning;

    Widget textWidget;
    if (lang == 'en') {
      final rawHtml = WordGlossaryService.getRawByPosition(
        int.parse(word.id.split(':')[0]),
        int.parse(word.id.split(':')[1]),
        int.parse(word.id.split(':')[2]),
      );
      textWidget = rawHtml.isNotEmpty
          ? _buildEnglishMeaning(rawHtml, urduFontSize, isDark)
          : Text(meaningText,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: urduFontSize,
                  color: isDark ? Colors.white54 : Colors.grey.shade600));
    } else {
      textWidget = Text(
        meaningText,
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
        // Wrap after 3 words
        softWrap: true,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: lang == 'ur' ? 'JameelNoori' : null,
          fontSize: urduFontSize,
          color: isDark ? Colors.white54 : Colors.grey.shade600,
          height: 1.4,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        textWidget,
        // Faint line — same width as text, not full screen
        IntrinsicWidth(
          child: Container(
            height: 0.5,
            // Minimum width so line is always visible
            constraints: const BoxConstraints(minWidth: 20),
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.3),
            ),
          ),
        ),
      ],
    );
  }

  /// Whole word, colored by stem POS
  Widget _buildSingleWord(DisplayProvider display, bool isDark) {
    final pos = word.pos;
    final color = pos.isNotEmpty
        ? _posColor(pos, isDark)
        : (isDark ? Colors.white : const Color(0xFF1A1A1A));

    return Text(
      word.arabic,
      textDirection: TextDirection.rtl,
      style: _arabicStyle(display, color, arabicFontSize),
    );
  }

  Widget _buildSegmentedWord(
      List<WordSegment> segs, DisplayProvider display, bool isDark) {
    final segTexts = MorphologyService.extractSegmentTexts(word.arabic, segs);

    // Use RichText with TextSpan — keeps word together, no breaking
    return RichText(
      textDirection: TextDirection.rtl,
      text: TextSpan(
        children: segTexts.map((st) {
          final pos = st.seg?.pos ?? '';
          final color = pos.isNotEmpty
              ? _posColor(pos, isDark)
              : (isDark ? Colors.white : const Color(0xFF1A1A1A));
          return TextSpan(
            text: st.text,
            style: _arabicStyle(display, color, arabicFontSize),
          );
        }).toList(),
      ),
    );
  }

  // Parse English HTML meaning like <span class='p'>In</span>
  static Widget _buildEnglishMeaning(
      String rawHtml, double fontSize, bool isDark) {
    if (!rawHtml.contains('<span')) {
      return Text(rawHtml,
          style: TextStyle(
              fontSize: fontSize,
              color: isDark ? Colors.white54 : Colors.grey.shade600));
    }

    final spans = <InlineSpan>[];
    final regex = RegExp(r"<span class='(\w+)'>(.*?)</span>");
    int last = 0;

    for (final match in regex.allMatches(rawHtml)) {
      // Text before span
      if (match.start > last) {
        spans.add(TextSpan(
            text: rawHtml.substring(last, match.start),
            style: TextStyle(
                fontSize: fontSize,
                color: isDark ? Colors.white54 : Colors.grey.shade600)));
      }
      final cls = match.group(1) ?? '';
      final text = match.group(2) ?? '';
      final color = _englishSpanColor(cls, isDark);
      spans.add(TextSpan(
          text: text,
          style: TextStyle(
              fontSize: fontSize,
              color: color,
              fontWeight: cls == 'pn' ? FontWeight.w600 : FontWeight.normal)));
      last = match.end;
    }
    if (last < rawHtml.length) {
      spans.add(TextSpan(
          text: rawHtml.substring(last),
          style: TextStyle(
              fontSize: fontSize,
              color: isDark ? Colors.white54 : Colors.grey.shade600)));
    }

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(children: spans),
    );
  }

  static Color _englishSpanColor(String cls, bool isDark) {
    switch (cls) {
      case 'v':
        return Colors.red.shade400; // verb
      case 'n':
        return Colors.blue.shade400; // noun
      case 'pn':
        return Colors.blue.shade600; // proper noun
      case 'p':
        return Colors.green.shade500; // preposition/particle
      case 'paren':
        return Colors.grey.shade400; // parenthetical
      default:
        return isDark ? Colors.white70 : Colors.grey.shade700;
    }
  }

  TextStyle _arabicStyle(DisplayProvider d, Color color, double size) {
    switch (d.arabicFont) {
      case 'indopak':
        return TextStyle(
            fontFamily: 'IndoPak', fontSize: size, color: color, height: 1.8);
      case 'noorehuda':
        return TextStyle(
            fontFamily: 'NoorehudaFont',
            fontSize: size,
            color: color,
            height: 1.8);
      default:
        return GoogleFonts.amiriQuran(
            fontSize: size, color: color, height: 1.8);
    }
  }
}
