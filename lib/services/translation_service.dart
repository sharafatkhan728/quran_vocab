// ignore_for_file: unintended_html_in_doc_comment

import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/content_repository.dart';
import 'package:flutter/foundation.dart';

/// Controls which language the full ayah translation shows in —
/// affects Surah Reader, Flashcards, everywhere.
class TranslationLangService {
  static final ValueNotifier<String> langNotifier =
      ValueNotifier<String>('ur.bayanulquran');

  // This is now the ONLY copy of the selected scholar/language anywhere in
  // the app — TranslationService below reads it live instead of keeping its
  // own separate copy, so the two classes can never disagree with each
  // other regardless of which one's setScholar() is called.
  static String _selectedScholar = 'ur.bayanulquran';
  static String get selectedScholar => _selectedScholar;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedScholar =
        prefs.getString('selected_scholar') ?? 'ur.bayanulquran';
    langNotifier.value = _selectedScholar;
  }

  static Future<void> setScholar(String key) async {
    _selectedScholar = key;
    langNotifier.value = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_scholar', key);
  }

  // Alias so profile_settings_screen can call either name
  static Future<void> setLang(String key) => setScholar(key);
}

class TranslationService {
  static const Map<String, TranslationSource> scholars = {
    'ur.bayanulquran': TranslationSource(
      name: 'Bayan-ul-Quran (Urdu)',
      language: 'ur',
      scholarKey: 'bayanulquran',
      isRtl: true,
    ),
    'en.sahihintl': TranslationSource(
      name: 'Saheeh International (English)',
      language: 'en',
      scholarKey: 'sahihintl',
      isRtl: false,
    ),
    'hi.azizulhaque': TranslationSource(
      name: 'Maulana Azizul Haque (Hindi)',
      language: 'hi',
      scholarKey: 'azizulhaque',
      isRtl: false,
    ),
  };

  static Future<void> init() async {
    // No-op — TranslationLangService is the single source of truth and
    // loads the persisted value itself during its own init().
  }

  static String get selectedScholar => TranslationLangService.selectedScholar;
  static String get selectedScholarName =>
      scholars[selectedScholar]?.name ?? '';
  static bool get isRtl => scholars[selectedScholar]?.isRtl ?? true;

  static Future<void> setScholar(String key) =>
      TranslationLangService.setScholar(key);

  static Future<String?> getAyahTranslation(int surah, int ayah,
      {String? scholar}) async {
    final s = scholar ?? 'selected_Scholar';
    final source = scholars[s];
    if (source == null) return null;
    return ContentRepository.getAyahTranslation(
        surah, ayah, source.language, source.scholarKey);
  }

  /// Returns Map<ayahNumber, text> for the full surah — instant from SQLite.
  static Future<Map<String, String>> getSurahTranslationsAsync(int surahId,
      {String? scholar}) async {
    final key = scholar ?? selectedScholar;
    final source = scholars[key] ?? scholars[selectedScholar];
    if (source == null) return {};
    final map = await ContentRepository.getSurahTranslations(
        surahId, source.language, source.scholarKey);
    return map.map((k, v) => MapEntry('$k', v));
  }

  /// Synchronous version kept for call-site compatibility.
  /// Returns empty map if cache not warm — caller should use async version.
  static Map<String, String> getSurahTranslations(int surahId) => {};

  static Map<String, TranslationSource> get scholarsMap => scholars;
}

class TranslationSource {
  final String name;
  final String language;
  final String scholarKey;
  final bool isRtl;
  const TranslationSource({
    required this.name,
    required this.language,
    required this.scholarKey,
    required this.isRtl,
  });
}
