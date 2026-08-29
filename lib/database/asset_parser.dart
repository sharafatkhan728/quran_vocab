/// Pure-Dart, isolate-safe asset parsers.
///
/// Methods here accept raw strings (already loaded from rootBundle) and
/// return parsed Dart objects. They contain no Flutter/SQFlite dependencies
/// so they can run on a background isolate via [compute].
///
/// Called from [DatabaseImporter.runImport] after the raw strings have been
/// loaded by rootBundle on the main isolate.
library;

import 'dart:convert';

/// Result of parsing all vocabulary / morphology assets.
///
/// Passed to [WordImporter] and [MorphologyImporter] so they can skip the
/// expensive re-parse that previously happened on the main thread.
class ParsedAssets {
  final Map<String, String> urduGlossary;
  final Map<String, String> englishGlossary;
  final Map<String, String> englishRaw;
  final Map<String, String> hindiGlossary;

  /// "surahId:ayahNumber:wordPos" → combined Arabic text from morphology
  final Map<String, String> morphWordText;

  /// "surahId:ayahNumber:wordPos" → dominant lemma from stem segments
  final Map<String, String> morphLemma;

  /// Raw newline-split morphology lines (already split on main thread).
  final List<String> morphologyLines;

  ParsedAssets({
    required this.urduGlossary,
    required this.englishGlossary,
    required this.englishRaw,
    required this.hindiGlossary,
    required this.morphWordText,
    required this.morphLemma,
    required this.morphologyLines,
  });
}

/// Pure-Dart, isolate-safe asset parsers.
class AssetParser {
  /// Parse a glossary JSON string (flat map: key → value).
  static Map<String, String> loadJson(String raw) {
    try {
      final data = json.decode(raw) as Map<String, dynamic>;
      return data.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  /// Parse the raw morphology text into morphWordText and morphLemma maps.
  static ParsedAssets parseMorphology(List<Object> args) {
    final raw      = args[0] as String;
    final urdu     = args[1] as Map<String, String>;
    final englishRaw = args[2] as Map<String, String>;
    final hindi    = args[3] as Map<String, String>;
    final lines = raw.split('\n');

    // segmentsByWord: wordKey → [segment Arabic texts in order]
    final segmentsByWord = <String, List<String>>{};
    // wordKey → Map<lemma, count> — pick most frequent lemma per position
    final lemmaCount = <String, Map<String, int>>{};

    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final cols = t.split('\t');
      if (cols.length < 4) continue;

      final loc = cols[0].replaceAll('(', '').replaceAll(')', '').trim();
      final arabic = cols[1].trim();
      final tag = cols[3].trim();
      final parts = loc.split(':');
      if (parts.length < 3) continue;

      final wordKey = '${parts[0]}:${parts[1]}:${parts[2]}';
      segmentsByWord.putIfAbsent(wordKey, () => []).add(arabic);

      // Extract lemma from stem segments only
      if (!tag.contains('PREF') && !tag.contains('SUFF')) {
        for (final tok in tag.split('|')) {
          if (tok.startsWith('LEM:')) {
            final lemma = tok.substring(4).trim();
            if (lemma.isNotEmpty) {
              lemmaCount
                  .putIfAbsent(wordKey, () => {})
                  .update(lemma, (c) => c + 1, ifAbsent: () => 1);
            }
            break;
          }
        }
      }
    }

    // Build combined word text
    final morphWordText = <String, String>{};
    for (final e in segmentsByWord.entries) {
      morphWordText[e.key] = e.value.join('');
    }

    // Pick dominant lemma per word position (most frequent; ties → first alpha)
    final morphLemma = <String, String>{};
    for (final e in lemmaCount.entries) {
      final sorted = e.value.entries.toList()
        ..sort((a, b) {
          final cmp = b.value.compareTo(a.value);
          return cmp != 0 ? cmp : a.key.compareTo(b.key);
        });
      morphLemma[e.key] = sorted.first.key;
    }

    return ParsedAssets(
      urduGlossary: urdu,
      englishGlossary: englishRaw.map(
          (k, v) => MapEntry(k, v.replaceAll(RegExp(r'<[^>]*>'), '').trim())),
      englishRaw: englishRaw,
      hindiGlossary: hindi,
      morphWordText: morphWordText,
      morphLemma: morphLemma,
      morphologyLines: lines,
    );
  }
}
