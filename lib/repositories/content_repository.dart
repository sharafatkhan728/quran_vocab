import '../database/database_manager.dart';
import 'package:sqflite/sqflite.dart';
import '../services/sync_service.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class AyahRow {
  final int id;
  final int surahId;
  final int ayahNumber;
  final String arabicText;
  final int juzNumber;
  final int rukuNumber;
  final int isBismillah;

  const AyahRow({
    required this.id,
    required this.surahId,
    required this.ayahNumber,
    required this.arabicText,
    required this.juzNumber,
    required this.rukuNumber,
    required this.isBismillah,
  });

  factory AyahRow.fromMap(Map<String, dynamic> m) => AyahRow(
        id: m['id'] as int,
        surahId: m['surah_id'] as int,
        ayahNumber: m['ayah_number'] as int,
        arabicText: m['arabic_text'] as String,
        juzNumber: m['juz_number'] as int,
        rukuNumber: m['ruku_number'] as int? ?? 0,
        isBismillah: m['is_bismillah'] as int? ?? 0,
      );
}

class AyahWordRow {
  final int id;
  final int ayahId;
  final int position;
  final String arabicText;
  final String arabicClean;
  final int isWaqf;
  final int? vocabWordId;

  const AyahWordRow({
    required this.id,
    required this.ayahId,
    required this.position,
    required this.arabicText,
    required this.arabicClean,
    required this.isWaqf,
    required this.vocabWordId,
  });

  factory AyahWordRow.fromMap(Map<String, dynamic> m) => AyahWordRow(
        id: m['id'] as int,
        ayahId: m['ayah_id'] as int,
        position: m['position'] as int,
        arabicText: m['arabic_text'] as String,
        arabicClean: m['arabic_clean'] as String,
        isWaqf: m['is_waqf'] as int? ?? 0,
        vocabWordId: m['vocab_word_id'] as int?,
      );
}

class WordTranslationRow {
  final int wordId;
  final String language;
  final String text;
  final String textRaw;

  const WordTranslationRow({
    required this.wordId,
    required this.language,
    required this.text,
    required this.textRaw,
  });

  factory WordTranslationRow.fromMap(Map<String, dynamic> m) =>
      WordTranslationRow(
        wordId: m['word_id'] as int,
        language: m['language'] as String,
        text: m['text'] as String,
        textRaw: m['text_raw'] as String? ?? '',
      );
}

class MorphSegmentRow {
  final int id;
  final int wordId;
  final int segmentNumber;
  final String segmentType;
  final String arabicText;
  final String posCode;
  final String posColorHex;
  final String root;
  final String lemma;
  final String tense;
  final String person;
  final String gender;
  final String number;
  final String grammaticalCase;
  final String voice;
  final String state;
  final String verbForm;
  final String rawTag;

  const MorphSegmentRow({
    required this.id,
    required this.wordId,
    required this.segmentNumber,
    required this.segmentType,
    required this.arabicText,
    required this.posCode,
    required this.posColorHex,
    required this.root,
    required this.lemma,
    required this.tense,
    required this.person,
    required this.gender,
    required this.number,
    required this.grammaticalCase,
    required this.voice,
    required this.state,
    required this.verbForm,
    required this.rawTag,
  });

  factory MorphSegmentRow.fromMap(Map<String, dynamic> m) => MorphSegmentRow(
        id: m['id'] as int,
        wordId: m['word_id'] as int,
        segmentNumber: m['segment_number'] as int,
        segmentType: m['segment_type'] as String,
        arabicText: m['arabic_text'] as String,
        posCode: m['pos_code'] as String? ?? '',
        posColorHex: m['pos_color_hex'] as String? ?? '#888888',
        root: m['root'] as String? ?? '',
        lemma: m['lemma'] as String? ?? '',
        tense: m['tense'] as String? ?? '',
        person: m['person'] as String? ?? '',
        gender: m['gender'] as String? ?? '',
        number: m['number'] as String? ?? '',
        grammaticalCase: m['grammatical_case'] as String? ?? '',
        voice: m['voice'] as String? ?? '',
        state: m['state'] as String? ?? '',
        verbForm: m['verb_form'] as String? ?? '',
        rawTag: m['raw_tag'] as String,
      );
}

