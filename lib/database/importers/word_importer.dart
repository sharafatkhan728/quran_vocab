import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../../services/word_progress_service.dart';

/// WordImporter — builds vocab_words, ayah_words, word_translations.
///
/// Uses morphology file positions as the source of truth for word
/// boundaries — NOT quran.getVerse().split(' ') which gives different
/// splits causing Arabic/Urdu misalignment.
///
/// Two-phase design:
///   Phase 1: loadAssets() — reads all JSON + morphology file into memory.
///             Called BEFORE the DB transaction so no DB state is changed
///             if asset loading fails.
///   Phase 2: runWithTxn() — writes everything to DB inside the caller's
///             transaction. If it throws, the transaction rolls back.
class WordImporter {
  final DatabaseExecutor db;

  Map<String, String> _urduGlossary = {};
  Map<String, String> _englishGlossary = {};
  Map<String, String> _englishRaw = {};
  Map<String, String> _hindiGlossary = {};

  // Morphology-derived word data
  // "surah:ayah:wordPos" → combined Arabic text of all segments
  final Map<String, String> _morphWordText = {};

  // Exposed so MorphologyImporter can reuse without re-reading the file
  List<String> _morphologyLines = [];
  List<String> get morphologyLines => _morphologyLines;

  WordImporter(this.db);

  // ── Phase 1: Load all assets into memory ──────────────────────────────────

  Future<void> loadAssets() async {
    await _loadGlossaries();
    await _parseMorphologyPositions();
  }

  Future<void> _loadGlossaries() async {
    _urduGlossary = await _loadJson('assets/data/urud-wbw.json');
    _englishRaw =
        await _loadJson('assets/data/colored-english-wbw-translation.json');
    _englishGlossary = _englishRaw.map(
        (k, v) => MapEntry(k, v.replaceAll(RegExp(r'<[^>]*>'), '').trim()));
    _hindiGlossary = await _loadJson('assets/data/hindi-wbw.json');
  }

  Future<Map<String, String>> _loadJson(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      final data = json.decode(raw) as Map<String, dynamic>;
      return data.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _parseMorphologyPositions() async {
    final raw = await rootBundle.loadString('assets/data/quran_morphology.txt');
    _morphologyLines = raw.split('\n');

    final segmentsByWord = <String, List<String>>{};

    for (final line in _morphologyLines) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final cols = t.split('\t');
      if (cols.length < 2) continue;

      final loc = cols[0].replaceAll('(', '').replaceAll(')', '').trim();
      final arabicText = cols[1].trim();
      final parts = loc.split(':');
      if (parts.length < 4) continue;

      final wordKey = '${parts[0]}:${parts[1]}:${parts[2]}';
      segmentsByWord.putIfAbsent(wordKey, () => []).add(arabicText);
    }

    for (final entry in segmentsByWord.entries) {
      _morphWordText[entry.key] = entry.value.join('');
    }
  }

  // ── Phase 2: Write to DB inside caller's transaction ─────────────────────

  Future<void> run(void Function(int done, int total) onProgress) async {
    await runWithTxn(db, onProgress);
  }

