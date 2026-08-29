import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../../services/word_progress_service.dart';

/// WordImporter — builds vocab_words, ayah_words, word_translations.
///
/// Vocab identity: (arabic_clean, lemma) composite key.
/// This correctly separates Arabic homographs that share the same surface
/// form but have different lemmas and roots (e.g. قل from قول vs قلل).
/// When lemma is unknown/empty, falls back to arabic_clean alone.
///
/// Two-phase design:
///   Phase 1: loadAssets() — reads JSON + morphology into memory.
///   Phase 2: runWithTxn() — writes to DB inside caller's transaction.
class WordImporter {
  final DatabaseExecutor db;

  Map<String, String> _urduGlossary   = {};
  Map<String, String> _englishGlossary = {};
  Map<String, String> _englishRaw     = {};
  Map<String, String> _hindiGlossary  = {};

  // "surah:ayah:wordPos" → combined Arabic text
  final Map<String, String> _morphWordText = {};
  // "surah:ayah:wordPos" → best lemma from stem segments
  final Map<String, String> _morphLemma    = {};

  List<String> _morphologyLines = [];
  List<String> get morphologyLines => _morphologyLines;

  WordImporter(this.db);

  // ── Phase 1 ───────────────────────────────────────────────────────────────

  Future<void> loadAssets() async {
    await _loadGlossaries();
    await _parseMorphologyPositions();
  }

  Future<void> _loadGlossaries() async {
    _urduGlossary    = await _loadJson('assets/data/urud-wbw.json');
    _englishRaw      = await _loadJson(
        'assets/data/colored-english-wbw-translation.json');
    _englishGlossary = _englishRaw.map(
        (k, v) => MapEntry(k, v.replaceAll(RegExp(r'<[^>]*>'), '').trim()));
    _hindiGlossary   = await _loadJson('assets/data/hindi-wbw.json');
  }

