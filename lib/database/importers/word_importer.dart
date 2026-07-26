import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:quran/quran.dart' as quran;
import 'package:sqflite/sqflite.dart';
import '../../services/word_progress_service.dart';

class WordImporter {
  final Database db;
  Map<String, String> _urduGlossary = {};
  Map<String, String> _englishGlossary = {};
  Map<String, String> _englishRaw = {};
  Map<String, String> _hindiGlossary = {};

  WordImporter(this.db);

  Future<void> run(void Function(int done, int total) onProgress) async {
    await _loadGlossaries();
    await _buildAndInsertVocab(onProgress);
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

  Future<void> _buildAndInsertVocab(
      void Function(int done, int total) onProgress) async {
    // Pass 1 — collect all unique normalized words across whole Quran
    // Map: arabicClean → VocabData
    final vocabMap = <String, _VocabData>{};

    for (int s = 1; s <= 114; s++) {
      final verseCount = quran.getVerseCount(s);
      for (int a = 1; a <= verseCount; a++) {
        String verse = quran.getVerse(s, a);
        if (a == 1 && s != 1 && s != 9) {
          final parts = verse.split(' ');
          if (parts.length > 4) verse = parts.skip(4).join(' ');
        }
        final words =
            verse.split(' ').where((w) => w.trim().isNotEmpty).toList();
        for (int pos = 1; pos <= words.length; pos++) {
          final arabic = words[pos - 1];
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
      }
      onProgress(s, 228); // 114 surahs × 2 passes
    }

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

    // Pass 3 — insert ayah_words + word_translations
    for (int s = 1; s <= 114; s++) {
      final verseCount = quran.getVerseCount(s);

      // Get all ayah IDs for this surah in one query
      final ayahRows = await db.rawQuery(
          'SELECT id, ayah_number FROM ayahs WHERE surah_id = ? ORDER BY ayah_number',
          [s]);
      final ayahIdMap = <int, int>{
        for (final r in ayahRows)
          r['ayah_number'] as int: r['id'] as int
      };

      var wBatch = db.batch();
      var tBatch = db.batch();
      int wCount = 0;

      for (int a = 1; a <= verseCount; a++) {
        final ayahId = ayahIdMap[a];
        if (ayahId == null) continue;

        String verse = quran.getVerse(s, a);
        if (a == 1 && s != 1 && s != 9) {
          final parts = verse.split(' ');
          if (parts.length > 4) verse = parts.skip(4).join(' ');
        }

        final words =
            verse.split(' ').where((w) => w.trim().isNotEmpty).toList();
        for (int pos = 1; pos <= words.length; pos++) {
          final arabic = words[pos - 1];
          final clean = WordProgressService.normalizeArabic(arabic);

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
      }
      await wBatch.commit(noResult: true);
      await tBatch.commit(noResult: true);
      onProgress(114 + s, 228);
    }

    // Pass 4 — update frequencies
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