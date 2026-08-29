// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:sqflite/sqflite.dart';
import '../../services/word_progress_service.dart';
import '../asset_parser.dart';

/// WordImporter — builds vocab_words, ayah_words, word_translations.
///
/// Vocab identity: (arabic_clean, lemma) composite key.
/// This correctly separates Arabic homographs that share the same surface
/// form but have different lemmas and roots (e.g. قل from قول vs قلل).
/// When lemma is unknown/empty, falls back to arabic_clean alone.
///
/// Two-phase design:
///   Phase 1: (done before this object is created — see AssetParser)
///     JSON + morphology parsed on a background isolate via compute().
///   Phase 2: runWithTxn() — writes to DB inside caller's transaction.
class WordImporter {
  final DatabaseExecutor db;

  /// Pre-parsed glossary maps (populated by AssetParser on isolate).
  final Map<String, String> urduGlossary;
  final Map<String, String> englishGlossary;
  final Map<String, String> englishRaw;
  final Map<String, String> hindiGlossary;

  // "surah:ayah:wordPos" → combined Arabic text
  final Map<String, String> morphWordText;
  // "surah:ayah:wordPos" → best lemma from stem segments
  final Map<String, String> morphLemma;

  final List<String> _morphologyLines;
  List<String> get morphologyLines => _morphologyLines;

  /// Construct from pre-parsed assets.
  ///
  /// [parsed] must have been produced by [AssetParser.parseMorphology].
  WordImporter.fromParsed(this.db, ParsedAssets parsed)
      : urduGlossary = parsed.urduGlossary,
        englishGlossary = parsed.englishGlossary,
        englishRaw = parsed.englishRaw,
        hindiGlossary = parsed.hindiGlossary,
        morphWordText = parsed.morphWordText,
        morphLemma = parsed.morphLemma,
        _morphologyLines = parsed.morphologyLines;

  // ── Phase 2 ───────────────────────────────────────────────────────────────

  Future<void> run(void Function(int, int) onProgress) =>
      runWithTxn(db, onProgress);

