import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/vocabulary_repository.dart';
import '../database/database_manager.dart';
import 'word_glossary_service.dart';

class WordProgressService {
  static String normalizeArabic(String text) =>
      text.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '').trim();

  // Always-transparent attached particles — excluded from every stats query
  // below so Progress screen numbers (discovered, remaining, total, known %)
  // match what the Vocabulary screen actually lists (which already hides
  // these three, since they're never independently learnable items).
  static const _hiddenStandaloneClean = "('و', 'ف', 'ال')";
  static const _hiddenStandalone = {'و', 'ف', 'ال'};

  static Future<Set<String>> getAllKnownWords() =>
      VocabularyRepository.getAllKnownWordCleans();

  /// Overall % = sum of frequency of all known words / total word occurrences in Quran
  static Future<double> getProgressPercent() async {
    final db = await DatabaseManager.db;
    // Sum frequency of known words
    final knownFreqRows = await db.rawQuery('''
      SELECT COALESCE(SUM(v.frequency), 0) as total
      FROM known_words k
      JOIN vocab_words v ON v.id = k.vocab_word_id
      WHERE v.frequency > 0 AND v.arabic_clean NOT IN $_hiddenStandaloneClean
    ''');
    final knownOccurrences =
        (knownFreqRows.first['total'] as int?) ?? 0;

    // Total word occurrences in Quran
    final totalOccurrences = await getTotalWordOccurrences();
    if (totalOccurrences == 0) return 0;
    return (knownOccurrences / totalOccurrences) * 100;
  }

  /// Total unique vocab words (for vocabulary progress display)
  static Future<int> getTotalVocabCount() async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM vocab_words '
        'WHERE frequency > 0 AND arabic_clean NOT IN $_hiddenStandaloneClean');
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// Total word occurrences across the entire Quran
  /// = sum of frequency column across all vocab_words
  /// This equals the total number of words in Quran (~77,430)
  static Future<int> getTotalWordOccurrences() async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(frequency), 0) as total FROM vocab_words '
        'WHERE frequency > 0 AND arabic_clean NOT IN $_hiddenStandaloneClean');
    return (rows.first['total'] as int?) ?? 77430;
  }

  static int get totalUniqueWords => 15072;

  /// Returns frequency map from SQLite vocab_words table.
  static Future<Map<String, WordData>> getWordFrequencies() async {
    final rows = await VocabularyRepository.getAllWordsByFrequency();
    final lang = WordGlossaryService.selectedLang;
    return {
      for (final r in rows.where((r) => !_hiddenStandalone.contains(r.arabicClean)))
        r.arabicClean: WordData(
          urdu: lang == 'en'
              ? (r.meaningEn.isNotEmpty ? r.meaningEn : r.meaningUr)
              : lang == 'hi'
                  ? (r.meaningHi.isNotEmpty ? r.meaningHi : r.meaningUr)
                  : r.meaningUr,
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
      JOIN vocab_words v ON v.id = aw.vocab_word_id
      WHERE aw.is_waqf = 0 AND aw.vocab_word_id IS NOT NULL
        AND v.arabic_clean NOT IN $_hiddenStandaloneClean
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
      JOIN vocab_words v ON v.id = aw.vocab_word_id
      WHERE aw.is_waqf = 0 AND v.arabic_clean NOT IN $_hiddenStandaloneClean
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