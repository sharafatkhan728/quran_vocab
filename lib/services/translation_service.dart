// ignore_for_file: library_private_types_in_public_api

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TranslationService {
  static const Map<String, _TranslationSource> scholars = {
    // 'ur.maududi': _TranslationSource(
    //   name: 'Maududi (Urdu)',
    //   assetPath: 'assets/data/translation_ur_maududi.json',
    //   apiId: 'urd-maududi',
    //   isRtl: true,
    // ),
    'ur.bayanulquran': _TranslationSource(
      name: 'Bayan-ul-Quran (Urdu)',
      assetPath: 'assets/data/bayan-ul-quran-simple.json',
      apiId: 'ur.bayanulquran',
      isRtl: true,
    ),
    // 'en.sahih': _TranslationSource(
    //   name: 'Sahih International (English)',
    //   assetPath: 'assets/data/translation_en_sahih.json',
    //   apiId: 'eng-sahih',
    //   isRtl: false,
    // ),
    // 'en.pickthall': _TranslationSource(
    //   name: 'Pickthall (English)',
    //   assetPath: null,
    //   apiId: 'en.pickthall',
    //   isRtl: false,
    // ),
  };

  // In-memory cache: scholarKey → {surah:ayah → text}
  static final Map<String, Map<String, String>> _memCache = {};
  static String _selectedScholar = 'ur.bayanulquran';

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedScholar = prefs.getString('selected_scholar') ?? 'ur.bayanulquran';
    // Preload bundled translations into memory
    await _preloadBundled();
  }

  static String get selectedScholar => _selectedScholar;
  static String get selectedScholarName =>
      scholars[_selectedScholar]?.name ?? '';
  static bool get isRtl => scholars[_selectedScholar]?.isRtl ?? true;

  static Future<void> setScholar(String key) async {
    _selectedScholar = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_scholar', key);
    // Preload if bundled
    await _preloadBundled();
  }

  /// Preload all bundled translation files into memory — runs once
  static Future<void> _preloadBundled() async {
    final source = scholars[_selectedScholar];
    if (source?.assetPath == null) return;
    if (_memCache.containsKey(_selectedScholar)) return;

    try {
      final raw = await rootBundle.loadString(source!.assetPath!);
      final data = json.decode(raw) as Map<String, dynamic>;

      //
      final Map<String, String> translations = {};

      data.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final text = value['t']?.toString();

          if (text != null && text.isNotEmpty) {
            translations[key] = text;
          }
        }
      });

      _memCache[_selectedScholar] = translations;
      _memCache[_selectedScholar] = translations;
    } catch (e) {
      // Asset not found — will fall back to API
    }
  }

  /// Get translation for one ayah — instant if bundled, API if not
  static Future<String?> getAyahTranslation(int surah, int ayah,
      {String? scholar}) async {
    final s = scholar ?? _selectedScholar;

    // 1. Check in-memory cache (bundled)
    final memKey = '$surah:$ayah';
    if (_memCache[s]?.containsKey(memKey) == true) {
      return _memCache[s]![memKey];
    }

    // 2. Check SharedPreferences cache
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'trans_${s}_${surah}_$ayah';
    final cached = prefs.getString(cacheKey);
    if (cached != null) return cached;

    // 3. Fetch from API
    try {
      final source = scholars[s];
      final apiId = source?.apiId ?? s;
      final url = 'https://api.alquran.cloud/v1/ayah/$surah:$ayah/$apiId';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final text = data['data']['text'] as String? ?? '';
        if (text.isNotEmpty) {
          await prefs.setString(cacheKey, text);
          // Also add to memory cache
          _memCache.putIfAbsent(
            s,
            () => <String, String>{},
          )[memKey] = text;
          return text;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Get all translations for surah at once — for surah reader preload
  static Map<String, String> getSurahTranslations(int surahId) {
    final cache = _memCache[_selectedScholar] ?? {};
    final result = <String, String>{};
    for (int a = 1; a <= 300; a++) {
      final text = cache['$surahId:$a'];
      if (text != null) {
        result['$a'] = text;
      }
    }
    return result;
  }

  static Map<String, String> scholarsMap() =>
      scholars.map((k, v) => MapEntry(k, v.name));
}

class _TranslationSource {
  final String name;
  final String? assetPath;
  final String apiId;
  final bool isRtl;
  const _TranslationSource({
    required this.name,
    required this.assetPath,
    required this.apiId,
    required this.isRtl,
  });
}
