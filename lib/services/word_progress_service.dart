import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/vocabulary_repository.dart';
import '../repositories/srs_repository.dart';
import '../database/database_manager.dart';

class WordProgressService {
  static const String _prefix = 'known_word_';

  static String normalizeArabic(String text) =>
      text.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '').trim();

  static Future<void> markAsKnown(String arabicText) async {
    final clean = normalizeArabic(arabicText);
    final vocab = await VocabularyRepository.getByArabicClean(clean);
    if (vocab == null) return;
    await VocabularyRepository.markKnown(vocab.id);
    _scheduleDailyUpdate();
  }

  static Future<void> markAsUnknown(String arabicText) async {
    final clean = normalizeArabic(arabicText);
    final vocab = await VocabularyRepository.getByArabicClean(clean);
    if (vocab == null) return;
    await VocabularyRepository.markUnknown(vocab.id);
  }

  static Future<bool> toggleWord(String arabicText) async {
    final clean = normalizeArabic(arabicText);
    final vocab = await VocabularyRepository.getByArabicClean(clean);
    if (vocab == null) return false;
    final db = await DatabaseManager.db;
    final rows = await db.query('known_words',
        where: 'vocab_word_id = ?', whereArgs: [vocab.id], limit: 1);
    if (rows.isNotEmpty) {
      await VocabularyRepository.markUnknown(vocab.id);
      return false;
    } else {
      await VocabularyRepository.markKnown(vocab.id);
      _scheduleDailyUpdate();
      return true;
    }
  }

  static Future<bool> isKnown(String arabicText) async {
    final clean = normalizeArabic(arabicText);
    final vocab = await VocabularyRepository.getByArabicClean(clean);
    if (vocab == null) return false;
    final db = await DatabaseManager.db;
    final rows = await db.query('known_words',
        where: 'vocab_word_id = ?', whereArgs: [vocab.id], limit: 1);
    return rows.isNotEmpty;
  }

  static Future<Set<String>> getAllKnownWords() =>
      VocabularyRepository.getAllKnownWordCleans();

  static Future<double> getProgressPercent() async {
    final known = await getAllKnownWords();
    return (known.length / 14870) * 100;
  }

  static int get totalUniqueWords => 14870;

  /// Returns frequency map from SQLite vocab_words table.
  /// Used by flashcard session builder and vocabulary screen.
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

  // ── Surah progress ────────────────────────────────────────────────────────

  static Future<Map<int, double>> getAllSurahProgress() async {
    final db = await DatabaseManager.db;
    final result = <int, double>{};
    for (int i = 1; i <= 114; i++) {
      final totalRows = await db.rawQuery('''
        SELECT COUNT(DISTINCT aw.vocab_word_id) AS cnt
        FROM ayah_words aw
        JOIN ayahs a ON a.id = aw.ayah_id
        WHERE a.surah_id = ? AND aw.is_waqf = 0 AND aw.vocab_word_id IS NOT NULL
      ''', [i]);
      final total = (totalRows.first['cnt'] as int?) ?? 0;
      if (total == 0) { result[i] = 0; continue; }

      final knownRows = await db.rawQuery('''
        SELECT COUNT(DISTINCT aw.vocab_word_id) AS cnt
        FROM ayah_words aw
        JOIN ayahs a ON a.id = aw.ayah_id
        JOIN known_words kw ON kw.vocab_word_id = aw.vocab_word_id
        WHERE a.surah_id = ? AND aw.is_waqf = 0
      ''', [i]);
      final knownCount = (knownRows.first['cnt'] as int?) ?? 0;
      result[i] = (knownCount / total * 100).clamp(0, 100);
    }
    return result;
  }

  static void recalculateAllSurahProgress() {
    // No-op — progress is now calculated on demand from SQLite
    // Left in place so existing call sites compile unchanged
  }

  // ── Legacy methods kept for compile compatibility ─────────────────────────
  // These are called from surah_reader_screen._saveWordData
  // They are no-ops now because the database is built during import

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

  // ── Kept for migration_manager and sync_service compatibility ─────────────
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