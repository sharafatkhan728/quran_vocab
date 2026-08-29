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
  final Map<String, int> _posCache = {};
  final Map<String, int> _rootCache = {};

  MorphologyImporter(this.db);

  Future<void> run(void Function(int done, int total) onProgress) async {
    await _seedPartsOfSpeech();

    // Pre-load entire ayah_words table into memory
    // Map: "surahId:ayahNumber:position" → ayah_word.id
    final wordIdMap = await _buildWordIdMap();

    final raw = await rootBundle.loadString('assets/data/quran_morphology.txt');
    final lines = raw.split('\n');
    final total = lines.length;
    const batchSize = 1000;
    var batch = db.batch();
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
      if (root.isNotEmpty) rootId = await _getOrCreateRoot(root);
      final posId = await _getPosId(effectivePosCode);

      batch.insert('morphology_segments', {
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
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      count++;
      if (count % batchSize == 0) {
        await batch.commit(noResult: true);
        batch = db.batch();
      }

      if (count % 10000 == 0) {
        onProgress(count, total);
      }
    }
    await batch.commit(noResult: true);
    onProgress(total, total);
  }

  /// Fast path: accepts pre-parsed morphology data so we skip re-reading the
  /// 6 MB [quran_morphology.txt] file.
  ///
  /// [morphWordText] maps "surah:ayah:pos" → combined Arabic text (from
  /// [AssetParser.parseMorphology]).
  /// [morphLemma] maps "surah:ayah:pos" → dominant lemma.
  /// [morphologyLines] is the raw newline-split file content.
  Future<void> runWithLines(
    List<String> morphologyLines,
    void Function(int done, int total) onProgress, {
    Map<String, String>? morphWordText,
    Map<String, String>? morphLemma,
  }) async {
    await _seedPartsOfSpeech();

    // Pre-load entire ayah_words table into memory
    // Map: "surahId:ayahNumber:position" → ayah_word.id
    final wordIdMap = await _buildWordIdMap();

    final total = morphologyLines.length;
    const batchSize = 1000;
    var batch = db.batch();
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
      if (root.isNotEmpty) rootId = await _getOrCreateRoot(root);
      final posId = await _getPosId(effectivePosCode);

      batch.insert('morphology_segments', {
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
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      count++;
      if (count % batchSize == 0) {
        await batch.commit(noResult: true);
        batch = db.batch();
      }

      if (count % 10000 == 0) {
        onProgress(count, total);
      }
    }
    await batch.commit(noResult: true);
    onProgress(total, total);
  }

  Future<void> _seedPartsOfSpeech() async {
    final seedData = [
      {'code': 'N', 'name_en': 'Noun', 'name_ur': 'اسم', 'color_hex': '#4CAF50'},
      {'code': 'V', 'name_en': 'Verb', 'name_ur': 'فعل', 'color_hex': '#2196F3'},
      {'code': 'P', 'name_en': 'Pronoun', 'name_ur': 'ضمیر', 'color_hex': '#FF9800'},
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
    final rows = await db.rawQuery(
        'SELECT arabic_clean, id FROM ayah_words');
    final map = <String, int>{};
    for (final r in rows) {
      map[r['arabic_clean'] as String] = r['id'] as int;
    }
    return map;
  }

  Future<int?> _getOrCreateRoot(String rootArabic) async {
    if (rootArabic.isEmpty) return null;
    if (_rootCache.containsKey(rootArabic)) return _rootCache[rootArabic];
    final existing = await db.query('roots',
        where: 'arabic = ?', whereArgs: [rootArabic], limit: 1);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      _rootCache[rootArabic] = id;
      return id;
    }
    final id = await db.insert('roots', {'arabic': rootArabic},
        conflictAlgorithm: ConflictAlgorithm.replace);
    _rootCache[rootArabic] = id;
    return id;
  }

  Future<int> _getPosId(String posCode) async {
    if (posCode.isEmpty) return 1;
    if (_posCache.containsKey(posCode)) return _posCache[posCode]!;
    final existing = await db.query('parts_of_speech',
        where: 'code = ?', whereArgs: [posCode], limit: 1);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      _posCache[posCode] = id;
      return id;
    }
    // Create a new POS entry with generic info
    final id = await db.insert('parts_of_speech', {
      'code': posCode,
      'name_en': posCode,
      'name_ur': posCode,
      'color_hex': '#888888',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _posCache[posCode] = id;
    return id;
  }
}
