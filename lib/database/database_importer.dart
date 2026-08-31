import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'importers/surah_importer.dart';
import 'importers/ayah_importer.dart';
import 'importers/translation_importer.dart';
import 'importers/morphology_importer.dart';
import 'importers/word_importer.dart';
import 'importers/vocab_root_importer.dart';
import 'database_manager.dart';
import 'asset_parser.dart';
import '../services/crashlytics_service.dart';

enum ImportStep {
  preparing,
  surahs,
  ayahs,
  translations,
  words,
  morphology,
  vocabRoots,
  done,
  error,
}

class ImportProgress {
  final ImportStep step;
  final int done;
  final int total;
  final String label;
  final String? error;
  ImportProgress(this.step, this.done, this.total, this.label, {this.error});
  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
}

/// Per-dataset version strategy.
/// Bump ONLY the version whose asset/importer changed.
///
///  _vCore        — surahs + ayahs
///  _vVocab       — vocab_words + ayah_words + word_translations
///  _vMorphology  — morphology_segments + roots + parts_of_speech
///  _vTranslation — ayah_translations (Urdu/EN/HI full ayah)
class DatabaseImporter {
  static const int _vCore = 2;
  static const int _vVocab = 10;
  static const int _vMorphology = 7;
  static const int _vTranslation = 9;
  static const int _schemaVersion = 1;

