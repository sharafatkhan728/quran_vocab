import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'sync_service.dart';

class WordProgressService {
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static const String _prefix = 'known_word_';

  // Normalize Arabic text: remove diacritics (tashkeel) so
  // صِرَاطَ and صِرَاطَ and صراط all match as the same word
  static String normalizeArabic(String text) {
    // Remove tashkeel (diacritics), tatweel, and special chars
    return text.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '').trim();
  }

  static Future<void> markAsKnown(String arabicText) async {
    final prefs = await _getPrefs();
    final key = '$_prefix${normalizeArabic(arabicText)}';
    await prefs.setBool(key, true);
    SyncService.scheduleSyncUp();
  }

  static Future<void> markAsUnknown(String arabicText) async {
    final prefs = await _getPrefs();
    final key = '$_prefix${normalizeArabic(arabicText)}';
    await prefs.remove(key);
    SyncService.scheduleSyncUp();
  }

  static Future<bool> toggleWord(String arabicText) async {
    final prefs = await _getPrefs();
    final key = '$_prefix${normalizeArabic(arabicText)}';
    final isCurrentlyKnown = prefs.getBool(key) ?? false;
    if (isCurrentlyKnown) {
      await prefs.remove(key);
    } else {
      await prefs.setBool(key, true);
      // Track daily learning
      final today = DateTime.now();
      final dayKey =
          'daily_${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await prefs.setInt(dayKey, (prefs.getInt(dayKey) ?? 0) + 1);
    }
    SyncService.scheduleSyncUp();
    return !isCurrentlyKnown;
  }

  static Future<bool> isKnown(String arabicText) async {
    final prefs = await _getPrefs();
    final key = '$_prefix${normalizeArabic(arabicText)}';
    return prefs.getBool(key) ?? false;
  }

  static Future<Set<String>> getAllKnownWords() async {
    final prefs = await _getPrefs();
    return prefs
        .getKeys()
        .where((k) => k.startsWith(_prefix))
        .map((k) => k.replaceFirst(_prefix, ''))
        .toSet();
  }

  static Future<double> getProgressPercent() async {
    final known = await getAllKnownWords();
    return (known.length / 14870) * 100; // 14,870 authentic unique word forms
  }

  static int get totalUniqueWords => 14870;

// Save that user has visited/loaded a surah's words
  static Future<void> markSurahWordsLoaded(
      int surahId, Set<String> arabicWords) async {
    final prefs = await _getPrefs();
    final key = 'surah_total_$surahId';
    await prefs.setInt(key, arabicWords.length);
  }

  static Future<Map<int, double>> getAllSurahProgress() async {
    final prefs = await _getPrefs();
    await getAllKnownWords();
    final Map<int, double> result = {};
    for (int i = 1; i <= 114; i++) {
      final total = prefs.getInt('surah_total_$i') ?? 0;
      if (total == 0) {
        result[i] = 0;
        continue;
      }
      final surahKnown = prefs.getInt('surah_known_$i') ?? 0;
      result[i] = (surahKnown / total * 100).clamp(0, 100);
    }
    return result;
  }

  static Future<void> updateSurahKnownCount(int surahId, int knownCount) async {
    final prefs = await _getPrefs();
    await prefs.setInt('surah_known_$surahId', knownCount);
  }

  static Future<void> saveSurahWordList(
      int surahId, Set<String> normalizedWords) async {
    final prefs = await _getPrefs();
    await prefs.setStringList('surah_words_$surahId', normalizedWords.toList());
    await prefs.setInt('surah_total_$surahId', normalizedWords.length);
  }

  static Future<void> saveWordUrdu(String normalized, String urdu) async {
    final prefs = await _getPrefs();
    await prefs.setString('urdu_$normalized', urdu); // always overwrite
  }

  // ADD THIS new method:
  static Future<void> saveWordOriginal(
      String normalized, String original) async {
    final prefs = await _getPrefs();
    await prefs.setString('orig_$normalized', original); // always overwrite
  }

  // UPDATE getWordFrequencies to return original Arabic:
  static Future<Map<String, WordData>> getWordFrequencies() async {
    final prefs = await _getPrefs();
    final Map<String, int> freq = {};
    for (int i = 1; i <= 114; i++) {
      final raw = prefs.getStringList('surah_word_counts_$i');
      if (raw == null) continue;
      for (final entry in raw) {
        final parts = entry.split('|||');
        if (parts.length != 2) continue;
        final word = parts[0];
        final count = int.tryParse(parts[1]) ?? 1;
        freq[word] = (freq[word] ?? 0) + count;
      }
    }
    final Map<String, WordData> result = {};
    for (final entry in freq.entries) {
      final urdu = prefs.getString('urdu_${entry.key}') ?? '';
      final original = prefs.getString('orig_${entry.key}') ?? entry.key;
      result[entry.key] = WordData(
          urdu: urdu, frequency: entry.value, originalArabic: original);
    }
    return result;
  }

  static Future<void> saveSurahWordCounts(
      int surahId, Map<String, int> wordCounts) async {
    final prefs = await _getPrefs();
    // Store as "word|||count" strings
    final encoded =
        wordCounts.entries.map((e) => '${e.key}|||${e.value}').toList();
    await prefs.setStringList('surah_word_counts_$surahId', encoded);
  }

  // Recalculate known count for ALL surahs based on currently known words.
  // Debounced — rapid word toggles collapse into a single recalc.
  // Yields to the event loop every 10 surahs so the UI never janks.
  static bool _recalcRunning = false;
  static Timer? _recalcTimer;

  static void recalculateAllSurahProgress() {
    _recalcTimer?.cancel();
    _recalcTimer = Timer(const Duration(milliseconds: 500), _doRecalc);
  }

  static Future<void> _doRecalc() async {
    if (_recalcRunning) return;
    _recalcRunning = true;
    try {
      final prefs = await _getPrefs();
      final knownWords = await getAllKnownWords();
      for (int i = 1; i <= 114; i++) {
        final surahWords = prefs.getStringList('surah_words_$i');
        if (surahWords == null) continue;
        final knownInSurah =
            surahWords.where((w) => knownWords.contains(w)).length;
        prefs.setInt('surah_known_$i', knownInSurah);
        // Yield every 10 surahs so UI stays responsive
        if (i % 10 == 0) await Future.delayed(Duration.zero);
      }
    } finally {
      _recalcRunning = false;
    }
  }
}

class WordData {
  final String urdu;
  final int frequency;
  final String originalArabic;
  WordData(
      {required this.urdu, required this.frequency, this.originalArabic = ''});
}
