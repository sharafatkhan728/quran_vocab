import 'package:quran/quran.dart' as quran;
import 'package:sqflite/sqflite.dart';

class AyahImporter {
  final DatabaseExecutor db;
  AyahImporter(this.db);

  Future<void> run(void Function(int done, int total) onProgress) async {
    for (int s = 1; s <= 114; s++) {
      final verseCount = quran.getVerseCount(s);
      final batch = db.batch();
      for (int a = 1; a <= verseCount; a++) {
        batch.insert(
            'ayahs',
            {
              'surah_id': s,
              'ayah_number': a,
              'arabic_text': quran.getVerse(s, a),
              'juz_number': quran.getJuzNumber(s, a),
              'ruku_number': 0,
              'is_bismillah': 0,
              'page_number': 0,
              'sajda_type': '',
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      onProgress(s, 114);
    }
  }
}