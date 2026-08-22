import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

class TranslationImporter {
  final DatabaseExecutor db;
  TranslationImporter(this.db);

  Future<void> run() async {
    // All three files have same format: {"surahId:ayahNum": {"t": "text", "f": {...}}}
    await _importFile(
      assetPath: 'assets/data/bayan-ul-quran-simple.json',
      language: 'ur',
      scholarKey: 'bayanulquran',
    );
    await _importFile(
      assetPath: 'assets/data/en-sahih-international-with-footnote-tags.json',
      language: 'en',
      scholarKey: 'sahihintl',
    );
    await _importFile(
      assetPath: 'assets/data/maulana-azizul-haque-al-umari-with-footnote-tags.json',
      language: 'hi',
      scholarKey: 'azizulhaque',
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

      final ayahRows =
          await db.rawQuery('SELECT id, surah_id, ayah_number FROM ayahs');
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

        // Extract text — handles both {"t": "text"} and plain string
        String text = '';
        final val = entry.value;
        if (val is Map) {
          // Format: {"t": "main text", "f": {"id": "footnote"}}
          text = val['t']?.toString() ?? '';
        } else {
          text = val.toString();
        }

        // Strip HTML tags and footnote superscripts
        text = _clean(text);
        if (text.isEmpty) continue;

        batch.insert(
          'ayah_translations',
          {
            'ayah_id': ayahId,
            'language': language,
            'scholar_key': scholarKey,
            'text': text,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        count++;
        if (count % batchSize == 0) {
          await batch.commit(noResult: true);
          batch = db.batch();
        }
      }
      await batch.commit(noResult: true);
    } catch (_) {
      // Skip if asset missing
    }
  }

  /// Remove HTML tags, footnote superscripts, and clean whitespace
  String _clean(String text) {
    return text
        .replaceAll(RegExp(r'<sup[^>]*>.*?</sup>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}