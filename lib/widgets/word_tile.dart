// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/word.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/display_provider.dart';

class WordTile extends StatelessWidget {
  final QuranWord word;
  final VoidCallback onLongPress;
  final VoidCallback onTap;
  final double arabicFontSize;
  final double urduFontSize;

  const WordTile({
    super.key,
    required this.word,
    required this.onLongPress,
    required this.onTap,
    this.arabicFontSize = 26,
    this.urduFontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: word.isKnown
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: word.isKnown
              ? Border.all(color: Colors.green.withValues(alpha: 0.4))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word.arabic,
              textDirection: TextDirection.rtl,
              style: _arabicTextStyle(context, arabicFontSize),
            ),
            const SizedBox(height: 4),
            AnimatedOpacity(
              opacity: word.isKnown ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: SizedBox(
                height: word.isKnown ? 0 : null,
                child: Text(
                  word.urduMeaning,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: 'JameelNoori',
                    fontSize: urduFontSize,
                    color: Theme.of(context).colorScheme.primary,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle _arabicTextStyle(BuildContext context, double size) {
  final display = context.watch<DisplayProvider>();
  final font = display.arabicFont;
  final color = Theme.of(context).colorScheme.onSurface;
  switch (font) {
    case 'indopak':
      return TextStyle(
        fontFamily: 'IndoPak',
        fontSize: size,
        color: color,
        height: context.read<DisplayProvider>().lineHeight,
        wordSpacing: context.read<DisplayProvider>().wordSpacing,
      );
    case 'noorehuda':
      return TextStyle(
        fontFamily: 'NoorehudaFont',
        fontSize: size,
        color: color,
        height: 2.0,
      );
    case 'uthmani':
    default:
      return GoogleFonts.amiriQuran(fontSize: size).copyWith(color: color);
  }
}
