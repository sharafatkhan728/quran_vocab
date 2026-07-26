import '../database/database_manager.dart';
import 'content_repository.dart';

class MorphologyRepository {
  /// All segments for a word identified by surah:ayah:position.
  static Future<List<MorphSegmentRow>> getSegmentsByPosition(
      int surahId, int ayahNumber, int position) async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT
        ms.id, ms.word_id, ms.segment_number, ms.segment_type,
        ms.arabic_text, ms.lemma, ms.tense, ms.person, ms.gender,
        ms.number, ms.grammatical_case, ms.voice, ms.state,
        ms.verb_form, ms.raw_tag,
        COALESCE(p.code,      '') AS pos_code,
        COALESCE(p.color_hex, '#888888') AS pos_color_hex,
        COALESCE(r.arabic,    '') AS root
      FROM morphology_segments ms
      JOIN ayah_words aw ON aw.id = ms.word_id
      JOIN ayahs a ON a.id = aw.ayah_id
      LEFT JOIN parts_of_speech p ON p.id = ms.pos_id
      LEFT JOIN roots r ON r.id = ms.root_id
      WHERE a.surah_id = ? AND a.ayah_number = ? AND aw.position = ?
      ORDER BY ms.segment_number ASC
    ''', [surahId, ayahNumber, position]);
    return rows.map(MorphSegmentRow.fromMap).toList();
  }

  /// All occurrences of a root across the Quran.
  /// Returns list of {surahId, ayahNumber, position, arabicText}.
  static Future<List<Map<String, dynamic>>> getOccurrencesByRoot(
      String root) async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT DISTINCT
        a.surah_id, a.ayah_number, aw.position, aw.arabic_text
      FROM morphology_segments ms
      JOIN roots r ON r.id = ms.root_id
      JOIN ayah_words aw ON aw.id = ms.word_id
      JOIN ayahs a ON a.id = aw.ayah_id
      WHERE r.arabic = ? AND ms.segment_type = 'stem'
      ORDER BY a.surah_id ASC, a.ayah_number ASC
      LIMIT 100
    ''', [root]);
    return rows
        .map((r) => {
              'surahId': r['surah_id'] as int,
              'ayahNumber': r['ayah_number'] as int,
              'position': r['position'] as int,
              'arabicText': r['arabic_text'] as String,
            })
        .toList();
  }

  /// All forms derived from a root, grouped by lemma.
  /// Returns Map<lemma, List<{surahId, ayahNumber, position}>>.
  static Future<Map<String, List<Map<String, dynamic>>>> getRootForms(
      String root) async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT
        ms.lemma,
        a.surah_id, a.ayah_number, aw.position
      FROM morphology_segments ms
      JOIN roots r ON r.id = ms.root_id
      JOIN ayah_words aw ON aw.id = ms.word_id
      JOIN ayahs a ON a.id = aw.ayah_id
      WHERE r.arabic = ? AND ms.segment_type = 'stem'
        AND ms.lemma != ''
      ORDER BY ms.lemma ASC, a.surah_id ASC, a.ayah_number ASC
    ''', [root]);

    final result = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final lemma = r['lemma'] as String;
      result.putIfAbsent(lemma, () => []).add({
        'surahId': r['surah_id'] as int,
        'ayahNumber': r['ayah_number'] as int,
        'position': r['position'] as int,
      });
    }
    return result;
  }

  /// Dominant POS for a vocab word — used for grammar coloring.
  static Future<String> getDominantPos(int vocabWordId) async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT COALESCE(p.code, '') AS pos_code
      FROM morphology_segments ms
      JOIN ayah_words aw ON aw.id = ms.word_id
      LEFT JOIN parts_of_speech p ON p.id = ms.pos_id
      WHERE aw.vocab_word_id = ? AND ms.segment_type = 'stem'
      LIMIT 1
    ''', [vocabWordId]);
    if (rows.isEmpty) return '';
    return rows.first['pos_code'] as String? ?? '';
  }

  /// Color hex for a POS code.
  static Future<String> getPosColor(String posCode) async {
    final db = await DatabaseManager.db;
    final rows = await db.query('parts_of_speech',
        columns: ['color_hex'],
        where: 'code = ?',
        whereArgs: [posCode],
        limit: 1);
    if (rows.isEmpty) return '#888888';
    return rows.first['color_hex'] as String? ?? '#888888';
  }
}
