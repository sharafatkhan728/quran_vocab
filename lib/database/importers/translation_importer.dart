import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

/// TranslationImporter — inserts ayah_translations for 3 languages.
///
/// Loads 3 JSON translation files and bulk-inserts into [ayah_translations].
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

  /// Static helper: parse a translation JSON string into a Map.
  /// Returns empty map on any error (graceful fallback).
  static Map<String, Map<String, String>> loadTranslations(String raw) {
    try {
      final data = json.decode(raw) as Map<String, dynamic>;
      return data.map((k, v) {
        String text = '';
        if (v is Map) {
          text = (v['t'] ?? '').toString();
        } else {
          text = v.toString();
        }
        return MapEntry(k, {'t': text});
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> _importFile({
    required String assetPath,
    required String language,
    required String scholarKey,
  }) async {
    try {
      final rawData = await rootBundle.loadString(assetPath);
      final data = await compute(TranslationImporter._parseJson, rawData);

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

  /// Parse JSON string — runs on isolate.
  static Map<String, dynamic> _parseJson(String raw) {
    return json.decode(raw) as Map<String, dynamic>;
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
