import 'package:shared_preferences/shared_preferences.dart';
import 'word_progress_service.dart';
import 'package:quran/quran.dart' as quran;

class QuranPreloaderService {
  static const String _loadedKey = 'quran_fully_loaded';

// >>>>>>>>>>>>>>
  static SharedPreferences? _prefs;
  static Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static Future<bool> isFullyLoaded() async {
    final prefs = await _getPrefs();
    final result = prefs.getBool(_loadedKey) ?? false;
    return result;
  }

  static Future<void> loadAllSurahs({
    required Function(int surahId, int total) onProgress,
    Function(String error)? onError,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    for (int surahId = 1; surahId <= 114; surahId++) {
      try {
        final verseCount = quran.getVerseCount(surahId);
        final Map<String, int> wordCounts = {};
        final Set<String> uniqueWords = {};

        for (int ayah = 1; ayah <= verseCount; ayah++) {
          String verse = quran.getVerse(surahId, ayah);
          if (ayah == 1 && surahId != 1 && surahId != 9) {
            final parts = verse.split(' ');
            // Bismillah is 4 words: بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
            if (parts.length > 4) verse = parts.skip(4).join(' ');
          }
          final words = verse.split(' ')

              .where((w) => w.trim().isNotEmpty).toList();

          for (final w in words) {
            final normalized = WordProgressService.normalizeArabic(w);
            if (normalized.isEmpty) continue;
            wordCounts[normalized] = (wordCounts[normalized] ?? 0) + 1;
            uniqueWords.add(normalized);
          }
        }

        await WordProgressService.saveSurahWordCounts(surahId, wordCounts);
        await WordProgressService.saveSurahWordList(surahId, uniqueWords);
        await prefs.setInt('surah_total_$surahId', uniqueWords.length);
      } catch (e) {
        onError?.call('Surah $surahId: $e');
      }
      onProgress(surahId, 114);
    }
    await prefs.setBool(_loadedKey, true);
  }
}  
//<<<<<<<<<<<<<<<<<<<<



  /// Loads all 114 surahs word data. Calls [onProgress] with surahId after each.
  /// 
  /// 
//   static Future<void> loadAllSurahs({
//     required Function(int surahId, int total) onProgress,
//     Function(String error)? onError,
//   }) async {
//     final prefs = await _getPrefs();

//     for (int surahId = 1; surahId <= 114; surahId++) {
//       // Skip if already loaded
//       final existing = prefs.getStringList('surah_word_counts_$surahId');
//       if (existing != null) {
//         onProgress(surahId, 114);
//         continue;
//       }

//       try {
//         final url =
//             'https://api.qurancdn.com/api/qdc/verses/by_chapter/$surahId'
//             '?words=true'
//             '&word_fields=text_uthmani,translation'
//             '&word_translation_language=ur'
//             '&per_page=300&page=1';

//         final response = await http.get(Uri.parse(url));
//         if (response.statusCode != 200) continue;

//         final data = json.decode(response.body);
//         final verses = data['verses'] as List;

//         final Map<String, int> wordCounts = {};
//         final Set<String> uniqueWords = {};

//         for (final verse in verses) {
//           final wordsJson = verse['words'] as List;
//           for (final w in wordsJson) {
//             if (w['char_type_name'] == 'end') continue;
//             final arabic = (w['text_uthmani'] ?? '') as String;
//             final urdu = (w['translation']?['text'] ?? '') as String;
//             final normalized = WordProgressService.normalizeArabic(arabic);
//             if (normalized.isEmpty) continue;

//             wordCounts[normalized] = (wordCounts[normalized] ?? 0) + 1;
//             uniqueWords.add(normalized);

//             // Save urdu meaning
//             await WordProgressService.saveWordUrdu(normalized, urdu);
//           }
//         }

//         // Save word counts and unique word list
//         await WordProgressService.saveSurahWordCounts(surahId, wordCounts);
//         await WordProgressService.saveSurahWordList(surahId, uniqueWords);
//         await prefs.setInt('surah_total_$surahId', uniqueWords.length);

//         onProgress(surahId, 114);
//       } catch (e) {
//         onError?.call('Surah $surahId: $e');
//         onProgress(surahId, 114); // still advance progress
//       }
//     }

//     await prefs.setBool(_loadedKey, true);
//   }
// }
