// ignore_for_file: unintended_html_in_doc_comment

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

class TranslationImporter {
  final DatabaseExecutor db;
  TranslationImporter(this.db);

  Future<void> run() async {
    // Urdu — existing format: Map<"surahId:ayahNum", {t: text}>
    await _importBayanFormat(
      assetPath: 'assets/data/bayan-ul-quran-simple.json',
      language: 'ur',
      scholarKey: 'bayanulquran',
    );

    // English — quran.com format: {verses:[{verse_key:"1:1", text:"..."}]}
    await _importQuranComFormat(
      assetPath: 'assets/data/en-sahih-international-with-footnote-tags.json',
      language: 'en',
      scholarKey: 'sahihintl',
    );

    // Hindi — quran.com format
    await _importQuranComFormat(
      assetPath: 'assets/data/maulana-azizul-haque-al-umari-with-footnote-tags.json',
      language: 'hi',
      scholarKey: 'azizulhaque',
    );
  }

  // ── Bayan-ul-Quran format: {"surahId:ayahNum": {"t": "text"}} ─────────────
  Future<void> _importBayanFormat({
    required String assetPath,
    required String language,
    required String scholarKey,
  }) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final data = json.decode(raw) as Map<String, dynamic>;

      final ayahIdMap = await _buildAyahIdMap();
      const batchSize = 500;
      var batch = db.batch();
      int count = 0;

      for (final entry in data.entries) {
        final ayahId = ayahIdMap[entry.key];
        if (ayahId == null) continue;
        String text = '';
        final val = entry.value;
        if (val is Map) {
          text = val['t']?.toString() ?? '';
        } else {
          text = val.toString();
        }
        text = _stripTags(text);
        if (text.isEmpty) continue;

        batch.insert('ayah_translations', {
          'ayah_id': ayahId,
          'language': language,
          'scholar_key': scholarKey,
          'text': text,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        count++;
        if (count % batchSize == 0) {
          await batch.commit(noResult: true);
          batch = db.batch();
        }
      }
      await batch.commit(noResult: true);
    } catch (e) {
      // Skip if asset missing
    }
  }

  // ── Quran.com format: {"verses":[{"verse_key":"1:1","text":"..."}]} ────────
  Future<void> _importQuranComFormat({
    required String assetPath,
    required String language,
    required String scholarKey,
  }) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final data = json.decode(raw);

      // Handle both array format and object with "verses" key
      List<dynamic> verses;
      if (data is List) {
        verses = data;
      } else if (data is Map && data.containsKey('verses')) {
        verses = data['verses'] as List;
      } else if (data is Map && data.containsKey('quran')) {
        // Some formats wrap in "quran" key
        verses = (data['quran'] as List?) ?? [];
      } else {
        // Try treating as map of verse_key → text
        await _importMapFormat(data as Map<String, dynamic>,
            language: language, scholarKey: scholarKey);
        return;
      }

      final ayahIdMap = await _buildAyahIdMap();
      const batchSize = 500;
      var batch = db.batch();
      int count = 0;

      for (final v in verses) {
        if (v is! Map) continue;

        // verse_key can be "1:1" or surah/ayah separate fields
        String verseKey = '';
        if (v.containsKey('verse_key')) {
          verseKey = v['verse_key'].toString();
        } else if (v.containsKey('surah_number') &&
            v.containsKey('ayah_number')) {
          verseKey = '${v['surah_number']}:${v['ayah_number']}';
        } else if (v.containsKey('chapter_id') &&
            v.containsKey('verse_number')) {
          verseKey = '${v['chapter_id']}:${v['verse_number']}';
        }
        if (verseKey.isEmpty) continue;

        final ayahId = ayahIdMap[verseKey];
        if (ayahId == null) continue;

        // text field name varies
        String text = (v['text'] ?? v['translation'] ?? v['content'] ?? '')
            .toString();
        text = _stripTags(text);
        if (text.isEmpty) continue;

        batch.insert('ayah_translations', {
          'ayah_id': ayahId,
          'language': language,
          'scholar_key': scholarKey,
          'text': text,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        count++;
        if (count % batchSize == 0) {
          await batch.commit(noResult: true);
          batch = db.batch();
        }
      }
      await batch.commit(noResult: true);
    } catch (e) {
      // Skip if asset missing or wrong format
    }
  }

  // ── Map format: {"1:1": "text", ...} ────────────────────────────────────
  Future<void> _importMapFormat(
    Map<String, dynamic> data, {
    required String language,
    required String scholarKey,
  }) async {
    final ayahIdMap = await _buildAyahIdMap();
    const batchSize = 500;
    var batch = db.batch();
    int count = 0;

    for (final entry in data.entries) {
      final ayahId = ayahIdMap[entry.key];
      if (ayahId == null) continue;
      final text = _stripTags(entry.value.toString());
      if (text.isEmpty) continue;

      batch.insert('ayah_translations', {
        'ayah_id': ayahId,
        'language': language,
        'scholar_key': scholarKey,
        'text': text,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      count++;
      if (count % batchSize == 0) {
        await batch.commit(noResult: true);
        batch = db.batch();
      }
    }
    await batch.commit(noResult: true);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<Map<String, int>> _buildAyahIdMap() async {
    final rows =
        await db.rawQuery('SELECT id, surah_id, ayah_number FROM ayahs');
    return {
      for (final r in rows)
        '${r['surah_id']}:${r['ayah_number']}': r['id'] as int
    };
  }

  /// Strip HTML/footnote tags like <fn>...</fn>, <sup>...</sup>, <b>...</b>
  String _stripTags(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}