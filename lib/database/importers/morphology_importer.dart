import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

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
        } else if (tok == 'SG') {
          number = 'SG';
        } else if (tok == 'DU') {
          number = 'DU';
        } else if (tok == 'PL') {
          number = 'PL';
        } else if (tok == 'NOM') {
          gcase = 'NOM';
        } else if (tok == 'ACC') {
          gcase = 'ACC';
        } else if (tok == 'GEN') {
          gcase = 'GEN';
        } else if (tok == 'ACT') {
          voice = 'ACT';
        } else if (tok == 'PASS') {
          voice = 'PASS';
        } else if (tok == 'DEF') {
          state = 'DEF';
        } else if (tok == 'INDEF') {
          state = 'INDEF';
        } else if (RegExp(r'^[IVX]+$').hasMatch(tok)) {
          verbForm = tok;
        }
      }

      int? rootId;
      if (root.isNotEmpty) {
        rootId = await _getOrCreateRoot(root);
      }
      final posId = await _getPosId(effectivePosCode);

      batch.insert(
          'morphology_segments',
          {
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
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      count++;
      if (count % batchSize == 0) {
        await batch.commit(noResult: true);
        batch = db.batch();
        onProgress(count, total);
      }
    }
    await batch.commit(noResult: true);
    onProgress(total, total);
  }

  // Called from DatabaseImporter to reuse already-loaded lines
  Future<void> runWithLines(
      List<String> lines, void Function(int done, int total) onProgress) async {
    await _seedPartsOfSpeech();
    final wordIdMap = await _buildWordIdMap();
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
        if (tok.startsWith('ROOT:'))
          root = tok.substring(5);
        else if (tok.startsWith('LEM:'))
          lemma = tok.substring(4);
        else if (tok.startsWith('POS:'))
          effectivePosCode = tok.substring(4);
        else if (tok == 'PERF')
          tense = 'PERF';
        else if (tok == 'IMPF')
          tense = 'IMPF';
        else if (tok == 'IMPV')
          tense = 'IMPV';
        else if (tok == '1')
          person = '1';
        else if (tok == '2')
          person = '2';
        else if (tok == '3')
          person = '3';
        else if (tok == 'M')
          gender = 'M';
        else if (tok == 'F')
          gender = 'F';
        else if (tok == 'SG')
          number = 'SG';
        else if (tok == 'DU')
          number = 'DU';
        else if (tok == 'PL')
          number = 'PL';
        else if (tok == 'NOM')
          gcase = 'NOM';
        else if (tok == 'ACC')
          gcase = 'ACC';
        else if (tok == 'GEN')
          gcase = 'GEN';
        else if (tok == 'ACT')
          voice = 'ACT';
        else if (tok == 'PASS')
          voice = 'PASS';
        else if (tok == 'DEF')
          state = 'DEF';
        else if (tok == 'INDEF')
          state = 'INDEF';
        else if (RegExp(r'^[IVX]+$').hasMatch(tok)) verbForm = tok;
      }

      int? rootId;
      if (root.isNotEmpty) rootId = await _getOrCreateRoot(root);
      final posId = await _getPosId(effectivePosCode);

      batch.insert(
          'morphology_segments',
          {
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
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      count++;
      if (count % batchSize == 0) {
        await batch.commit(noResult: true);
        batch = db.batch();
        onProgress(count, total);
      }
    }
    await batch.commit(noResult: true);
    onProgress(total, total);
  }

  /// Load entire ayah_words table into memory map for O(1) lookup
  Future<Map<String, int>> _buildWordIdMap() async {
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

  Future<int> _getOrCreateRoot(String arabic) async {
    if (_rootCache.containsKey(arabic)) return _rootCache[arabic]!;
    final existing = await db.query('roots',
        columns: ['id'], where: 'arabic = ?', whereArgs: [arabic], limit: 1);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      _rootCache[arabic] = id;
      return id;
    }
    final id = await db.insert('roots', {'arabic': arabic});
    _rootCache[arabic] = id;
    return id;
  }

  Future<int?> _getPosId(String code) async {
    if (code.isEmpty) return null;
    if (_posCache.containsKey(code)) return _posCache[code];
    final existing = await db.query('parts_of_speech',
        columns: ['id'], where: 'code = ?', whereArgs: [code], limit: 1);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      _posCache[code] = id;
      return id;
    }
    return null;
  }

  Future<void> _seedPartsOfSpeech() async {
    const pos = [
      ('N', 'Noun', 'اسم', '#2196F3', ''),
      ('V', 'Verb', 'فعل', '#F44336', ''),
      ('P', 'Particle', 'حرف', '#4CAF50', ''),
      ('PN', 'Proper Noun', 'علم', '#9C27B0', ''),
      ('PRON', 'Pronoun', 'ضمیر', '#FF9800', ''),
      ('DEM', 'Demonstrative', 'اشارہ', '#795548', ''),
      ('REL', 'Relative Pronoun', '', '#607D8B', ''),
      ('T', 'Time', '', '#009688', ''),
      ('LOC', 'Location', '', '#3F51B5', ''),
      ('CONJ', 'Conjunction', '', '#8BC34A', ''),
      ('NEG', 'Negative', '', '#E91E63', ''),
      ('VOC', 'Vocative', '', '#FF5722', ''),
      ('INTG', 'Interrogative', '', '#00BCD4', ''),
      ('INL', 'Initial Letters', '', '#9E9E9E', ''),
      ('ADJ', 'Adjective', 'صفت', '#26C6DA', ''),
      ('SUB', 'Subordinating', '', '#78909C', ''),
      ('ACC', 'Particle', '', '#4CAF50', ''),
      ('CERT', 'Certainty', '', '#66BB6A', ''),
      ('FUT', 'Future', '', '#42A5F5', ''),
      ('VN', 'Verbal Noun', 'مصدر', '#AB47BC', ''),
      ('NV', 'Nominal Verb', '', '#EC407A', ''),
      ('PREV', 'Preventive', '', '#8D6E63', ''),
      ('ACT PCPL', 'Active Participle', 'اسم فاعل', '#29B6F6', ''),
      ('PASS PCPL', 'Passive Participle', 'اسم مفعول', '#26A69A', ''),
    ];
    final batch = db.batch();
    for (final p in pos) {
      batch.insert(
          'parts_of_speech',
          {
            'code': p.$1,
            'name_en': p.$2,
            'name_ur': p.$3,
            'color_hex': p.$4,
            'description': p.$5,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }
}