  Future<void> runWithTxn(
    DatabaseExecutor txn,
    void Function(int done, int total) onProgress,
  ) async {
    // Pass 1 — collect unique vocab words from morphology positions
    final vocabMap = <String, _VocabData>{};

    for (final entry in _morphWordText.entries) {
      final parts = entry.key.split(':');
      if (parts.length < 3) continue;
      final s = int.tryParse(parts[0]) ?? 0;
      final a = int.tryParse(parts[1]) ?? 0;
      final pos = int.tryParse(parts[2]) ?? 0;

      final arabic = entry.value;
      final clean = WordProgressService.normalizeArabic(arabic);
      if (clean.isEmpty) continue;

      final glKey = '$s:$a:$pos';
      final urdu = _urduGlossary[glKey] ?? '';
      final en = _englishGlossary[glKey] ?? '';
      final enRaw = _englishRaw[glKey] ?? '';
      final hi = _hindiGlossary[glKey] ?? '';

      if (!vocabMap.containsKey(clean)) {
        vocabMap[clean] = _VocabData(
          display: arabic,
          ur: urdu,
          en: en,
          enRaw: enRaw,
          hi: hi,
          firstSurah: s,
          firstAyah: a,
          firstPos: pos,
        );
      } else {
        final v = vocabMap[clean]!;
        if (v.ur.isEmpty && urdu.isNotEmpty) v.ur = urdu;
        if (v.en.isEmpty && en.isNotEmpty) v.en = en;
        if (v.hi.isEmpty && hi.isNotEmpty) v.hi = hi;
      }
    }

    onProgress(114, 228);

    // Pass 2 — insert vocab_words
    const batchSize = 500;
    var batch = txn.batch();
    int count = 0;

    for (final entry in vocabMap.entries) {
      batch.insert(
          'vocab_words',
          {
            'arabic_clean': entry.key,
            'arabic_display': entry.value.display,
            'frequency': 0,
            'first_surah_id': entry.value.firstSurah,
            'first_ayah_number': entry.value.firstAyah,
            'first_word_position': entry.value.firstPos,
            'meaning_ur': entry.value.ur,
            'meaning_en': entry.value.en,
            'meaning_hi': entry.value.hi,
            'meaning_en_raw': entry.value.enRaw,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      count++;
      if (count % batchSize == 0) {
        await batch.commit(noResult: true);
        batch = txn.batch();
      }
    }
    await batch.commit(noResult: true);

    // Build vocab cache from what we just inserted
    final vocabRows =
        await txn.query('vocab_words', columns: ['id', 'arabic_clean']);
    final vocabCache = <String, int>{
      for (final r in vocabRows) r['arabic_clean'] as String: r['id'] as int
    };

    // Build ayah id lookup
    final ayahRows = await txn.rawQuery(
        'SELECT id, surah_id, ayah_number FROM ayahs ORDER BY surah_id, ayah_number');
    final surahAyahMap = <int, Map<int, int>>{};
    for (final r in ayahRows) {
      final sid = r['surah_id'] as int;
      final anum = r['ayah_number'] as int;
      final aid = r['id'] as int;
      surahAyahMap.putIfAbsent(sid, () => {})[anum] = aid;
    }

    // Group morphology keys by surah
    final bySurah = <int, List<String>>{};
    for (final key in _morphWordText.keys) {
      final parts = key.split(':');
      if (parts.length < 3) continue;
      final s = int.tryParse(parts[0]);
      if (s == null) continue;
      bySurah.putIfAbsent(s, () => []).add(key);
    }

// Waqf sign Unicode range — these are Quranic punctuation marks
    final waqfRegex = RegExp(
        r'^[\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED\s]+$');

    // Pass 3 — insert ayah_words + word_translations
    // Waqf signs are appended to the PRECEDING word's arabic_text instead of
    // creating a separate ayah_words row. This keeps them visible in the
    // reader while not affecting word positions, translations, or SRS.
    int surahDone = 0;
    for (int s = 1; s <= 114; s++) {
      final keys = (bySurah[s] ?? [])
        ..sort((a, b) {
          // Sort by ayah then position so we can find preceding word
          final aParts = a.split(':');
          final bParts = b.split(':');
          final aAyah = int.tryParse(aParts[1]) ?? 0;
          final bAyah = int.tryParse(bParts[1]) ?? 0;
          if (aAyah != bAyah) return aAyah.compareTo(bAyah);
          final aPos = int.tryParse(aParts[2]) ?? 0;
          final bPos = int.tryParse(bParts[2]) ?? 0;
          return aPos.compareTo(bPos);
        });

      final ayahMap = surahAyahMap[s] ?? {};

      // Pre-pass: build map of wordKey → arabic_text with Waqf appended
      // "surah:ayah:pos" → display text (may include trailing Waqf)
      final displayText = <String, String>{};
      for (int i = 0; i < keys.length; i++) {
        final wordKey = keys[i];
        final arabic = _morphWordText[wordKey]!;
        WordProgressService.normalizeArabic(arabic);
        final isWaqfOnly = waqfRegex.hasMatch(arabic.trim());

        if (isWaqfOnly && i > 0) {
          // Append this Waqf sign to the previous word's display text
          final prevKey = keys[i - 1];
          displayText[prevKey] = (displayText[prevKey] ??
                  _morphWordText[prevKey]!) +
              arabic;
          // Do NOT add this key to displayText — it will not get its own row
        } else {
          displayText[wordKey] = arabic;
        }
      }

      var wBatch = txn.batch();
      var tBatch = txn.batch();
      int wCount = 0;

      for (final wordKey in keys) {
        // Skip pure Waqf-sign keys — they've been appended to previous word
        if (!displayText.containsKey(wordKey)) continue;

        final parts = wordKey.split(':');
        final a = int.tryParse(parts[1]) ?? 0;
        final pos = int.tryParse(parts[2]) ?? 0;
        final ayahId = ayahMap[a];
        if (ayahId == null) continue;

        // Use display text (which may have Waqf appended)
        final arabicDisplay = displayText[wordKey]!;
        // Clean is still the original word without Waqf for vocab lookup
        final arabicOrig = _morphWordText[wordKey]!;
        final clean = WordProgressService.normalizeArabic(arabicOrig);
        final vocabId = vocabCache[clean];
        final glKey = '$s:$a:$pos';

        wBatch.rawInsert('''
          INSERT OR IGNORE INTO ayah_words
            (ayah_id, position, arabic_text, arabic_clean, is_waqf, vocab_word_id)
          VALUES (?, ?, ?, ?, 0, ?)
        ''', [ayahId, pos, arabicDisplay, clean, vocabId]);

        final urdu  = _urduGlossary[glKey] ?? '';
        final en    = _englishGlossary[glKey] ?? '';
        final enRaw = _englishRaw[glKey] ?? '';
        final hi    = _hindiGlossary[glKey] ?? '';

        if (urdu.isNotEmpty) {
          tBatch.rawInsert(
              'INSERT OR IGNORE INTO word_translations(word_id,language,text,text_raw) '
              'SELECT id,?,?,? FROM ayah_words WHERE ayah_id=? AND position=?',
              ['ur', urdu, urdu, ayahId, pos]);
        }
        if (en.isNotEmpty) {
          tBatch.rawInsert(
              'INSERT OR IGNORE INTO word_translations(word_id,language,text,text_raw) '
              'SELECT id,?,?,? FROM ayah_words WHERE ayah_id=? AND position=?',
              ['en', en, enRaw, ayahId, pos]);
        }
        if (hi.isNotEmpty) {
          tBatch.rawInsert(
              'INSERT OR IGNORE INTO word_translations(word_id,language,text,text_raw) '
              'SELECT id,?,?,? FROM ayah_words WHERE ayah_id=? AND position=?',
              ['hi', hi, hi, ayahId, pos]);
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

    // Pass 4 — update frequencies
    await txn.rawUpdate('''
      UPDATE vocab_words
      SET frequency = (
        SELECT COUNT(*) FROM ayah_words
        WHERE ayah_words.vocab_word_id = vocab_words.id
          AND ayah_words.is_waqf = 0
      )
    ''');
  }
}

class _VocabData {
  final String display;
  String ur, en, enRaw, hi;
  final int firstSurah, firstAyah, firstPos;
  _VocabData({
    required this.display,
    required this.ur,
    required this.en,
    required this.enRaw,
    required this.hi,
    required this.firstSurah,
    required this.firstAyah,
    required this.firstPos,
  });
}