  Future<Map<String, String>> _loadJson(String path) async {
    try {
      final raw  = await rootBundle.loadString(path);
      final data = json.decode(raw) as Map<String, dynamic>;
      return data.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _parseMorphologyPositions() async {
    final raw = await rootBundle.loadString('assets/data/quran_morphology.txt');
    _morphologyLines = raw.split('\n');

    // segmentsByWord: wordKey → [segment Arabic texts in order]
    // lemmaByWord:    wordKey → dominant stem lemma
    final segmentsByWord = <String, List<String>>{};
    // wordKey → Map<lemma, count> — pick most frequent lemma per position
    final lemmaCount = <String, Map<String, int>>{};

    for (final line in _morphologyLines) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final cols = t.split('\t');
      if (cols.length < 4) continue;

      final loc     = cols[0].replaceAll('(', '').replaceAll(')', '').trim();
      final arabic  = cols[1].trim();
      final tag     = cols[3].trim();
      final parts   = loc.split(':');
      if (parts.length < 4) continue;

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
    for (final e in segmentsByWord.entries) {
      _morphWordText[e.key] = e.value.join('');
    }

    // Pick dominant lemma per word position (most frequent; ties → first alpha)
    for (final e in lemmaCount.entries) {
      final sorted = e.value.entries.toList()
        ..sort((a, b) {
          final cmp = b.value.compareTo(a.value);
          return cmp != 0 ? cmp : a.key.compareTo(b.key);
        });
      _morphLemma[e.key] = sorted.first.key;
    }
  }

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

    for (final e in _morphWordText.entries) {
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
      final rawLemma  = _morphLemma[e.key] ?? '';
      final normLemma = WordProgressService.normalizeArabic(rawLemma);
      // Composite identity: clean form + lemma (empty lemma = no disambiguation)
      final vocabKey = '$clean\x00$normLemma';

      final glKey = '$s:$a:$pos';
      final urdu  = _urduGlossary[glKey]    ?? '';
      final en    = _englishGlossary[glKey] ?? '';
      final enRaw = _englishRaw[glKey]      ?? '';
      final hi    = _hindiGlossary[glKey]   ?? '';

      if (!vocabMap.containsKey(vocabKey)) {
        vocabMap[vocabKey] = _VocabData(
          display:    arabic,
          clean:      clean,
          lemma:      normLemma,
          ur: urdu, en: en, enRaw: enRaw, hi: hi,
          firstSurah: s, firstAyah: a, firstPos: pos,
        );
      } else {
        final v = vocabMap[vocabKey]!;
        if (v.ur.isEmpty   && urdu.isNotEmpty) v.ur    = urdu;
        if (v.en.isEmpty   && en.isNotEmpty)   v.en    = en;
        if (v.enRaw.isEmpty && enRaw.isNotEmpty) v.enRaw = enRaw;
        if (v.hi.isEmpty   && hi.isNotEmpty)   v.hi    = hi;
      }
    }

    onProgress(114, 228);

    // ── Pass 2: insert vocab_words ────────────────────────────────────────
    const batchSize = 500;
    var batch = txn.batch();
    int count = 0;

    for (final e in vocabMap.entries) {
      final v = e.value;
      batch.insert('vocab_words', {
        'arabic_clean':      v.clean,
        'arabic_display':    v.display,
        'lemma_key':         v.lemma,  // new column — see note below
        'frequency':         0,
        'first_surah_id':    v.firstSurah,
        'first_ayah_number': v.firstAyah,
        'first_word_position': v.firstPos,
        'meaning_ur':  v.ur,
        'meaning_en':  v.en,
        'meaning_hi':  v.hi,
        'meaning_en_raw': v.enRaw,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      count++;
      if (count % batchSize == 0) {
        await batch.commit(noResult: true);
        batch = txn.batch();
      }
    }
    await batch.commit(noResult: true);

    // ── Build caches ──────────────────────────────────────────────────────
    // vocab cache: "$clean\x00$normLemma" → id
    final vocabRows = await txn.rawQuery(
        'SELECT id, arabic_clean, COALESCE(lemma_key,"") AS lk FROM vocab_words');
    final vocabCache = <String, int>{
      for (final r in vocabRows)
        '${r['arabic_clean'] as String}\x00${r['lk'] as String}': r['id'] as int
    };
    // Also build clean-only cache for fallback (words with empty lemma)
    final vocabCleanCache = <String, int>{};
    for (final r in vocabRows) {
      final clean = r['arabic_clean'] as String;
      vocabCleanCache.putIfAbsent(clean, () => r['id'] as int);
    }

    // Ayah id lookup
    final ayahRows = await txn.rawQuery(
        'SELECT id, surah_id, ayah_number FROM ayahs '
        'ORDER BY surah_id, ayah_number');
    final surahAyahMap = <int, Map<int, int>>{};
    for (final r in ayahRows) {
      surahAyahMap
          .putIfAbsent(r['surah_id'] as int, () => {})
          [r['ayah_number'] as int] = r['id'] as int;
    }

    // Group morphology keys by surah
    final bySurah = <int, List<String>>{};
    for (final key in _morphWordText.keys) {
      final p = key.split(':');
      if (p.length < 3) continue;
      final s = int.tryParse(p[0]);
      if (s != null) bySurah.putIfAbsent(s, () => []).add(key);
    }

    // ── Pass 3: ayah_words + word_translations ────────────────────────────
    final waqfRe = RegExp(
        r'^[\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED\s]+$');

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
        final arabic = _morphWordText[wk]!;
        if (waqfRe.hasMatch(arabic.trim()) && i > 0) {
          final prev = sortedKeys[i - 1];
          displayText[prev] =
              (displayText[prev] ?? _morphWordText[prev]!) + arabic;
        } else {
          displayText[wk] = arabic;
        }
      }

      for (final wordKey in sortedKeys) {
        if (!displayText.containsKey(wordKey)) continue;

        final p      = wordKey.split(':');
        final a      = int.tryParse(p[1]) ?? 0;
        final pos    = int.tryParse(p[2]) ?? 0;
        final ayahId = ayahMap[a];
        if (ayahId == null) continue;

        final arabicDisplay = displayText[wordKey]!;
        final arabicOrig    = _morphWordText[wordKey]!;
        final clean         = WordProgressService.normalizeArabic(arabicOrig);
        final normLemma     = WordProgressService.normalizeArabic(
            _morphLemma[wordKey] ?? '');
        final vocabKey      = '$clean\x00$normLemma';

        // Look up by composite key first, then fall back to clean-only
        final vocabId = vocabCache[vocabKey] ?? vocabCleanCache[clean];
        final glKey   = '$s:$a:$pos';

        wBatch.rawInsert('''
          INSERT OR IGNORE INTO ayah_words
            (ayah_id, position, arabic_text, arabic_clean, is_waqf, vocab_word_id)
          VALUES (?, ?, ?, ?, 0, ?)
        ''', [ayahId, pos, arabicDisplay, clean, vocabId]);

        if (vocabId != null) {
          for (final lang in ['ur', 'en', 'hi']) {
            final text = lang == 'ur'
                ? _urduGlossary[glKey] ?? ''
                : lang == 'en'
                    ? _englishGlossary[glKey] ?? ''
                    : _hindiGlossary[glKey]   ?? '';
            final raw = lang == 'en' ? (_englishRaw[glKey] ?? '') : text;
            if (text.isEmpty) continue;
            tBatch.rawInsert(
                'INSERT OR IGNORE INTO word_translations'
                '(word_id,language,text,text_raw) '
                'SELECT id,?,?,? FROM ayah_words '
                'WHERE ayah_id=? AND position=?',
                [lang, text, raw, ayahId, pos]);
          }
        }

        wCount++;
        if (wCount % batchSize == 0) {
          await wBatch.commit(noResult: true);
          await tBatch.commit(noResult: true);
          wBatch = txn.batch();
          tBatch = txn.batch();
        }
      }
      await wBatch.commit(noResult: true);
      await tBatch.commit(noResult: true);
      surahDone++;
      onProgress(114 + surahDone, 228);
    }

    // ── Pass 4: frequencies via GROUP BY (no correlated subquery) ────────
    await txn.execute('''
      CREATE TEMP TABLE IF NOT EXISTS _freq_agg AS
      SELECT vocab_word_id, COUNT(*) AS cnt
      FROM ayah_words
      WHERE vocab_word_id IS NOT NULL
      GROUP BY vocab_word_id
    ''');
    await txn.rawUpdate('''
      UPDATE vocab_words
      SET frequency = (
        SELECT cnt FROM _freq_agg
        WHERE _freq_agg.vocab_word_id = vocab_words.id
      )
      WHERE id IN (SELECT vocab_word_id FROM _freq_agg)
    ''');
    await txn.execute('DROP TABLE IF EXISTS _freq_agg');
  }
}

class _VocabData {
  final String display;
  final String clean;
  final String lemma;
  String ur, en, enRaw, hi;
  final int firstSurah, firstAyah, firstPos;
  _VocabData({
    required this.display,
    required this.clean,
    required this.lemma,
    required this.ur,
    required this.en,
    required this.enRaw,
    required this.hi,
    required this.firstSurah,
    required this.firstAyah,
    required this.firstPos,
  });
}