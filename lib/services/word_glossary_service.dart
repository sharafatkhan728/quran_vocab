import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WordGlossaryService {
  static const Map<String, _GlossarySource> glossaries = {
    'ur': _GlossarySource(name: 'اردو', assetPath: 'assets/data/urud-wbw.json'),
    'en': _GlossarySource(
        name: 'English',
        assetPath: 'assets/data/colored-english-wbw-translation.json'),
    'hi':
        _GlossarySource(name: 'हिंदी', assetPath: 'assets/data/hindi-wbw.json'),
  };

  // cache: lang → {"surah:ayah:pos" → meaning}
  static final Map<String, Map<String, String>> _cache = {};
  static String _selectedLang = 'ur';

  // Call this in init() to ensure raw cache is always ready
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedLang = prefs.getString('word_gloss_lang') ?? 'ur';
    await _load(_selectedLang);
    // Always preload English raw for color coding
    if (_selectedLang != 'en') {
      _loadEnglishRaw(); // background, no await
    }
  }

  static Future<void> _loadEnglishRaw() async {
    if (_rawCache.containsKey('en')) return;
    final source = glossaries['en'];
    if (source?.assetPath == null) return;
    try {
      final raw = await rootBundle.loadString(source!.assetPath);
      final data = json.decode(raw) as Map<String, dynamic>;
      _rawCache['en'] = data.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {}
  }





  static String get selectedLang => _selectedLang;
  static String get selectedLangName =>
      glossaries[_selectedLang]?.name ?? 'اردو';

  static Future<void> setLanguage(String lang) async {
    _selectedLang = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('word_gloss_lang', lang);
    await _load(lang);
  }

  // static Future<void> _load(String lang) async {
  //   if (_cache.containsKey(lang)) return;
  //   final source = glossaries[lang];
  //   if (source == null) return;
  //   try {
  //     final raw = await rootBundle.loadString(source.assetPath);
  //     final data = json.decode(raw) as Map<String, dynamic>;
  //     // Format: {"1:1:1": "meaning", "1:1:2": "meaning2", ...}
  //     // Strip HTML tags for English
  //     _cache[lang] = data.map((k, v) =>
  //         MapEntry(k, _stripHtml(v.toString())));
  //   } catch (_) {
  //     _cache[lang] = {};
  //   }
  // }

  static String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  /// Get meaning by exact position key "surah:ayah:wordPos"
  static String getByPosition(int surah, int ayah, int pos, {String? lang}) {
    final l = lang ?? _selectedLang;
    return _cache[l]?['$surah:$ayah:$pos'] ?? '';
  }

  /// Get all meanings for a surah — returns Map<"ayah:pos", meaning>
  static Map<String, String> getSurahLookup(int surahId, {String? lang}) {
    final l = lang ?? _selectedLang;
    final cache = _cache[l] ?? {};
    final result = <String, String>{};
    final prefix = '$surahId:';
    for (final entry in cache.entries) {
      if (entry.key.startsWith(prefix)) {
        // Key: "surah:ayah:pos" → store as "ayah:pos"
        final rest = entry.key.substring(prefix.length);
        result[rest] = entry.value;
      }
    }
    return result;
  }

  // /// For English: get colored HTML spans (without stripping)
  // static String getRawByPosition(int surah, int ayah, int pos) {
  //   if (_selectedLang != 'en') return getByPosition(surah, ayah, pos);
  //   final l = 'en';
  //   return _cache[l]?['$surah:$ayah:$pos'] ?? '';
  // }

  static final Map<String, Map<String, String>> _rawCache =
      {}; // English raw HTML

  static Future<void> _load(String lang) async {
    if (_cache.containsKey(lang)) return;
    final source = glossaries[lang];
    if (source == null) return;
    try {
      final raw = await rootBundle.loadString(source.assetPath);
      final data = json.decode(raw) as Map<String, dynamic>;
      _cache[lang] = data.map((k, v) => MapEntry(k, _stripHtml(v.toString())));
      if (lang == 'en') {
        // Keep raw HTML for coloring
        _rawCache[lang] = data.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {
      _cache[lang] = {};
    }
  }

  static String getRawByPosition(int surah, int ayah, int pos) {
    return _rawCache['en']?['$surah:$ayah:$pos'] ?? '';
  }
}

class _GlossarySource {
  final String name;
  final String assetPath;
  const _GlossarySource({required this.name, required this.assetPath});
}
