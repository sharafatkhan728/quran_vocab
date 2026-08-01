import 'package:quran/quran.dart' as quran;
import 'package:sqflite/sqflite.dart';

class SurahImporter {
  final DatabaseExecutor db;
  SurahImporter(this.db);

  Future<void> run() async {
    final batch = db.batch();
    for (int i = 1; i <= 114; i++) {
      batch.insert(
          'surahs',
          {
            'id': i,
            'name_arabic': quran.getSurahNameArabic(i),
            'name_english': quran.getSurahName(i),
            'name_urdu': quran.getSurahName(i),
            'revelation_type': quran.getPlaceOfRevelation(i),
            'verse_count': quran.getVerseCount(i),
            'juz_start': quran.getJuzNumber(i, 1),
            'page_start': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
