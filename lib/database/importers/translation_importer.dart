import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

class TranslationImporter {
  final Database db;
  TranslationImporter(this.db);

  Future<void> run() async {
    await _importFile(
      assetPath: 'assets/data/bayan-ul-quran-simple.json',
      language: 'ur',
      scholarKey: 'bayanulquran',
    );
  }

  Future<void> _importFile({
    required String assetPath,
    required String language,
    required String scholarKey,
  }) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final data = json.decode(raw) as Map<String, dynamic>;

      // Load all ayah ids into memory: "surahId:ayahNum" → id
      final ayahRows = await db
          .rawQuery('SELECT id, surah_id, ayah_number FROM ayahs');
      final ayahIdMap = <String, int>{
        for (final r in ayahRows)
          '${r['surah_id']}:${r['ayah_number']}': r['id'] as int
      };

      const batchSize = 500;
      var batch = db.batch();
      int count = 0;

      for (final entry in data.entries) {
        final parts = entry.key.split(':');
        if (parts.length != 2) continue;
        final ayahId = ayahIdMap[entry.key];
        if (ayahId == null) continue;

        String text = '';
        final val = entry.value;
        if (val is Map) {
          text = val['t']?.toString() ?? '';
        } else {
          text = val.toString();
        }
        if (text.isEmpty) continue;

        batch.insert(
            'ayah_translations',
            {
              'ayah_id': ayahId,
              'language': language,
              'scholar_key': scholarKey,
              'text': text,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);

        count++;
        if (count % batchSize == 0) {
          await batch.commit(noResult: true);
          batch = db.batch();
        }
      }
      await batch.commit(noResult: true);
    } catch (e) {
      // Log but don't fail the whole import
    }
  }
}