// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

/// MorphologyImporter — seeds parts_of_speech, inserts morphology_segments & roots.
///
/// Two entry points:
///   * [run] — legacy path that reads rootBundle internally (used by old code).
///   * [runWithLines] — new fast path that accepts pre-parsed line data, so
///     the caller (database_importer) can skip re-reading the 6 MB file.
class MorphologyImporter {
  final DatabaseExecutor db;
  // In-memory maps: key → id (built once before the main loop)
  final Map<String, int> _rootMap = {};
  final Map<String, int> _posMap = {};

  MorphologyImporter(this.db);

  Future<void> run(void Function(int done, int total) onProgress) async {
    await _seedPartsOfSpeech();
    final wordIdMap = await _buildWordIdMap();
    await _preloadMaps();

    final raw = await rootBundle.loadString('assets/data/quran_morphology.txt');
    final lines = raw.split('\n');
    final total = lines.length;
    final pendingRows = <Map<String, dynamic>>[];
    final newRoots = <String>[];
    final newPosCodes = <String>[];
    int count = 0;

    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final cols = t.split('\t');
      if (cols.length < 4) continue;

      final loc = cols[0].replaceAll('(', '').replaceAll(')', '').trim();
      final arabicText = cols[1].trim();
      final posCode = cols[2].trim();
      final tag = cols[3].trim();
      final parts = loc.split(':');
      if (parts.length < 4) continue;

      final surahId = int.tryParse(parts[0]) ?? 0;
      final ayahNum = int.tryParse(parts[1]) ?? 0;
      final wordPos = int.tryParse(parts[2]) ?? 0;
      final segNum = int.tryParse(parts[3]) ?? 1;

      final wordMapKey = '$surahId:$ayahNum:$wordPos';
      final wordId = wordIdMap[wordMapKey];
      if (wordId == null) {
        count++;
        continue;
      }

      String segType = 'stem';
      if (tag.contains('PREF')) segType = 'prefix';
      if (tag.contains('SUFF')) segType = 'suffix';

      String root = '', lemma = '', tense = '', person = '';
      String gender = '', number = '', gcase = '', voice = '';
      String state = '', verbForm = '';
      String effectivePosCode = posCode;

      for (final token in tag.split('|')) {
        final tok = token.trim();
        if (tok.startsWith('ROOT:')) {
          root = tok.substring(5);
        } else if (tok.startsWith('LEM:')) {
          lemma = tok.substring(4);
        } else if (tok.startsWith('POS:')) {
          effectivePosCode = tok.substring(4);
        } else if (tok == 'PERF') {
          tense = 'PERF';
        } else if (tok == 'IMPF') {
          tense = 'IMPF';
        } else if (tok == 'IMPV') {
          tense = 'IMPV';
        } else if (tok == '1') {
          person = '1';
        } else if (tok == '2') {
          person = '2';
        } else if (tok == '3') {
          person = '3';
        } else if (tok == 'M') {
          gender = 'M';
        } else if (tok == 'F') {
          gender = 'F';
        } else if (tok == 'S') {
          number = 'S';
        } else if (tok == 'D') {
          number = 'D';
        } else if (tok == 'P') {
          number = 'P';
        } else if (tok.startsWith('NOM')) {
          gcase = 'NOM';
        } else if (tok.startsWith('ACC')) {
          gcase = 'ACC';
        } else if (tok.startsWith('GEN')) {
          gcase = 'GEN';
        } else if (tok == 'IND') {
          voice = 'IND';
        } else if (tok == 'ACT') {
          voice = 'ACT';
        } else if (tok == 'PAS') {
          voice = 'PAS';
        } else if (tok == 'DET') {
          state = 'DET';
        } else if (tok == 'INDET') {
          state = 'INDET';
        } else if (tok.startsWith('V')) {
          verbForm = tok;
        }
      }

      int? rootId;
      if (root.isNotEmpty) {
        rootId = _rootMap[root];
        if (rootId == null) {
          newRoots.add(root);
          _rootMap[root] = -1;
        }
      }
      int? posId;
      if (effectivePosCode.isEmpty) {
        posId = 1;
      } else {
        posId = _posMap[effectivePosCode];
        if (posId == null) {
          newPosCodes.add(effectivePosCode);
          _posMap[effectivePosCode] = -1;
          posId = 1; // temporary; corrected after bulk insert
        }
      }

      pendingRows.add({
        'word_id': wordId,
        'segment_number': segNum,
        'segment_type': segType,
        'arabic_text': arabicText,
        'pos_id': posId,
        'root_id': rootId,
        'lemma': lemma,
        'tense': tense,
        'person': person,
        'gender': gender,
        'number': number,
        'grammatical_case': gcase,
        'voice': voice,
        'state': state,
        'verb_form': verbForm,
        'raw_tag': tag,
      });

      count++;
      if (count % 10000 == 0) {
        onProgress(count, total);
      }
    }

