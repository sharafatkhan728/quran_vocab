import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Caches all 6236 ayahs locally.
/// Uses fawazahmed0 CDN — no rate limit, no API key.
class QuranCacheService {
  static const _cachedKey = 'quran_ayahs_cached_v1';
  static const _dataKey = 'quran_ayah_data';

  // In-memory store: "surah:ayah" → arabic text
  static final Map<String, String> _arabic = {};
  // Index: normalized word → list of "surah:ayah" keys
  static final Map<String, List<String>> _wordIndex = {};
  static bool _loaded = false;

  static bool get isLoaded => _loaded;

  /// Call once at app start — loads from prefs or fetches from CDN
  static Future<void> initialize({
    Function(int progress, int total)? onProgress,
  }) async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(_cachedKey) == true) {
      // Load from prefs
      final raw = prefs.getString(_dataKey);
      if (raw != null) {
        final map = json.decode(raw) as Map<String, dynamic>;
        map.forEach((k, v) => _arabic[k] = v.toString());
        _buildIndex();
        _loaded = true;
        return;
      }
    }

    // Fetch from CDN surah by surah
    for (int surah = 1; surah <= 114; surah++) {
      try {
        final url =
            'https://cdn.jsdelivr.net/gh/fawazahmed0/quran-api@1'
            '/editions/ara-quranindopak/$surah.json';
        final res = await http.get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final ayahs = data['chapter'] as List;
          for (final a in ayahs) {
            final ayahNum = a['verse'] as int;
            final text = a['text'] as String;
            _arabic['$surah:$ayahNum'] = text;
          }
        }
      } catch (_) {
        // Skip failed surahs — will retry next time
      }
      onProgress?.call(surah, 114);
    }

    // Save to prefs

    await prefs.setString(_dataKey, json.encode(_arabic));
    await prefs.setBool(_cachedKey, true);
    _buildIndex();
    _loaded = true;
    
  }

  static void _buildIndex() {
    _wordIndex.clear();
    for (final entry in _arabic.entries) {
      final normalized = entry.value
          .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
      final words = normalized.split(' ');
      for (final w in words) {
        if (w.isEmpty) continue;
        _wordIndex.putIfAbsent(w, () => []).add(entry.key);
      }
    }
  }

  /// Get Arabic text of a specific ayah
  static String? getAyah(int surah, int ayah) => _arabic['$surah:$ayah'];

  /// Find first ayah containing a normalized Arabic word
  static Map<String, dynamic>? findAyahForWord(String normalizedWord) {
    // Use index for O(1) lookup
    final keys = _wordIndex[normalizedWord];
    if (keys != null && keys.isNotEmpty) {
      final key = keys.first;
      final parts = key.split(':');
      final ayahText = _arabic[key] ?? '';
      final ayahWords = ayahText
          .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
          .split(' ');
      int pos = 1;
      for (int i = 0; i < ayahWords.length; i++) {
        if (ayahWords[i] == normalizedWord) { pos = i + 1; break; }
      }
      return {
        'surah': int.parse(parts[0]),
        'ayah': int.parse(parts[1]),
        'arabic': ayahText,
        'wordPos': pos,
      };
    }

    // Fallback: partial match
    for (final entry in _arabic.entries) {
      final parts = entry.key.split(':');
      if (parts.length < 2) continue;
      final norm = entry.value.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
      if (norm.contains(normalizedWord)) {
        final words = norm.split(' ');
        int pos = 1;
        for (int i = 0; i < words.length; i++) {
          if (words[i].contains(normalizedWord)) { pos = i + 1; break; }
        }
        return {
          'surah': int.parse(parts[0]),
          'ayah': int.parse(parts[1]),
          'arabic': entry.value,
          'wordPos': pos,
        };
      }
    }
    return null;
  }


  /// Get all ayahs containing a normalized word
  static List<Map<String, dynamic>> findAllAyahsForWord(String normalizedWord) {
    final results = <Map<String, dynamic>>[];
    for (final entry in _arabic.entries) {
      final parts = entry.key.split(':');
      if (parts.length < 2) continue;
      final normalizedAyah = entry.value
          .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
      if (normalizedAyah.contains(normalizedWord)) {
        results.add({
          'surah': int.parse(parts[0]),
          'ayah': int.parse(parts[1]),
          'arabic': entry.value,
        });
      }
    }
    return results;
  }

  static bool get hasSomeData => _arabic.isNotEmpty;
}