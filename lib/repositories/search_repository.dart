import '../database/database_manager.dart';

/// Search result types
enum SearchResultType { word, surah, ayah }

class SearchResult {
  final SearchResultType type;
  final String arabic;
  final String meaning;
  final String subtitle;
  final int surahId;
  final int ayahNumber;
  final int vocabWordId;
  final int frequency;

  const SearchResult({
    required this.type,
    required this.arabic,
    required this.meaning,
    required this.subtitle,
    this.surahId = 0,
    this.ayahNumber = 0,
    this.vocabWordId = 0,
    this.frequency = 0,
  });
}

class SearchRepository {
  /// Search vocab_words by Arabic text or Urdu/English meaning.
  /// Returns up to [limit] results ordered by frequency.
  static Future<List<SearchResult>> searchWords(
    String query, {
    int limit = 30,
    String lang = 'ur',
  }) async {
    if (query.trim().isEmpty) return [];
    final db = await DatabaseManager.db;
    final q = query.trim();

    // Detect Arabic vs Latin query
    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(q);
    final meaningCol = lang == 'en' ? 'meaning_en' : 'meaning_ur';

    List<Map<String, Object?>> rows;

    if (isArabic) {
      // Search arabic_clean and arabic_display
      rows = await db.rawQuery('''
        SELECT
          v.id, v.arabic_clean, v.arabic_display, v.frequency,
          v.meaning_ur, v.meaning_en,
          v.first_surah_id, v.first_ayah_number,
          COALESCE(r.arabic, '') AS root
        FROM vocab_words v
        LEFT JOIN roots r ON r.id = v.root_id
        WHERE v.arabic_clean LIKE ? OR v.arabic_display LIKE ?
        ORDER BY v.frequency DESC
        LIMIT ?
      ''', ['%$q%', '%$q%', limit]);
    } else {
      // Search meaning column
      rows = await db.rawQuery('''
        SELECT
          v.id, v.arabic_clean, v.arabic_display, v.frequency,
          v.meaning_ur, v.meaning_en,
          v.first_surah_id, v.first_ayah_number,
          COALESCE(r.arabic, '') AS root
        FROM vocab_words v
        LEFT JOIN roots r ON r.id = v.root_id
        WHERE v.$meaningCol LIKE ?
        ORDER BY v.frequency DESC
        LIMIT ?
      ''', ['%$q%', limit]);
    }

    return rows.map((r) {
      final meaning = lang == 'en'
          ? (r['meaning_en'] as String? ?? '')
          : (r['meaning_ur'] as String? ?? '');
      final freq = r['frequency'] as int? ?? 0;
      return SearchResult(
        type: SearchResultType.word,
        arabic: r['arabic_display'] as String? ?? '',
        meaning: meaning,
        subtitle: 'Occurs $freq× in Quran',
        surahId: r['first_surah_id'] as int? ?? 0,
        ayahNumber: r['first_ayah_number'] as int? ?? 0,
        vocabWordId: r['id'] as int? ?? 0,
        frequency: freq,
      );
    }).toList();
  }

  /// Search surah names (English and Arabic).
  static Future<List<SearchResult>> searchSurahs(
    String query, {
    int limit = 10,
  }) async {
    if (query.trim().isEmpty) return [];
    final db = await DatabaseManager.db;
    final q = query.trim();

    final rows = await db.rawQuery('''
      SELECT id, name_arabic, name_english, name_urdu, verse_count
      FROM surahs
      WHERE name_english LIKE ? OR name_arabic LIKE ? OR name_urdu LIKE ?
      ORDER BY id ASC
      LIMIT ?
    ''', ['%$q%', '%$q%', '%$q%', limit]);

    return rows
        .map((r) => SearchResult(
              type: SearchResultType.surah,
              arabic: r['name_arabic'] as String? ?? '',
              meaning: r['name_english'] as String? ?? '',
              subtitle: '${r['verse_count']} ayahs',
              surahId: r['id'] as int? ?? 0,
            ))
        .toList();
  }

  /// Search roots table.
  static Future<List<SearchResult>> searchRoots(
    String query, {
    int limit = 20,
  }) async {
    if (query.trim().isEmpty) return [];
    final db = await DatabaseManager.db;
    final q = query.trim();

    final rows = await db.rawQuery('''
      SELECT r.id, r.arabic, r.meaning_ur, r.meaning_en,
             COUNT(v.id) AS word_count
      FROM roots r
      LEFT JOIN vocab_words v ON v.root_id = r.id
      WHERE r.arabic LIKE ? OR r.meaning_ur LIKE ? OR r.meaning_en LIKE ?
      GROUP BY r.id
      ORDER BY word_count DESC
      LIMIT ?
    ''', ['%$q%', '%$q%', '%$q%', limit]);

    return rows
        .map((r) => SearchResult(
              type: SearchResultType.word,
              arabic: r['arabic'] as String? ?? '',
              meaning: r['meaning_ur'] as String? ??
                  r['meaning_en'] as String? ??
                  '',
              subtitle: '${r['word_count']} derived words',
              frequency: (r['word_count'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Combined search — words + surahs together, deduplicated.
  static Future<
      ({
        List<SearchResult> surahs,
        List<SearchResult> words,
        List<SearchResult> roots,
      })> searchAll(String query, {String lang = 'ur'}) async {
    if (query.trim().isEmpty) {
      return (
        surahs: <SearchResult>[],
        words: <SearchResult>[],
        roots: <SearchResult>[],
      );
    }
    final surahResults = await searchSurahs(query, limit: 5);
    final wordResults = await searchWords(query, limit: 25, lang: lang);
    final rootResults = await searchRoots(query, limit: 10);
    return (
      surahs: surahResults,
      words: wordResults,
      roots: rootResults,
    );
  }
}
