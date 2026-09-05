import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/word.dart';
import '../providers/display_provider.dart';
import '../services/morphology_service.dart';
import '../services/word_glossary_service.dart';

class WordTile extends StatelessWidget {
  final QuranWord word;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const WordTile({
    super.key,
    required this.word,
    required this.onTap,
    required this.onLongPress,
  });

  static Color _posColor(String pos, bool isDark) {
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
      case 'ADJ':
        return Colors.teal.shade400;
      case 'NEG':
        return Colors.red.shade300;
      default:
        return isDark ? Colors.white70 : Colors.grey.shade700;
    }
  }

  /// Use colorHex from database if available, fall back to hardcoded map.
  static Color _wordColor(QuranWord word, bool isDark) {
    final hex = word.colorHex;
    if (hex.isNotEmpty && hex != '#888888') {
      try {
        return Color(int.parse(hex.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    return _posColor(word.pos, isDark);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final display = context.watch<DisplayProvider>();
    final arabicFontSize = display.arabicFontSize;
    final urduFontSize = display.urduFontSize;

    if (word.isWaqf) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Text(
          word.arabic,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontSize: arabicFontSize * 0.7,
            color: isDark ? Colors.white38 : Colors.grey.shade400,
          ),
        ),
      );
    }

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
            segments.length > 1
                ? _buildSegmentedWord(segments, display, isDark, arabicFontSize)
                : _buildSingleWord(word, display, isDark, arabicFontSize),
            const SizedBox(height: 2),
            if (word.urduMeaning.isNotEmpty && !word.isKnown)
              SizedBox(
                width: 50,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _buildMeaning(isDark, urduFontSize),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeaning(bool isDark, double urduFontSize) {
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
              style: TextStyle(
                  fontSize: urduFontSize,
                  color: isDark ? Colors.white54 : Colors.grey.shade600));
    } else {
      textWidget = Text(
        meaningText,
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
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
        IntrinsicWidth(
          child: Container(
            height: 0.5,
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

  Widget _buildSingleWord(QuranWord word, DisplayProvider display, bool isDark,
      double arabicFontSize) {
    final color = _wordColor(word, isDark);
    return Text(
      word.arabic,
      textDirection: TextDirection.rtl,
      style: _arabicStyle(display, color, arabicFontSize),
    );
  }

  Widget _buildSegmentedWord(List<WordSegment> segs, DisplayProvider display,
      bool isDark, double arabicFontSize) {
    final segTexts = MorphologyService.extractSegmentTexts(word.arabic, segs);
    return RichText(
      textDirection: TextDirection.rtl,
      text: TextSpan(
        children: segTexts.map((st) {
          final segPos = st.seg?.pos ?? '';
          final segColorHex = st.seg?.colorHex ?? '';
          Color color;
          if (segColorHex.isNotEmpty && segColorHex != '#888888') {
            try {
              color = Color(int.parse(segColorHex.replaceFirst('#', '0xFF')));
            } catch (_) {
              color = segPos.isNotEmpty
                  ? _posColor(segPos, isDark)
                  : (isDark ? Colors.white : const Color(0xFF1A1A1A));
            }
          } else {
            color = segPos.isNotEmpty
                ? _posColor(segPos, isDark)
                : (isDark ? Colors.white : const Color(0xFF1A1A1A));
          }
          return TextSpan(
            text: st.text,
            style: _arabicStyle(display, color, arabicFontSize),
          );
        }).toList(),
      ),
    );
  }

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
        return Colors.red.shade400;
      case 'n':
        return Colors.blue.shade400;
      case 'pn':
        return Colors.blue.shade600;
      case 'p':
        return Colors.green.shade500;
      case 'paren':
        return Colors.grey.shade400;
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
