import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../../services/word_progress_service.dart';

/// WordImporter — builds ayah_words and word_translations from the
/// morphology file's word positions, NOT from quran.getVerse().split().
///
/// The morphology file is the single source of truth for word positions.
/// The glossary JSONs use the same surah:ayah:wordPos keys.
/// quran.getVerse().split(' ') gives a DIFFERENT split for some ayahs
/// (e.g. 2:21 splits into 12 tokens but morphology has 11 positions),
/// which causes Arabic ↔ Urdu misalignment in the reader.
class WordImporter {
  final Database db;
  Map<String, String> _urduGlossary = {};
  Map<String, String> _englishGlossary = {};
  Map<String, String> _englishRaw = {};
  Map<String, String> _hindiGlossary = {};

  // Built from morphology.txt:
  // "surah:ayah:wordPos" → combined Arabic text of all segments
  final Map<String, String> _morphWordText = {};

  // "surah:ayah" → max word position (how many words in that ayah)
  final Map<String, int> _ayahWordCount = {};

  WordImporter(this.db);

  Future<void> run(void Function(int done, int total) onProgress) async {
    await _loadGlossaries();
    await _parseMorphologyPositions();
    await _buildAndInsertVocab(onProgress);
  }

  // ── Glossary loading ──────────────────────────────────────────────────────

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

  // ── Parse morphology.txt to extract word-level positions ─────────────────
  //
  // The morphology file has one row per SEGMENT:
  //   1:1:1:1   بِ   P   P|PREF|LEM:ب
  //   1:1:1:2   سْمِ  N   ROOT:سمو|...
  //
  // We merge all segments per word position into one combined Arabic string.
  // e.g. 2:21:1 has segments: يَٰٓ + أَيُّ + هَا → "يَٰٓأَيُّهَا"
  //
  // This is how the reader should display each "word tile" — one tile per
  // morphology word position, not one tile per quran-package token.

  Future<void> _parseMorphologyPositions() async {
    final raw =
        await rootBundle.loadString('assets/data/quran_morphology.txt');
    final lines = raw.split('\n');

    // Accumulate segments per word position
    // key: "surah:ayah:wordPos"  value: list of segment Arabic texts in order
    final segmentsByWord = <String, List<String>>{};

    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final cols = t.split('\t');
      if (cols.length < 2) continue;

      final loc =
          cols[0].replaceAll('(', '').replaceAll(')', '').trim();
      final arabicText = cols[1].trim();
      final parts = loc.split(':');
      if (parts.length < 4) continue;

      final surahId = parts[0];
      final ayahNum = parts[1];
      final wordPos = parts[2];
      // segNum = parts[3] — not needed here

      final wordKey = '$surahId:$ayahNum:$wordPos';
      segmentsByWord.putIfAbsent(wordKey, () => []).add(arabicText);

      // Track max word position per ayah
      final ayahKey = '$surahId:$ayahNum';
      final pos = int.tryParse(wordPos) ?? 0;
      if ((_ayahWordCount[ayahKey] ?? 0) < pos) {
        _ayahWordCount[ayahKey] = pos;
      }
    }

    // Merge segments into combined word text
    for (final entry in segmentsByWord.entries) {
      _morphWordText[entry.key] = entry.value.join('');
    }
  }

  // ── Build vocab_words + ayah_words + word_translations ───────────────────

  Future<void> _buildAndInsertVocab(
      void Function(int done, int total) onProgress) async {

    // Pass 1 — collect unique vocab words using morphology positions
    final vocabMap = <String, _VocabData>{};

    // Iterate over all morphology word positions (not quran.getVerse())
    for (final entry in _morphWordText.entries) {
      final parts = entry.key.split(':');
      if (parts.length < 3) continue;
      final s = int.tryParse(parts[0]) ?? 0;
      final a = int.tryParse(parts[1]) ?? 0;
      final pos = int.tryParse(parts[2]) ?? 0;

      final arabic = entry.value; // combined segments
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

    // Pass 2 — insert vocab_words in bulk
    const batchSize = 500;
    var batch = db.batch();
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
        batch = db.batch();
      }
    }
    await batch.commit(noResult: true);

    // Build in-memory cache: arabicClean → vocab_word_id
    final vocabRows =
        await db.query('vocab_words', columns: ['id', 'arabic_clean']);
    final vocabCache = <String, int>{
      for (final r in vocabRows)
        r['arabic_clean'] as String: r['id'] as int
    };

    // Build ayah id lookup: surahId → {ayahNumber → ayahId}
    final surahAyahMap = <int, Map<int, int>>{};
    final ayahRows = await db.rawQuery(
        'SELECT id, surah_id, ayah_number FROM ayahs ORDER BY surah_id, ayah_number');
    for (final r in ayahRows) {
      final sid = r['surah_id'] as int;
      final anum = r['ayah_number'] as int;
      final aid = r['id'] as int;
      surahAyahMap.putIfAbsent(sid, () => {})[anum] = aid;
    }

    // Pass 3 — insert ayah_words + word_translations using morphology positions
    // Group _morphWordText by surah for progress reporting
    int surahDone = 0;
    const totalSurahs = 114;

    // Group keys by surah
    final bySurah = <int, List<String>>{};
    for (final key in _morphWordText.keys) {
      final parts = key.split(':');
      if (parts.length < 3) continue;
      final s = int.tryParse(parts[0]);
      if (s == null) continue;
      bySurah.putIfAbsent(s, () => []).add(key);
    }

    for (int s = 1; s <= totalSurahs; s++) {
      final keys = bySurah[s] ?? [];
      final ayahMap = surahAyahMap[s] ?? {};

      var wBatch = db.batch();
      var tBatch = db.batch();
      int wCount = 0;

      for (final wordKey in keys) {
        final parts = wordKey.split(':');
        final a = int.tryParse(parts[1]) ?? 0;
        final pos = int.tryParse(parts[2]) ?? 0;
        final ayahId = ayahMap[a];
        if (ayahId == null) continue;

        final arabic = _morphWordText[wordKey]!;
        final clean = WordProgressService.normalizeArabic(arabic);

        // A word is waqf if its clean form contains only Quranic pause marks
        final stripped = clean
            .replaceAll(
                RegExp(
                    r'[\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED]'),
                '')
            .trim();
        final isWaqf = stripped.isEmpty ? 1 : 0;
        final vocabId = isWaqf == 0 ? vocabCache[clean] : null;
        final glKey = '$s:$a:$pos';

        wBatch.rawInsert('''
          INSERT OR IGNORE INTO ayah_words
            (ayah_id, position, arabic_text, arabic_clean, is_waqf, vocab_word_id)
          VALUES (?, ?, ?, ?, ?, ?)
        ''', [ayahId, pos, arabic, clean, isWaqf, vocabId]);

        if (isWaqf == 0) {
          final urdu = _urduGlossary[glKey] ?? '';
          final en = _englishGlossary[glKey] ?? '';
          final enRaw = _englishRaw[glKey] ?? '';
          final hi = _hindiGlossary[glKey] ?? '';

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
        }

        wCount++;
        if (wCount % batchSize == 0) {
          await wBatch.commit(noResult: true);
          await tBatch.commit(noResult: true);
          wBatch = db.batch();
          tBatch = db.batch();
        }
      }

      await wBatch.commit(noResult: true);
      await tBatch.commit(noResult: true);

      surahDone++;
      onProgress(114 + surahDone, 228);
    }

    // Pass 4 — update frequencies from ayah_words count
    await db.execute('''
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