  static Future<int> _stored(Database db, String key) async {
    final rows = await db.query('db_meta', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'].toString()) ?? 0;
  }

  static Future<void> _setVer(
      DatabaseExecutor txn, String key, int value) async {
    await txn.insert('db_meta', {'key': key, 'value': '$value'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<bool> needsImport() async {
    try {
      final db = await DatabaseManager.db;
      final core = await _stored(db, 'v_core');
      final voc = await _stored(db, 'v_vocab');
      final mor = await _stored(db, 'v_morphology');
      final tra = await _stored(db, 'v_translation');
      final need = core < _vCore ||
          voc < _vVocab ||
          mor < _vMorphology ||
          tra < _vTranslation;
      debugPrint('needsImport: core=$core/$_vCore voc=$voc/$_vVocab '
          'mor=$mor/$_vMorphology tra=$tra/$_vTranslation → $need');
      return need;
    } catch (e, stack) {
      debugPrint('needsImport: $e');
      CrashlyticsService.recordError(e, stack,
          context: 'DatabaseImporter.needsImport');
      return true;
    }
  }

  // ── Asset loading (parallel, isolate-safe) ──────────────────────────────
  // Loads raw strings from rootBundle, then dispatches JSON parsing and
  // morphology splitting to a background isolate so the UI never stalls.

  static Future<ParsedAssets> _loadAndParseVocabAssets() async {
    // Load raw strings on main isolate (I/O is fast; parsing is CPU-heavy)
    final futures = <Future<String>>[
      rootBundle.loadString('assets/data/urud-wbw.json'),
      rootBundle.loadString(
          'assets/data/colored-english-wbw-translation.json'),
      rootBundle.loadString('assets/data/hindi-wbw.json'),
      rootBundle.loadString('assets/data/quran_morphology.txt'),
    ];
    final results = await Future.wait(futures);
    final urduRaw      = results[0];
    final englishRaw   = results[1];
    final hindiRaw     = results[2];
    final morphologyRaw = results[3];

    // Parse JSON glossaries on the UI thread (they're small enough)
    final urdu    = AssetParser.loadJson(urduRaw);
    final english = AssetParser.loadJson(englishRaw);
    final hindi   = AssetParser.loadJson(hindiRaw);

    // Parse morphology on a background isolate (6.3 MB, CPU-heavy)
    final parsed = await compute(
        AssetParser.parseMorphology,
        [morphologyRaw, urdu, english, hindi]);

    return parsed;
  }

  // ── Main entry point ────────────────────────────────────────────────────

  static Stream<ImportProgress> runImport() async* {
    final db = await DatabaseManager.db;

    final storedCore = await _stored(db, 'v_core');
    final storedVocab = await _stored(db, 'v_vocab');
    final storedMorph = await _stored(db, 'v_morphology');
    final storedTrans = await _stored(db, 'v_translation');

    final needCore = storedCore < _vCore;
    final needVocab = storedVocab < _vVocab || needCore;
    final needMorph = storedMorph < _vMorphology || needVocab;
    final needTrans = storedTrans < _vTranslation || needCore;

    // ── Phase 1: Load & parse assets (parallel isolate) ───────────────────
    if (needVocab || needMorph) {
      yield ImportProgress(ImportStep.preparing, 0, 1, 'Loading assets...');
      late ParsedAssets parsed;
      try {
        parsed = await _loadAndParseVocabAssets();
      } catch (e, stack) {
        yield ImportProgress(ImportStep.error, 0, 1, 'Asset load failed: $e',
            error: e.toString());
        CrashlyticsService.recordError(e, stack,
            context: 'DatabaseImporter._loadAndParseVocabAssets');
        return;
      }
      yield ImportProgress(ImportStep.preparing, 1, 1, 'Assets loaded ✓');

      // Build WordImporter from pre-parsed data
      final wordImporter = WordImporter.fromParsed(db, parsed);

      // ── Phase 2: Save user progress keyed by stable identities ────────
      List<Map<String, Object?>> savedKnown = [];
      List<Map<String, Object?>> savedSrs = [];
      List<Map<String, Object?>> savedBookmarks = [];
      List<Map<String, Object?>> savedReading = [];

      if (needVocab) {
        try {
          savedKnown = await db.rawQuery('''
            SELECT v.arabic_clean, k.marked_at
            FROM known_words k
            JOIN vocab_words v ON v.id = k.vocab_word_id
          ''');
          savedSrs = await db.rawQuery('''
            SELECT v.arabic_clean, s.stage, s.next_review_session,
                   s.ease_factor, s.fail_count, s.total_reviews,
                   s.last_result, s.is_deleted, s.created_at, s.updated_at
            FROM srs_cards s
            JOIN vocab_words v ON v.id = s.vocab_word_id
          ''');
        } catch (e) {
          debugPrint('save vocab progress: $e');
        }
      }
      if (needCore) {
        try {
          savedBookmarks = await db.rawQuery(
              'SELECT surah_id, ayah_number, created_at FROM bookmarks');
          savedReading = await db.rawQuery(
              'SELECT surah_id, last_ayah, last_read_at FROM reading_progress');
        } catch (e) {
          debugPrint('save surah progress: $e');
        }
      }

      // ── Phase 3: Run datasets in separate transactions ────────────────
      bool anyError = false;
      String? errorMsg;

      // ── Core ──────────────────────────────────────────────────────────
      if (needCore) {
        yield ImportProgress(ImportStep.surahs, 0, 1, 'Importing Surahs...');
        try {
          await db.execute('PRAGMA foreign_keys = OFF');
          await db.transaction((txn) async {
            await txn.delete('ayahs');
            await txn.delete('surahs');
            await SurahImporter(txn).run();
            await AyahImporter(txn).run((_, __) {});
            await _setVer(txn, 'v_core', _vCore);
          });
        } catch (e, stack) {
          anyError = true;
          errorMsg = 'Core import failed: $e';
          CrashlyticsService.recordError(e, stack,
              context: 'DatabaseImporter.core (with vocab/morph)');
        } finally {
          await db.execute('PRAGMA foreign_keys = ON');
        }
        if (anyError) {
          yield ImportProgress(ImportStep.error, 0, 1, errorMsg!,
              error: errorMsg);
          return;
        }
        yield ImportProgress(ImportStep.surahs, 1, 1, 'Surahs ✓');
      }

      // ── Vocab ─────────────────────────────────────────────────────────
      if (needVocab) {
        yield ImportProgress(ImportStep.words, 0, 1, 'Building Vocabulary...');
        try {
          await db.execute('PRAGMA foreign_keys = OFF');
          // Drop secondary indexes before bulk insert — recreate after.
          await _dropVocabIndexes(db);
          await db.transaction((txn) async {
            await txn.delete('word_translations');
            await txn.delete('ayah_words');
            await txn.delete('known_words');
            await txn.delete('srs_cards');
            await txn.delete('vocab_words');
            await wordImporter.runWithTxn(txn, (_, __) {});
            await _setVer(txn, 'v_vocab', _vVocab);
          });
          await _recreateVocabIndexes(db);
        } catch (e, stack) {
          anyError = true;
          errorMsg = 'Vocab import failed: $e';
          CrashlyticsService.recordError(e, stack,
              context: 'DatabaseImporter.vocab');
          await _recreateVocabIndexes(db); // always restore indexes
        } finally {
          await db.execute('PRAGMA foreign_keys = ON');
        }
        if (anyError) {
          yield ImportProgress(ImportStep.error, 0, 1, errorMsg!,
              error: errorMsg);
          return;
        }
        yield ImportProgress(ImportStep.words, 1, 1, 'Vocabulary ✓');
      }

      // ── Morphology ────────────────────────────────────────────────────
      if (needMorph) {
        yield ImportProgress(ImportStep.morphology, 0, 1,
            'Importing Morphology...');
        try {
          await db.execute('PRAGMA foreign_keys = OFF');
          await _dropMorphIndexes(db);
          await db.transaction((txn) async {
            await txn.delete('morphology_segments');
            await txn.delete('roots');
            await txn.delete('parts_of_speech');
            await MorphologyImporter(txn).runWithLines(
              wordImporter.morphologyLines,
              (_, __) {},
              morphWordText: parsed.morphWordText,
              morphLemma: parsed.morphLemma,
            );
            await _setVer(txn, 'v_morphology', _vMorphology);
          });
          await _recreateMorphIndexes(db);
          // VocabRootImporter runs AFTER indexes are restored so its
          // JOIN queries use them efficiently
          await VocabRootImporter(db).run();
          await db.insert('db_meta',
              {'key': 'v_morphology', 'value': '$_vMorphology'},
              conflictAlgorithm: ConflictAlgorithm.replace);
        } catch (e, stack) {
          anyError = true;
          errorMsg = 'Morphology import failed: $e';
          CrashlyticsService.recordError(e, stack,
              context: 'DatabaseImporter.morphology');
          await _recreateMorphIndexes(db);
        } finally {
          await db.execute('PRAGMA foreign_keys = ON');
        }
        if (anyError) {
          yield ImportProgress(ImportStep.error, 0, 1, errorMsg!,
              error: errorMsg);
          return;
        }
        yield ImportProgress(ImportStep.morphology, 1, 1, 'Morphology ✓');
      }

      // ── Translations ──────────────────────────────────────────────────
      if (needTrans) {
        yield ImportProgress(
            ImportStep.translations, 0, 1, 'Importing Translations...');
        try {
          await db.transaction((txn) async {
            await txn.delete('ayah_translations');
            await TranslationImporter(txn).run();
            await _setVer(txn, 'v_translation', _vTranslation);
          });
        } catch (e) {
          // Translations are non-fatal — app works without them
          debugPrint('Translation import warning: $e');
        }
        yield ImportProgress(ImportStep.translations, 1, 1, 'Translations ✓');
      }

      // Mark legacy key so old version checks also pass
      await db.insert('db_meta', {'key': 'content_version', 'value': '$_vVocab'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert(
          'db_meta',
          {
            'key': 'import_completed_at',
            'value': DateTime.now().toIso8601String()
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      // ── Phase 4: Restore user progress ────────────────────────────────
      if (needVocab && (savedKnown.isNotEmpty || savedSrs.isNotEmpty)) {
        yield ImportProgress(ImportStep.preparing, 0, 1, 'Restoring progress...');
        await _restoreVocab(db, savedKnown, savedSrs);
        yield ImportProgress(ImportStep.preparing, 1, 1, 'Progress restored ✓');
      }
      if (needCore && (savedBookmarks.isNotEmpty || savedReading.isNotEmpty)) {
        await _restoreSurah(db, savedBookmarks, savedReading);
      }

      yield ImportProgress(ImportStep.done, 1, 1, 'Setup Complete ✓');
    } else if (needCore) {
      // No vocab/morph needed but core might be — short-circuit the asset load
      // ── Phase 2: Save user progress ───────────────────────────────────
      List<Map<String, Object?>> savedBookmarks = [];
      List<Map<String, Object?>> savedReading = [];
      if (needCore) {
        try {
          savedBookmarks = await db.rawQuery(
              'SELECT surah_id, ayah_number, created_at FROM bookmarks');
          savedReading = await db.rawQuery(
              'SELECT surah_id, last_ayah, last_read_at FROM reading_progress');
        } catch (e) {
          debugPrint('save surah progress: $e');
        }
      }

      bool anyError = false;
      String? errorMsg;

      // ── Core ──────────────────────────────────────────────────────────
      if (needCore) {
        yield ImportProgress(ImportStep.surahs, 0, 1, 'Importing Surahs...');
        try {
          await db.execute('PRAGMA foreign_keys = OFF');
          await db.transaction((txn) async {
            await txn.delete('ayahs');
            await txn.delete('surahs');
            await SurahImporter(txn).run();
            await AyahImporter(txn).run((_, __) {});
            await _setVer(txn, 'v_core', _vCore);
          });
        } catch (e, stack) {
          anyError = true;
          errorMsg = 'Core import failed: $e';
          CrashlyticsService.recordError(e, stack,
              context: 'DatabaseImporter.core (core-only path)');
        } finally {
          await db.execute('PRAGMA foreign_keys = ON');
        }
        if (anyError) {
          yield ImportProgress(ImportStep.error, 0, 1, errorMsg!,
              error: errorMsg);
          return;
        }
        yield ImportProgress(ImportStep.surahs, 1, 1, 'Surahs ✓');
      }

      // ── Translations ──────────────────────────────────────────────────
      if (needTrans) {
        yield ImportProgress(
            ImportStep.translations, 0, 1, 'Importing Translations...');
        try {
          await db.transaction((txn) async {
            await txn.delete('ayah_translations');
            await TranslationImporter(txn).run();
            await _setVer(txn, 'v_translation', _vTranslation);
          });
        } catch (e) {
          debugPrint('Translation import warning: $e');
        }
        yield ImportProgress(ImportStep.translations, 1, 1, 'Translations ✓');
      }

      await db.insert('db_meta', {'key': 'content_version', 'value': '$_vVocab'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert(
          'db_meta',
          {
            'key': 'import_completed_at',
            'value': DateTime.now().toIso8601String()
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      if (needCore && (savedBookmarks.isNotEmpty || savedReading.isNotEmpty)) {
        await _restoreSurah(db, savedBookmarks, savedReading);
      }

      yield ImportProgress(ImportStep.done, 1, 1, 'Setup Complete ✓');
    } else {
      // Nothing to import — mark completion
      await db.insert('db_meta', {'key': 'content_version', 'value': '$_vVocab'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      yield ImportProgress(ImportStep.done, 1, 1, 'Already up to date ✓');
    }
  }

  static Future<void> _restoreVocab(
    Database db,
    List<Map<String, Object?>> known,
    List<Map<String, Object?>> srs,
  ) async {
    try {
      final rows =
          await db.query('vocab_words', columns: ['id', 'arabic_clean']);
      final idMap = <String, int>{
        for (final r in rows) r['arabic_clean'] as String: r['id'] as int
      };
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = db.batch();

      for (final r in known) {
        final id = idMap[r['arabic_clean'] as String];
        if (id == null) continue;
        batch.insert('known_words',
            {'vocab_word_id': id, 'marked_at': r['marked_at'] ?? now},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final r in srs) {
        final id = idMap[r['arabic_clean'] as String];
        if (id == null) continue;
        batch.insert(
            'srs_cards',
            {
              'vocab_word_id': id,
              'stage': r['stage'] ?? 0,
              'next_review_session': r['next_review_session'] ?? 0,
              'ease_factor': r['ease_factor'] ?? 2.5,
              'fail_count': r['fail_count'] ?? 0,
              'total_reviews': r['total_reviews'] ?? 0,
              'last_result': r['last_result'] ?? -1,
              'is_deleted': r['is_deleted'] ?? 0,
              'created_at': r['created_at'] ?? now,
              'updated_at': r['updated_at'] ?? now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
      debugPrint('restored ${known.length} known + ${srs.length} SRS cards');
    } catch (e) {
      debugPrint('restoreVocab: $e');
    }
  }

  static Future<void> _restoreSurah(
    Database db,
    List<Map<String, Object?>> bookmarks,
    List<Map<String, Object?>> reading,
  ) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = db.batch();
      for (final r in bookmarks) {
        batch.insert(
            'bookmarks',
            {
              'surah_id': r['surah_id'],
              'ayah_number': r['ayah_number'],
              'created_at': r['created_at'] ?? now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final r in reading) {
        batch.insert(
            'reading_progress',
            {
              'surah_id': r['surah_id'],
              'last_ayah': r['last_ayah'],
              'last_read_at': r['last_read_at'] ?? now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      debugPrint('restored ${bookmarks.length} bookmarks + '
          '${reading.length} reading positions');
    } catch (e) {
      debugPrint('restoreSurah: $e');
    }
  }

  // ── Index helpers ──────────────────────────────────────────────────────────
  // Dropping indexes before bulk inserts then recreating after is much
  // faster than maintaining B-tree indexes on every row insert.

  static Future<void> _dropVocabIndexes(Database db) async {
    for (final idx in [
      'idx_ayah_words_ayah_id',
      'idx_ayah_words_vocab_word_id',
      'idx_word_translations_word_id',
      'idx_vocab_words_arabic_clean',
    ]) {
      await db.execute('DROP INDEX IF EXISTS $idx');
    }
  }

  static Future<void> _recreateVocabIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ayah_words_ayah_id
      ON ayah_words(ayah_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ayah_words_vocab_word_id
      ON ayah_words(vocab_word_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_word_translations_word_id
      ON word_translations(word_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_vocab_words_arabic_clean
      ON vocab_words(arabic_clean)
    ''');
  }

  static Future<void> _dropMorphIndexes(Database db) async {
    for (final idx in [
      'idx_morphology_segments_word_id',
      'idx_morphology_segments_root_id',
    ]) {
      await db.execute('DROP INDEX IF EXISTS $idx');
    }
  }

  static Future<void> _recreateMorphIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_morphology_segments_word_id
      ON morphology_segments(word_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_morphology_segments_root_id
      ON morphology_segments(root_id)
    ''');
  }
}