    // Bulk-insert new roots and POS codes so IDs are real before segment inserts
    if (newRoots.isNotEmpty) {
      var rb = db.batch();
      for (final r in newRoots) {
        rb.insert('roots', {'arabic': r},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await rb.commit(noResult: true);
      await _reloadRoots();
    }
    if (newPosCodes.isNotEmpty) {
      var pb = db.batch();
      for (final code in newPosCodes) {
        pb.insert('parts_of_speech', {
          'code': code,
          'name_en': code,
          'name_ur': code,
          'color_hex': '#888888',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await pb.commit(noResult: true);
      await _reloadPos();
    }

    // Now insert all morphology segments with correct IDs, batched at 1000
    const batchSize = 1000;
    var batch = db.batch();
    int batchCount = 0;
    for (final row in pendingRows) {
      batch.insert('morphology_segments', row,
          conflictAlgorithm: ConflictAlgorithm.replace);
      batchCount++;
      if (batchCount >= batchSize) {
        await batch.commit(noResult: true);
        batch = db.batch();
        batchCount = 0;
      }
    }
    if (batchCount > 0) await batch.commit(noResult: true);

    onProgress(total, total);
  }

  /// Fast path: accepts pre-parsed morphology data so we skip re-reading the
  /// 6 MB [quran_morphology.txt] file.
  Future<void> runWithLines(
    List<String> morphologyLines,
    void Function(int done, int total) onProgress, {
    Map<String, String>? morphWordText,
    Map<String, String>? morphLemma,
  }) async {
    await _seedPartsOfSpeech();
    final wordIdMap = await _buildWordIdMap();
    await _preloadMaps();

    final total = morphologyLines.length;
    final pendingRows = <Map<String, dynamic>>[];
    final newRoots = <String>[];
    final newPosCodes = <String>[];
    int count = 0;

    for (final line in morphologyLines) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final cols = t.split('\t');
      if (cols.length < 4) continue;

      final loc = cols[0].replaceAll('(', '').replaceAll(')', '').trim();
      final arabicText = cols[1].trim();
      final posCode = cols[2].trim();
      final tag = cols[3].trim();
      final parts = loc.split(':');
      if (parts.length < 4) continue;

      final surahId = int.tryParse(parts[0]) ?? 0;
      final ayahNum = int.tryParse(parts[1]) ?? 0;
      final wordPos = int.tryParse(parts[2]) ?? 0;
      final segNum = int.tryParse(parts[3]) ?? 1;

      final wordMapKey = '$surahId:$ayahNum:$wordPos';
      final wordId = wordIdMap[wordMapKey];
      if (wordId == null) {
        count++;
        continue;
      }

      String segType = 'stem';
      if (tag.contains('PREF')) segType = 'prefix';
      if (tag.contains('SUFF')) segType = 'suffix';

      String root = '', lemma = '', tense = '', person = '';
      String gender = '', number = '', gcase = '', voice = '';
      String state = '', verbForm = '';
      String effectivePosCode = posCode;

      for (final token in tag.split('|')) {
        final tok = token.trim();
        if (tok.startsWith('ROOT:')) {
          root = tok.substring(5);
        } else if (tok.startsWith('LEM:')) {
          lemma = tok.substring(4);
        } else if (tok.startsWith('POS:')) {
          effectivePosCode = tok.substring(4);
        } else if (tok == 'PERF') {
          tense = 'PERF';
        } else if (tok == 'IMPF') {
          tense = 'IMPF';
        } else if (tok == 'IMPV') {
          tense = 'IMPV';
        } else if (tok == '1') {
          person = '1';
        } else if (tok == '2') {
          person = '2';
        } else if (tok == '3') {
          person = '3';
        } else if (tok == 'M') {
          gender = 'M';
        } else if (tok == 'F') {
          gender = 'F';
        } else if (tok == 'S') {
          number = 'S';
        } else if (tok == 'D') {
          number = 'D';
        } else if (tok == 'P') {
          number = 'P';
        } else if (tok.startsWith('NOM')) {
          gcase = 'NOM';
        } else if (tok.startsWith('ACC')) {
          gcase = 'ACC';
        } else if (tok.startsWith('GEN')) {
          gcase = 'GEN';
        } else if (tok == 'IND') {
          voice = 'IND';
        } else if (tok == 'ACT') {
          voice = 'ACT';
        } else if (tok == 'PAS') {
          voice = 'PAS';
        } else if (tok == 'DET') {
          state = 'DET';
        } else if (tok == 'INDET') {
          state = 'INDET';
        } else if (tok.startsWith('V')) {
          verbForm = tok;
        }
      }

      int? rootId;
      if (root.isNotEmpty) {
        rootId = _rootMap[root];
        if (rootId == null) {
          newRoots.add(root);
          _rootMap[root] = -1;
        }
      }
      int? posId;
      if (effectivePosCode.isEmpty) {
        posId = 1;
      } else {
        posId = _posMap[effectivePosCode];
        if (posId == null) {
          newPosCodes.add(effectivePosCode);
          _posMap[effectivePosCode] = -1;
          posId = 1; // temporary; corrected after bulk insert
        }
      }

      pendingRows.add({
        'word_id': wordId,
        'segment_number': segNum,
        'segment_type': segType,
        'arabic_text': arabicText,
        'pos_id': posId,
        'root_id': rootId,
        'lemma': lemma,
        'tense': tense,
        'person': person,
        'gender': gender,
        'number': number,
        'grammatical_case': gcase,
        'voice': voice,
        'state': state,
        'verb_form': verbForm,
        'raw_tag': tag,
      });

      count++;
      if (count % 10000 == 0) {
        onProgress(count, total);
      }
    }

    // Bulk-insert new roots and POS codes so IDs are real before segment inserts
    if (newRoots.isNotEmpty) {
      var rb = db.batch();
      for (final r in newRoots) {
        rb.insert('roots', {'arabic': r},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await rb.commit(noResult: true);
      await _reloadRoots();
    }
    if (newPosCodes.isNotEmpty) {
      var pb = db.batch();
      for (final code in newPosCodes) {
        pb.insert('parts_of_speech', {
          'code': code,
          'name_en': code,
          'name_ur': code,
          'color_hex': '#888888',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await pb.commit(noResult: true);
      await _reloadPos();
    }

    // Now insert all morphology segments with correct IDs, batched at 1000
    const batchSize = 1000;
    var batch = db.batch();
    int batchCount = 0;
    for (final row in pendingRows) {
      batch.insert('morphology_segments', row,
          conflictAlgorithm: ConflictAlgorithm.replace);
      batchCount++;
      if (batchCount >= batchSize) {
        await batch.commit(noResult: true);
        batch = db.batch();
        batchCount = 0;
      }
    }
    if (batchCount > 0) await batch.commit(noResult: true);

    onProgress(total, total);
  }

  /// Pre-load all existing roots and parts_of_speech into in-memory maps.
  /// One query each — replaces thousands of per-line async lookups.
  Future<void> _preloadMaps() async {
    final roots = await db.query('roots', columns: ['id', 'arabic']);
    for (final r in roots) {
      _rootMap[r['arabic'] as String] = r['id'] as int;
    }
    final pos = await db.query('parts_of_speech', columns: ['id', 'code']);
    for (final r in pos) {
      _posMap[r['code'] as String] = r['id'] as int;
    }
  }

  /// After bulk-inserting new roots, reload the map with real IDs.
  Future<void> _reloadRoots() async {
    _rootMap.clear();
    final roots = await db.query('roots', columns: ['id', 'arabic']);
    for (final r in roots) {
      _rootMap[r['arabic'] as String] = r['id'] as int;
    }
  }

  /// After bulk-inserting new POS codes, reload the map with real IDs.
  Future<void> _reloadPos() async {
    _posMap.clear();
    final pos = await db.query('parts_of_speech', columns: ['id', 'code']);
    for (final r in pos) {
      _posMap[r['code'] as String] = r['id'] as int;
    }
  }

  Future<void> _seedPartsOfSpeech() async {
    final seedData = [
      {'code': 'N', 'name_en': 'Noun', 'name_ur': 'اسم', 'color_hex': '#2196F3'},
      {'code': 'V', 'name_en': 'Verb', 'name_ur': 'فعل', 'color_hex': '#F44336'},
      {'code': 'P', 'name_en': 'Particle', 'name_ur': 'حرف', 'color_hex': '#4CAF50'},
      {'code': 'PREP', 'name_en': 'Preposition', 'name_ur': 'حرف جار', 'color_hex': '#9C27B0'},
      {'code': 'CONN', 'name_en': 'Conjunction', 'name_ur': 'حرف ربط', 'color_hex': '#F44336'},
      {'code': 'ADV', 'name_en': 'Adverb', 'name_ur': 'قید', 'color_hex': '#00BCD4'},
      {'code': 'PART', 'name_en': 'Particle', 'name_ur': 'حرف', 'color_hex': '#795548'},
      {'code': 'DEM', 'name_en': 'Demonstrative', 'name_ur': 'اسم اشارہ', 'color_hex': '#607D8B'},
      {'code': 'REL', 'name_en': 'Relative', 'name_ur': 'اسم موصول', 'color_hex': '#3F51B5'},
      {'code': 'NUM', 'name_en': 'Numeral', 'name_ur': 'عدد', 'color_hex': '#009688'},
      {'code': 'Adj', 'name_en': 'Adjective', 'name_ur': 'صفت', 'color_hex': '#CDDC39'},
      {'code': 'Interj', 'name_en': 'Interjection', 'name_ur': 'استثنائی حرف', 'color_hex': '#E91E63'},
      {'code': 'Inf', 'name_en': 'Infinitive', 'name_ur': 'مصدر', 'color_hex': '#8BC34A'},
      {'code': 'PartPass', 'name_en': 'Passive Participle', 'name_ur': 'فاعل', 'color_hex': '#FF5722'},
      {'code': 'PartAct', 'name_en': 'Active Participle', 'name_ur': 'مفعول', 'color_hex': '#FFC107'},
      {'code': 'Gerund', 'name_en': 'Gerund', 'name_ur': 'مصدر معروف', 'color_hex': '#673AB7'},
      {'code': 'Command', 'name_en': 'Command', 'name_ur': 'امر', 'color_hex': '#795548'},
      {'code': 'Neg', 'name_en': 'Negation', 'name_ur': 'نہی', 'color_hex': '#607D8B'},
      {'code': 'Emph', 'name_en': 'Emphasis', 'name_ur': 'تاکید', 'color_hex': '#9C27B0'},
      {'code': 'Desir', 'name_en': 'Desire', 'name_ur': ' خواہش', 'color_hex': '#F44336'},
      {'code': 'Poss', 'name_en': 'Possession', 'name_ur': 'مالکیت', 'color_hex': '#00BCD4'},
      {'code': 'Condition', 'name_en': 'Condition', 'name_ur': 'شرط', 'color_hex': '#4CAF50'},
      {'code': 'Honor', 'name_en': 'Honor', 'name_ur': 'احترام', 'color_hex': '#FF9800'},
    ];
    for (final s in seedData) {
      await db.insert('parts_of_speech', s,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<Map<String, int>> _buildWordIdMap() async {
    // Map "surahId:ayahNumber:position" → ayah_word.id
    final rows = await db.rawQuery('''
      SELECT aw.id, a.surah_id, a.ayah_number, aw.position
      FROM ayah_words aw
      JOIN ayahs a ON a.id = aw.ayah_id
    ''');
    final map = <String, int>{};
    for (final r in rows) {
      final key = '${r['surah_id']}:${r['ayah_number']}:${r['position']}';
      map[key] = r['id'] as int;
    }
    return map;
  }
}
