import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/content_repository.dart';
import 'package:flutter/foundation.dart';

class GlossarySource {
  final String name;
  const GlossarySource({required this.name});
}

class WordGlossaryService {
  static final ValueNotifier<String> langNotifier = ValueNotifier<String>('ur');
  static const Map<String, GlossarySource> glossaries = {
    'ur': GlossarySource(name: 'اردو'),
    'en': GlossarySource(name: 'English'),
    'hi': GlossarySource(name: 'हिंदी'),
  };

  static String _selectedLang = 'ur';

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedLang = prefs.getString('word_gloss_lang') ?? 'ur';
    langNotifier.value = _selectedLang;
  }

  static String get selectedLang => _selectedLang;
  static String get selectedLangName =>
      glossaries[_selectedLang]?.name ?? 'اردو';

  static Future<void> setLanguage(String lang) async {
    _selectedLang = lang;
    langNotifier.value = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('word_gloss_lang', lang);
  }

  /// Returns Map<"ayahNumber:position", meaningText> for a surah.
  /// Used by SurahReaderScreen to build the glossary lookup map.
  static Future<Map<String, String>> getSurahLookupAsync(int surahId,
      {String? lang}) async {
    final language = lang ?? _selectedLang;
    final ayahs = await ContentRepository.getAyahsForSurah(surahId);
    final result = <String, String>{};
    for (final ayah in ayahs) {
      final translations =
          await ContentRepository.getWordTranslationsForAyah(ayah.id, language);
      final words = await ContentRepository.getWordsForAyah(ayah.id);
      for (final word in words) {
        final trans = translations[word.id];
        if (trans != null && trans[language] != null) {
          result['${ayah.ayahNumber}:${word.position}'] = trans[language]!.text;
        }
      }
    }
    return result;
  }

  /// Sync version — kept for compile compatibility, returns empty.
  static Map<String, String> getSurahLookup(int surahId, {String? lang}) => {};

  /// All words for current language — used by vocabulary screen fallback.
  static Map<String, String> getAllWords({String? lang}) => {};

  static String getByPosition(int surah, int ayah, int pos, {String? lang}) =>
      '';

  static String getRawByPosition(int surah, int ayah, int pos) => '';
}
