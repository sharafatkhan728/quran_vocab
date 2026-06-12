import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TranslationService {
  // Available scholars
  static const Map<String, String> scholars = {
    'ur.jalandhry': 'Jalandhry (Urdu)',
    'ur.ahmedali': 'Ahmed Ali (Urdu)',
    'ur.kanzuliman': 'Kanz ul Iman (Urdu)',
    'en.sahih': 'Sahih International (English)',
    'en.pickthall': 'Pickthall (English)',
    'en.yusufali': 'Yusuf Ali (English)',
    'en.asad': 'Muhammad Asad (English)',
  };

  static const _cachePrefix = 'trans_';
  static String _selectedScholar = 'ur.jalandhry';

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedScholar = prefs.getString('selected_scholar') ?? 'ur.jalandhry';
  }

  static String get selectedScholar => _selectedScholar;
  static String get selectedScholarName => scholars[_selectedScholar] ?? '';

  static Future<void> setScholar(String key) async {
    _selectedScholar = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_scholar', key);
  }

  /// Fetch single ayah translation (cached)
  static Future<String?> getAyahTranslation(int surah, int ayah,
      {String? scholar}) async {
    final s = scholar ?? _selectedScholar;
    final cacheKey = '$_cachePrefix${s}_${surah}_$ayah';
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(cacheKey);
    if (cached != null) return cached;

    try {
      final url = 'https://api.alquran.cloud/v1/ayah/$surah:$ayah/$s';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final text = data['data']['text'] as String? ?? '';
        if (text.isNotEmpty) {
          await prefs.setString(cacheKey, text);
          return text;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Fetch all translations for one ayah (multiple scholars at once)
  static Future<Map<String, String>> getAllTranslations(
      int surah, int ayah) async {
    final editions = scholars.keys.join(',');
    final result = <String, String>{};
    try {
      final url =
          'https://api.alquran.cloud/v1/ayah/$surah:$ayah/editions/$editions';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final list = data['data'] as List;
        for (final item in list) {
          final edition = item['edition']['identifier'] as String;
          final text = item['text'] as String? ?? '';
          if (text.isNotEmpty) result[edition] = text;
        }
      }
    } catch (_) {}
    return result;
  }

  /// Get ayah for a word from cache (used in flashcards)
  static Future<Map<String, String>?> getWordSampleAyah(
      String normalizedArabic) async {
    final prefs = await SharedPreferences.getInstance();
    // Find which surah:ayah contains this word from our cached data
    for (int i = 1; i <= 114; i++) {
      final raw = prefs.getStringList('surah_word_counts_$i');
      if (raw == null) continue;
      final has = raw.any((e) {
        final p = e.split('|||');
        return p.isNotEmpty && p[0] == normalizedArabic;
      });
      if (has) {
        // Get ayah 1 of this surah as sample
        final arabicKey = 'ayah_arabic_${i}_1';
        final arabic = prefs.getString(arabicKey);
        if (arabic != null) {
          final translation = await getAyahTranslation(i, 1);
          return {
            'arabic': arabic,
            'translation': translation ?? '',
            'surah': '$i',
            'ayah': '1'
          };
        }
        // Fetch from API
        try {
          final url = 'https://api.alquran.cloud/v1/ayah/$i:1/quran-uthmani';
          final res = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 5));
          if (res.statusCode == 200) {
            final data = json.decode(res.body);
            final arabicText = data['data']['text'] as String? ?? '';
            await prefs.setString(arabicKey, arabicText);
            final translation = await getAyahTranslation(i, 1);
            return {
              'arabic': arabicText,
              'translation': translation ?? '',
              'surah': '$i',
              'ayah': '1',
            };
          }
        } catch (_) {}
        break;
      }
    }
    return null;
  }
}
