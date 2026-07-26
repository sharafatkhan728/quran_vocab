import '../database/database_manager.dart';
import 'package:sqflite/sqflite.dart';

class VocabWordRow {
  final int id;
  final String arabicClean;
  final String arabicDisplay;
  final int frequency;
  final String meaningUr;
  final String meaningEn;
  final String meaningHi;
  final int firstSurahId;
  final int firstAyahNumber;
  final int firstWordPosition;
  final String root;
  final String lemma;
  final String pos;

  const VocabWordRow({
    required this.id,
    required this.arabicClean,
    required this.arabicDisplay,
    required this.frequency,
    required this.meaningUr,
    required this.meaningEn,
    required this.meaningHi,
    required this.firstSurahId,
    required this.firstAyahNumber,
    required this.firstWordPosition,
    required this.root,
    required this.lemma,
    required this.pos,
  });

  factory VocabWordRow.fromMap(Map<String, dynamic> m) => VocabWordRow(
        id: m['id'] as int,
        arabicClean: m['arabic_clean'] as String,
        arabicDisplay: m['arabic_display'] as String,
        frequency: m['frequency'] as int? ?? 0,
        meaningUr: m['meaning_ur'] as String? ?? '',
        meaningEn: m['meaning_en'] as String? ?? '',
        meaningHi: m['meaning_hi'] as String? ?? '',
        firstSurahId: m['first_surah_id'] as int? ?? 0,
        firstAyahNumber: m['first_ayah_number'] as int? ?? 0,
        firstWordPosition: m['first_word_position'] as int? ?? 0,
        root: m['root'] as String? ?? '',
        lemma: m['lemma'] as String? ?? '',
        pos: m['pos'] as String? ?? '',
      );
}

class VocabularyRepository {
  /// All vocab words sorted by frequency descending.
  /// Used by flashcard session builder and vocabulary screen.
  static Future<List<VocabWordRow>> getAllWordsByFrequency() async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT
        v.id, v.arabic_clean, v.arabic_display, v.frequency,
        v.meaning_ur, v.meaning_en, v.meaning_hi,
        v.first_surah_id, v.first_ayah_number, v.first_word_position,
        v.lemma,
        COALESCE(r.arabic, '') AS root,
        COALESCE(p.code, '')   AS pos
      FROM vocab_words v
      LEFT JOIN roots r ON r.id = v.root_id
      LEFT JOIN parts_of_speech p ON p.id = v.pos_id
      ORDER BY v.frequency DESC
    ''');
    return rows.map(VocabWordRow.fromMap).toList();
  }

  /// Look up a single vocab word by its normalized Arabic form.
  static Future<VocabWordRow?> getByArabicClean(String clean) async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT
        v.id, v.arabic_clean, v.arabic_display, v.frequency,
        v.meaning_ur, v.meaning_en, v.meaning_hi,
        v.first_surah_id, v.first_ayah_number, v.first_word_position,
        v.lemma,
        COALESCE(r.arabic, '') AS root,
        COALESCE(p.code, '')   AS pos
      FROM vocab_words v
      LEFT JOIN roots r ON r.id = v.root_id
      LEFT JOIN parts_of_speech p ON p.id = v.pos_id
      WHERE v.arabic_clean = ?
      LIMIT 1
    ''', [clean]);
    if (rows.isEmpty) return null;
    return VocabWordRow.fromMap(rows.first);
  }

  /// Look up by integer id.
  static Future<VocabWordRow?> getById(int id) async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT
        v.id, v.arabic_clean, v.arabic_display, v.frequency,
        v.meaning_ur, v.meaning_en, v.meaning_hi,
        v.first_surah_id, v.first_ayah_number, v.first_word_position,
        v.lemma,
        COALESCE(r.arabic, '') AS root,
        COALESCE(p.code, '')   AS pos
      FROM vocab_words v
      LEFT JOIN roots r ON r.id = v.root_id
      LEFT JOIN parts_of_speech p ON p.id = v.pos_id
      WHERE v.id = ?
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    return VocabWordRow.fromMap(rows.first);
  }

  /// Get the Arabic text of a specific ayah for sample display.
  static Future<String> getAyahArabic(int surahId, int ayahNumber) async {
    final db = await DatabaseManager.db;
    final rows = await db.query(
      'ayahs',
      columns: ['arabic_text'],
      where: 'surah_id = ? AND ayah_number = ?',
      whereArgs: [surahId, ayahNumber],
      limit: 1,
    );
    if (rows.isEmpty) return '';
    return rows.first['arabic_text'] as String;
  }

  /// Known words
  static Future<Set<String>> getAllKnownWordCleans() async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT v.arabic_clean
      FROM known_words k
      JOIN vocab_words v ON v.id = k.vocab_word_id
    ''');
    return rows.map((r) => r['arabic_clean'] as String).toSet();
  }

  static Future<void> markKnown(int vocabWordId) async {
    final db = await DatabaseManager.db;
    await db.insert('known_words', {
      'vocab_word_id': vocabWordId,
      'marked_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> markUnknown(int vocabWordId) async {
    final db = await DatabaseManager.db;
    await db.delete('known_words',
        where: 'vocab_word_id = ?', whereArgs: [vocabWordId]);
  }
}