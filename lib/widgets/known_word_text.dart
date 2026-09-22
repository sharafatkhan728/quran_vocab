import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/learning_state_provider.dart';

/// Wraps a single Arabic word's Text so it only rebuilds when THIS word's
/// known/unknown status changes — not on every known-word toggle anywhere
/// in the app. Replaces the old pattern of calling
/// context.read<LearningStateProvider>().isKnown(...) inside a big parent
/// build() that gets fully rebuilt via _refreshAllKnownFlags()/setState().
class KnownAwareText extends StatelessWidget {
  final String normalizedArabic;
  final TextStyle Function(bool isKnown) styleBuilder;
  final String text;
  final TextDirection textDirection;

  const KnownAwareText({
    super.key,
    required this.normalizedArabic,
    required this.text,
    required this.styleBuilder,
    this.textDirection = TextDirection.rtl,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<LearningStateProvider, bool>(
      selector: (_, provider) => provider.isKnown(normalizedArabic),
      builder: (_, isKnown, __) => Text(
        text,
        textDirection: textDirection,
        style: styleBuilder(isKnown),
      ),
    );
  }
}