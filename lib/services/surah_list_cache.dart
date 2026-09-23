import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/content_repository.dart';

/// Single source of truth for the SurahListScreen disk-cache key, and a
/// standalone helper so screens other than SurahListScreen (e.g. the Surah
/// Reader, right after a bookmark toggle) can patch just the bookmarks
/// portion of the cached snapshot — without needing a reference to that
/// screen's State, and without risking a key mismatch between files.
class SurahListCache {
  SurahListCache._();

  static const String cacheKey = 'surah_list_cache_v1';

  static Future<void> refreshBookmarksOnly() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      final data = raw != null
          ? jsonDecode(raw) as Map<String, dynamic>
          : <String, dynamic>{};
      final bookmarks = await ContentRepository.getAllBookmarks();
      data['bookmarks'] = bookmarks;
      await prefs.setString(cacheKey, jsonEncode(data));
    } catch (_) {
      // Non-fatal — worst case the cached bookmarks strip is briefly stale
      // until the next full save from SurahListScreen._loadProgress().
    }
  }
}