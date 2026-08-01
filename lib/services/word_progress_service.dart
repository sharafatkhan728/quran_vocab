import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/vocabulary_repository.dart';
import '../repositories/srs_repository.dart';
import '../database/database_manager.dart';

class WordProgressService {
  static String normalizeArabic(String text) =>
      text.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '').trim();

  // ── Known word actions ────────────────────────────────────────────────────

  static Future<void> markAsKnown(String arabicText) async {
    final clean = normalizeArabic(arabicText);
    final db = await DatabaseManager.db;
    // Look up id directly — avoids full VocabularyRepository overhead
    final rows = await db.query('vocab_words',
        columns: ['id'],
        where: 'arabic_clean = ?',
        whereArgs: [clean],
        limit: 1);
    if (rows.isEmpty) return;
    final id = rows.first['id'] as int;
    await VocabularyRepository.markKnown(id);
    _scheduleDailyUpdate();
  }

  static Future<void> markAsUnknown(String arabicText) async {
    final clean = normalizeArabic(arabicText);
    final db = await DatabaseManager.db;
    final rows = await db.query('vocab_words',
        columns: ['id'],
        where: 'arabic_clean = ?',
        whereArgs: [clean],
        limit: 1);
    if (rows.isEmpty) return;
    final id = rows.first['id'] as int;
    await VocabularyRepository.markUnknown(id);
  }

  static Future<bool> toggleWord(String arabicText) async {
    final clean = normalizeArabic(arabicText);
    final db = await DatabaseManager.db;
    final rows = await db.query('vocab_words',
        columns: ['id'],
        where: 'arabic_clean = ?',
        whereArgs: [clean],
        limit: 1);
    if (rows.isEmpty) return false;
    final id = rows.first['id'] as int;
    final known = await db.query('known_words',
        where: 'vocab_word_id = ?', whereArgs: [id], limit: 1);
    if (known.isNotEmpty) {
      await VocabularyRepository.markUnknown(id);
      return false;
    } else {
      await VocabularyRepository.markKnown(id);
      _scheduleDailyUpdate();
      return true;
    }
  }

  static Future<bool> isKnown(String arabicText) async {
    final clean = normalizeArabic(arabicText);
    final db = await DatabaseManager.db;
    final rows = await db.query('vocab_words',
        columns: ['id'],
        where: 'arabic_clean = ?',
        whereArgs: [clean],
        limit: 1);
    if (rows.isEmpty) return false;
    final id = rows.first['id'] as int;
    final known = await db.query('known_words',
        where: 'vocab_word_id = ?', whereArgs: [id], limit: 1);
    return known.isNotEmpty;
  }

  static Future<Set<String>> getAllKnownWords() =>
      VocabularyRepository.getAllKnownWordCleans();

  static Future<double> getProgressPercent() async {
    final known = await getAllKnownWords();
    final total = await getTotalVocabCount();
    if (total == 0) return 0;
    return (known.length / total) * 100;
  }

  static Future<int> getTotalVocabCount() async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM vocab_words WHERE frequency > 0');
    return (rows.first['cnt'] as int?) ?? 0;
  }

  static int get totalUniqueWords => 15072;

  /// Returns frequency map from SQLite vocab_words table.
  static Future<Map<String, WordData>> getWordFrequencies() async {
    final rows = await VocabularyRepository.getAllWordsByFrequency();
    return {
      for (final r in rows)
        r.arabicClean: WordData(
          urdu: r.meaningUr,
          frequency: r.frequency,
          originalArabic: r.arabicDisplay,
        )
    };
  }

  // ── Surah progress — two queries total (not 228) ──────────────────────────
  static Future<Map<int, double>> getAllSurahProgress() async {
    final db = await DatabaseManager.db;

    // Query 1: total unique vocab words per surah
    final totalRows = await db.rawQuery('''
      SELECT a.surah_id, COUNT(DISTINCT aw.vocab_word_id) AS cnt
      FROM ayah_words aw
      JOIN ayahs a ON a.id = aw.ayah_id
      WHERE aw.is_waqf = 0 AND aw.vocab_word_id IS NOT NULL
      GROUP BY a.surah_id
    ''');
    final totals = <int, int>{
      for (final r in totalRows) r['surah_id'] as int: (r['cnt'] as int? ?? 0)
    };

    // Query 2: known unique vocab words per surah
    final knownRows = await db.rawQuery('''
      SELECT a.surah_id, COUNT(DISTINCT aw.vocab_word_id) AS cnt
      FROM ayah_words aw
      JOIN ayahs a ON a.id = aw.ayah_id
      JOIN known_words kw ON kw.vocab_word_id = aw.vocab_word_id
      WHERE aw.is_waqf = 0
      GROUP BY a.surah_id
    ''');
    final knowns = <int, int>{
      for (final r in knownRows) r['surah_id'] as int: (r['cnt'] as int? ?? 0)
    };

    // Build result map for all 114 surahs
    final result = <int, double>{};
    for (int i = 1; i <= 114; i++) {
      final total = totals[i] ?? 0;
      if (total == 0) {
        result[i] = 0;
      } else {
        result[i] = ((knowns[i] ?? 0) / total * 100).clamp(0, 100);
      }
    }
    return result;
  }

  static void recalculateAllSurahProgress() {
    // No-op — progress calculated on demand from SQLite
  }

  // ── Legacy no-ops kept for compile compatibility ──────────────────────────
  static Future<void> saveSurahWordList(
      int surahId, Set<String> normalizedWords) async {}
  static Future<void> saveSurahWordCounts(
      int surahId, Map<String, int> wordCounts) async {}
  static Future<void> saveWordUrdu(String normalized, String urdu) async {}
  static Future<void> saveWordOriginal(
      String normalized, String original) async {}
  static Future<void> markSurahWordsLoaded(
      int surahId, Set<String> arabicWords) async {}

  // ── Daily stat helper ─────────────────────────────────────────────────────
  static Timer? _dailyTimer;
  static void _scheduleDailyUpdate() {
    _dailyTimer?.cancel();
    _dailyTimer = Timer(const Duration(milliseconds: 500), () async {
      await SrsRepository.recordWordLearned();
    });
  }

  // ── Kept for migration_manager compatibility ──────────────────────────────
  static Future<SharedPreferences?> getPrefsInstance() async =>
      SharedPreferences.getInstance();
}

class WordData {
  final String urdu;
  final int frequency;
  final String originalArabic;
  WordData({
    required this.urdu,
    required this.frequency,
    this.originalArabic = '',
  });
}
