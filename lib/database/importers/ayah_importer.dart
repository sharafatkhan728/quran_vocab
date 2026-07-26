import 'package:quran/quran.dart' as quran;
import 'package:sqflite/sqflite.dart';
import '../../data/ruku_data.dart';

class AyahImporter {
  final Database db;
  AyahImporter(this.db);

  Future<void> run(void Function(int done, int total) onProgress) async {
    for (int s = 1; s <= 114; s++) {
      final verseCount = quran.getVerseCount(s);
      final batch = db.batch();
      for (int a = 1; a <= verseCount; a++) {
        final rukuList = RukuData.rukuEnds[s] ?? [];
        // Find which ruku this ayah belongs to
        int rukuNum = 1;
      for (int r = 0; r < rukuList.length; r++) {
        if (a <= rukuList[r]) {
          rukuNum = r + 1;
          break;
        }
        if (r == rukuList.length - 1) {
          rukuNum = r + 1;
        }
      }
        batch.insert('ayahs', {
          'surah_id': s,
          'ayah_number': a,
          'arabic_text': quran.getVerse(s, a),
          'juz_number': quran.getJuzNumber(s, a),
          'ruku_number': rukuNum,
          'is_bismillah': (s != 1 && s != 9 && a == 1) ? 0 : 0,
          'page_number': 0,
          'sajda_type': '',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      onProgress(s, 114);
    }
  }
}