// ── Repository ────────────────────────────────────────────────────────────────

class ContentRepository {
  /// All ayahs for a surah ordered by ayah_number.
  static Future<List<AyahRow>> getAyahsForSurah(int surahId) async {
    final db = await DatabaseManager.db;
    final rows = await db.query(
      'ayahs',
      where: 'surah_id = ?',
      whereArgs: [surahId],
      orderBy: 'ayah_number ASC',
    );
    return rows.map(AyahRow.fromMap).toList();
  }

  /// Single ayah by surah+number.
  static Future<AyahRow?> getAyah(int surahId, int ayahNumber) async {
    final db = await DatabaseManager.db;
    final rows = await db.query(
      'ayahs',
      where: 'surah_id = ? AND ayah_number = ?',
      whereArgs: [surahId, ayahNumber],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AyahRow.fromMap(rows.first);
  }

  /// All words for a single ayah, ordered by position.
  static Future<List<AyahWordRow>> getWordsForAyah(int ayahId) async {
    final db = await DatabaseManager.db;
    final rows = await db.query(
      'ayah_words',
      where: 'ayah_id = ?',
      whereArgs: [ayahId],
      orderBy: 'position ASC',
    );
    return rows.map(AyahWordRow.fromMap).toList();
  }

  /// All word translations for an ayah, keyed by word_id.
  /// Returns Map<wordId, Map<language, WordTranslationRow>>.
  static Future<Map<int, Map<String, WordTranslationRow>>>
      getWordTranslationsForAyah(int ayahId, String language) async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT wt.word_id, wt.language, wt.text, wt.text_raw
      FROM word_translations wt
      JOIN ayah_words aw ON aw.id = wt.word_id
      WHERE aw.ayah_id = ? AND wt.language = ?
    ''', [ayahId, language]);

    final result = <int, Map<String, WordTranslationRow>>{};
    for (final r in rows) {
      final row = WordTranslationRow.fromMap(r);
      result.putIfAbsent(row.wordId, () => {})[row.language] = row;
    }
    return result;
  }

  /// Ayah translation text for a specific surah:ayah.
  static Future<String?> getAyahTranslation(
      int surahId, int ayahNumber, String language, String scholarKey) async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT at.text
      FROM ayah_translations at
      JOIN ayahs a ON a.id = at.ayah_id
      WHERE a.surah_id = ? AND a.ayah_number = ?
        AND at.language = ? AND at.scholar_key = ?
      LIMIT 1
    ''', [surahId, ayahNumber, language, scholarKey]);
    if (rows.isEmpty) return null;
    return rows.first['text'] as String;
  }

  /// All translations for a surah — used for pre-loading.
  /// Returns `Map<ayahNumber, translationText>`.
  static Future<Map<int, String>> getSurahTranslations(
      int surahId, String language, String scholarKey) async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT a.ayah_number, at.text
      FROM ayah_translations at
      JOIN ayahs a ON a.id = at.ayah_id
      WHERE a.surah_id = ? AND at.language = ? AND at.scholar_key = ?
      ORDER BY a.ayah_number ASC
    ''', [surahId, language, scholarKey]);
    return {for (final r in rows) r['ayah_number'] as int: r['text'] as String};
  }

  /// Morphology segments for a single ayah_word by its database id.
  static Future<List<MorphSegmentRow>> getSegmentsForWord(
      int ayahWordId) async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT
        ms.id, ms.word_id, ms.segment_number, ms.segment_type,
        ms.arabic_text, ms.lemma, ms.tense, ms.person, ms.gender,
        ms.number, ms.grammatical_case, ms.voice, ms.state,
        ms.verb_form, ms.raw_tag,
        COALESCE(p.code,      '') AS pos_code,
        COALESCE(p.color_hex, '#888888') AS pos_color_hex,
        COALESCE(r.arabic,    '') AS root
      FROM morphology_segments ms
      LEFT JOIN parts_of_speech p ON p.id = ms.pos_id
      LEFT JOIN roots r ON r.id = ms.root_id
      WHERE ms.word_id = ?
      ORDER BY ms.segment_number ASC
    ''', [ayahWordId]);
    return rows.map(MorphSegmentRow.fromMap).toList();
  }

  /// Morphology segments for ALL words in an ayah — one query instead of N.
  // / Returns Map<ayahWordId, List<MorphSegmentRow>>.
  static Future<Map<int, List<MorphSegmentRow>>> getSegmentsForAyah(
      int ayahId) async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT
        ms.id, ms.word_id, ms.segment_number, ms.segment_type,
        ms.arabic_text, ms.lemma, ms.tense, ms.person, ms.gender,
        ms.number, ms.grammatical_case, ms.voice, ms.state,
        ms.verb_form, ms.raw_tag,
        COALESCE(p.code,      '') AS pos_code,
        COALESCE(p.color_hex, '#888888') AS pos_color_hex,
        COALESCE(r.arabic,    '') AS root
      FROM morphology_segments ms
      JOIN ayah_words aw ON aw.id = ms.word_id
      LEFT JOIN parts_of_speech p ON p.id = ms.pos_id
      LEFT JOIN roots r ON r.id = ms.root_id
      WHERE aw.ayah_id = ?
      ORDER BY ms.word_id ASC, ms.segment_number ASC
    ''', [ayahId]);

    final result = <int, List<MorphSegmentRow>>{};
    for (final r in rows) {
      final seg = MorphSegmentRow.fromMap(r);
      result.putIfAbsent(seg.wordId, () => []).add(seg);
    }
    return result;
  }

  /// Reading progress
  static Future<int> getLastReadAyah(int surahId) async {
    final db = await DatabaseManager.db;
    final rows = await db.query('reading_progress',
        where: 'surah_id = ?', whereArgs: [surahId], limit: 1);
    if (rows.isEmpty) return 0;
    return rows.first['last_ayah'] as int? ?? 0;
  }

  static Future<void> saveLastReadAyah(int surahId, int ayahNumber) async {
    final db = await DatabaseManager.db;
    await db.insert(
        'reading_progress',
        {
          'surah_id': surahId,
          'last_ayah': ayahNumber,
          'last_read_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
        SyncService.scheduleSyncUp();
  }

  /// Bookmarks
  static Future<Set<String>> getBookmarksForSurah(int surahId) async {
    final db = await DatabaseManager.db;
    final rows = await db
        .query('bookmarks', where: 'surah_id = ?', whereArgs: [surahId]);
    return rows.map((r) => '$surahId:${r['ayah_number']}').toSet();
  }

  static Future<void> toggleBookmark(int surahId, int ayahNumber) async {
    final db = await DatabaseManager.db;
    final existing = await db.query('bookmarks',
        where: 'surah_id = ? AND ayah_number = ?',
        whereArgs: [surahId, ayahNumber],
        limit: 1);
    if (existing.isNotEmpty) {
      await db.delete('bookmarks',
          where: 'surah_id = ? AND ayah_number = ?',
          whereArgs: [surahId, ayahNumber]);
    } else {
      await db.insert(
          'bookmarks',
          {
            'surah_id': surahId,
            'ayah_number': ayahNumber,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
          SyncService.scheduleSyncUp();
    }
  }

  static Future<List<Map<String, dynamic>>> getAllBookmarks() async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT b.surah_id, b.ayah_number, s.name_english
      FROM bookmarks b
      JOIN surahs s ON s.id = b.surah_id
      ORDER BY b.created_at DESC
    ''');
    return rows
        .map((r) => {
              'surahId': r['surah_id'] as int,
              'ayahId': r['ayah_number'] as int,
              'name': r['name_english'] as String,
            })
        .toList();
  }
}