  Future<void> runWithTxn(
    DatabaseExecutor txn,
    void Function(int, int) onProgress,
  ) async {
    // ── Pass 1: collect unique vocab words by (arabic_clean, lemma) ─────────
    // Key: "$arabic_clean\x00$lemma" (null-byte separator, safe for Arabic)
    final vocabMap = <String, _VocabData>{};

    for (final e in morphWordText.entries) {
      final parts = e.key.split(':');
      if (parts.length < 3) continue;
      final s   = int.tryParse(parts[0]) ?? 0;
      final a   = int.tryParse(parts[1]) ?? 0;
      final pos = int.tryParse(parts[2]) ?? 0;

      final arabic = e.value;
      final clean  = WordProgressService.normalizeArabic(arabic);
      if (clean.isEmpty) continue;

      // Use lemma as secondary identity to separate homographs.
      // Normalize the lemma the same way so diacritics don't create spurious splits.
      final rawLemma  = morphLemma[e.key] ?? '';
      final normLemma = WordProgressService.normalizeArabic(rawLemma);
      // Composite identity: clean form + lemma (empty lemma = no disambiguation)
      final vocabKey = '$clean\x00$normLemma';

      final glKey = '$s:$a:$pos';
      final urdu  = urduGlossary[glKey]    ?? '';
      final en    = englishGlossary[glKey] ?? '';
      final hi    = hindiGlossary[glKey]   ?? '';
      final enRaw = englishRaw[glKey]      ?? '';

      final existing = vocabMap[vocabKey];
      if (existing != null) {
        // Merge meanings — keep the longest non-empty value per field
        if (urdu.isNotEmpty && urdu.length > existing.urdu.length) existing.urdu = urdu;
        if (en.isNotEmpty && en.length > existing.en.length) existing.en = en;
        if (hi.isNotEmpty && hi.length > existing.hi.length) existing.hi = hi;
        if (enRaw.isNotEmpty && enRaw.length > existing.enRaw.length) existing.enRaw = enRaw;
        // Pick the smallest frequency (first appearance wins)
        if (s < existing.firstSurah) existing.firstSurah = s;
      } else {
        vocabMap[vocabKey] = _VocabData(
          arabicClean: clean,
          arabicDisplay: arabic,
          urdu: urdu,
          en: en,
          hi: hi,
          enRaw: enRaw,
          lemma: normLemma,
          firstSurah: s,
        );
      }
    }

    // ── Pass 2: insert vocab_words ──────────────────────────────────────────
    final vocabRows = vocabMap.values.toList();
    final batchSize = 500;
    var batch = txn.batch();
    int count = 0;
    for (final v in vocabRows) {
      batch.insert('vocab_words', {
        'arabic_clean': v.arabicClean,
        'arabic_display': v.arabicDisplay,
        'lemma': v.lemma,
        'meaning_ur': v.urdu,
        'meaning_en': v.en,
        'meaning_hi': v.hi,
        'meaning_en_raw': v.enRaw,
        'first_surah_id': v.firstSurah,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
      if (count % batchSize == 0) {
        await batch.commit(noResult: true);
        batch = txn.batch();
      }
    }
    await batch.commit(noResult: true);

    // ── Pass 3: build clean→id lookup ───────────────────────────────────────
    final cleanToId = <String, int>{};
    final allVocab = await txn.rawQuery(
        'SELECT id, arabic_clean FROM vocab_words');
    for (final r in allVocab) {
      cleanToId[r['arabic_clean'] as String] = r['id'] as int;
    }

    // ── Pass 4: ayah_words + word_translations ──────────────────────────────
    final ayahRows =
        await txn.rawQuery('SELECT id, surah_id, ayah_number FROM ayahs');
    final surahAyahMap = <int, Map<int, int>>{};
    for (final r in ayahRows) {
      surahAyahMap
          .putIfAbsent(r['surah_id'] as int, () => {})
          [r['ayah_number'] as int] = r['id'] as int;
    }

    // Group morphology keys by surah
    final bySurah = <int, List<String>>{};
    for (final key in morphWordText.keys) {
      final p = key.split(':');
      if (p.length < 3) continue;
      final s = int.tryParse(p[0]);
      if (s != null) bySurah.putIfAbsent(s, () => []).add(key);
    }

    // ── Pass 5: ayah_words + word_translations ──────────────────────────────
    final waqfRe = RegExp(
        r'^[ۖ-ۜ۟-۪ۤۧۨ-ۭ\s]+$');

    int surahDone = 0;
    for (int s = 1; s <= 114; s++) {
      final keys     = bySurah[s] ?? [];
      final ayahMap  = surahAyahMap[s] ?? {};
      var   wBatch   = txn.batch();
      var   tBatch   = txn.batch();
      int   wCount   = 0;

      // Pre-pass: merge Waqf signs into preceding word display text
      final sortedKeys = List<String>.from(keys)
        ..sort((a, b) {
          final ap = a.split(':');
          final bp = b.split(':');
          final aA = int.tryParse(ap[1]) ?? 0;
          final bA = int.tryParse(bp[1]) ?? 0;
          if (aA != bA) return aA.compareTo(bA);
          return (int.tryParse(ap[2]) ?? 0)
              .compareTo(int.tryParse(bp[2]) ?? 0);
        });

      final displayText = <String, String>{};
      for (int i = 0; i < sortedKeys.length; i++) {
        final wk     = sortedKeys[i];
        final arabic = morphWordText[wk]!;
        if (waqfRe.hasMatch(arabic.trim()) && i > 0) {
          final prev = sortedKeys[i - 1];
          displayText[prev] =
              (displayText[prev] ?? morphWordText[prev]!) + arabic;
        } else {
          displayText[wk] = arabic;
        }
      }

      for (final key in sortedKeys) {
        final parts = key.split(':');
        if (parts.length < 3) continue;
        final a   = int.tryParse(parts[1]) ?? 0;
        final pos = int.tryParse(parts[2]) ?? 0;
        final ayahId = ayahMap[a];
        if (ayahId == null) continue;

        final arabic = morphWordText[key]!;
        final clean  = WordProgressService.normalizeArabic(arabic);
        if (clean.isEmpty) continue;

        final vocabWordId = cleanToId[clean];
        if (vocabWordId == null) continue;

        final display = displayText[key] ?? arabic;
        wBatch.insert('ayah_words', {
          'ayah_id': ayahId,
          'position': pos,
          'arabic_text': display,
          'arabic_clean': clean,
          'vocab_word_id': vocabWordId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        wCount++;

        // Word translations
        final glKey = key;
        final trans = <String, String>{
          'ur': urduGlossary[glKey] ?? '',
          'en': englishGlossary[glKey] ?? '',
          'hi': hindiGlossary[glKey] ?? '',
        };
        for (final entry in trans.entries) {
          if (entry.value.isNotEmpty) {
            tBatch.insert('word_translations', {
              'word_id': vocabWordId,
              'language': entry.key,
              'text': entry.value,
              'text_raw': entry.key == 'en'
                  ? (englishRaw[glKey] ?? '')
                  : '',
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }

      if (wCount > 0) {
        await wBatch.commit(noResult: true);
        await tBatch.commit(noResult: true);
      }

      surahDone++;
      if (surahDone % 10 == 0) {
        onProgress(surahDone, 114);
      }
    }
    onProgress(114, 114);
  }
}

class _VocabData {
  String arabicClean;
  String arabicDisplay;
  String urdu;
  String en;
  String hi;
  String enRaw;
  final String lemma;
  int firstSurah;

  _VocabData({
    required this.arabicClean,
    required this.arabicDisplay,
    required this.urdu,
    required this.en,
    required this.hi,
    required this.enRaw,
    required this.lemma,
    required this.firstSurah,
  });
}
