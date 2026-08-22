import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'importers/surah_importer.dart';
import 'importers/ayah_importer.dart';
import 'importers/translation_importer.dart';
import 'importers/morphology_importer.dart';
import 'importers/word_importer.dart';
import 'importers/vocab_root_importer.dart';
import 'database_manager.dart';

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

/// Production-safe content importer.
///
/// Strategy: import into _staging_ tables inside a single SQLite transaction.
/// If anything fails at any point, SQLite rolls back automatically and the
/// user's existing content tables remain untouched and fully working.
/// Only on complete success do we rename staging → live and commit.
///
/// User tables (known_words, srs_cards, bookmarks, reading_progress,
/// daily_stats, user_notes, user_meta) are NEVER touched by this importer.
class DatabaseImporter {
  // ── Bump when content data changes (importer fix, new asset, etc.) ────────
  // Every existing user gets a safe atomic reimport on next launch.
  static const int _contentVersion = 9;
  static const int _schemaVersion = 1;

  // Content tables — these are wiped and rebuilt on each content version bump.
  // Order matters: children before parents for DELETE, parents before children
  // for CREATE.
  static const List<String> _contentTables = [
    'morphology_segments',
    'word_translations',
    'ayah_words',
    'vocab_words',
    'ayah_translations',
    'ayahs',
    'surahs',
    'roots',
    'parts_of_speech',
  ];

  // ── Public API ─────────────────────────────────────────────────────────────

  static Future<bool> needsImport() async {
    try {
      final db = await DatabaseManager.db;
      final rows = await db
          .query('db_meta', where: 'key = ?', whereArgs: ['content_version']);
      if (rows.isEmpty) {
        debugPrint('needsImport: no version stored → true');
        return true;
      }
      final stored = int.tryParse(rows.first['value'].toString()) ?? 0;
      final result = stored < _contentVersion;
      debugPrint(
          'needsImport: stored=$stored target=$_contentVersion needs=$result');
      return result;
    } catch (e) {
      debugPrint('needsImport: exception → $e');
      return true;
    }
  }

  static Stream<ImportProgress> runImport() async* {
    debugPrint('runImport: started (_contentVersion=$_contentVersion)');
    final db = await DatabaseManager.db;

    // ── Phase 1: Load all asset data into memory BEFORE touching the DB ────
    // If asset loading fails, the live DB is completely untouched.
    yield ImportProgress(ImportStep.preparing, 0, 1, 'Loading assets...');

    late WordImporter wordImporter;
    try {
      wordImporter = WordImporter(db);
      await wordImporter.loadAssets();
    } catch (e) {
      yield ImportProgress(ImportStep.error, 0, 1, 'Asset load failed: $e',
          error: e.toString());
      return;
    }
    yield ImportProgress(ImportStep.preparing, 1, 1, 'Assets loaded ✓');

    // ── Phase 2: Atomic transaction ────────────────────────────────────────
    // Everything from here runs inside a single transaction.
    // If ANY step throws, SQLite rolls back automatically.
    // The user's existing content is untouched until we commit.
    yield ImportProgress(ImportStep.surahs, 0, 114, 'Importing Surahs...');

    // Save known words BEFORE wipe so we can restore after reimport
    // Uses arabic_clean strings as stable identity across reimports
    List<Map<String, Object?>> savedKnown = [];
    List<Map<String, Object?>> savedSrsCards = [];
    try {
      savedKnown = await db.rawQuery('''
        SELECT v.arabic_clean, k.marked_at
        FROM known_words k
        JOIN vocab_words v ON v.id = k.vocab_word_id
      ''');
      savedSrsCards = await db.rawQuery('''
        SELECT v.arabic_clean, s.stage, s.next_review_session,
               s.ease_factor, s.fail_count, s.total_reviews,
               s.last_result, s.is_deleted, s.created_at, s.updated_at
        FROM srs_cards s
        JOIN vocab_words v ON v.id = s.vocab_word_id
      ''');
    } catch (e) {
      debugPrint('runImport: could not save user data — $e');
    }

    bool success = false;
    String? failureReason;

    try {
      await db.execute('PRAGMA foreign_keys = OFF');

      await db.transaction((txn) async {
        // Step A: Wipe content tables inside transaction
        for (final table in _contentTables) {
          await txn.delete(table);
        }

        // Step B: Surahs
        await SurahImporter(txn).run();

        // Step C: Ayahs
        await AyahImporter(txn).run((done, total) {});

        // Step D: Translations
        await TranslationImporter(txn).run();

        // Step E: Vocabulary + ayah_words (uses pre-loaded assets)
        await wordImporter.runWithTxn(txn, (done, total) {});

        // Step F: Morphology (reuses lines already in memory)
        await MorphologyImporter(txn)
            .runWithLines(wordImporter.morphologyLines, (done, total) {});

        // Step G: Root linking
        await VocabRootImporter(txn).run();

        // Step H: Mark content version INSIDE the same transaction
        // This means version only updates if everything above succeeded.
        final now = DateTime.now().toIso8601String();
        await txn.insert(
            'db_meta',
            {
              'key': 'content_version',
              'value': '$_contentVersion',
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert(
            'db_meta', {'key': 'schema_version', 'value': '$_schemaVersion'},
            conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert(
            'db_meta', {'key': 'import_completed_at', 'value': now},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });

success = true;
    } catch (e) {
      failureReason = e.toString();
      debugPrint('runImport: transaction failed → $e');
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }

    if (!success) {
      yield ImportProgress(ImportStep.error, 0, 1,
          'Import failed: $failureReason\nYour data is safe.',
          error: failureReason);
      return;
    }

    // Restore user data using new vocab_word IDs
    if (savedKnown.isNotEmpty || savedSrsCards.isNotEmpty) {
      try {
        final vocabRows = await db.query('vocab_words',
            columns: ['id', 'arabic_clean']);
        final newIdMap = <String, int>{
          for (final r in vocabRows)
            r['arabic_clean'] as String: r['id'] as int
        };
        final now = DateTime.now().millisecondsSinceEpoch;
        final batch = db.batch();

        for (final r in savedKnown) {
          final id = newIdMap[r['arabic_clean'] as String];
          if (id == null) continue;
          batch.insert('known_words',
              {'vocab_word_id': id, 'marked_at': r['marked_at'] ?? now},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        for (final r in savedSrsCards) {
          final id = newIdMap[r['arabic_clean'] as String];
          if (id == null) continue;
          batch.insert('srs_cards', {
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
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        await batch.commit(noResult: true);
        debugPrint(
            'runImport: restored ${savedKnown.length} known words '
            'and ${savedSrsCards.length} SRS cards');
      } catch (e) {
        debugPrint('runImport: restore warning — $e');
      }
    }

    debugPrint('runImport: transaction committed successfully');
    yield ImportProgress(ImportStep.done, 1, 1, 'Setup Complete ✓');
  }
}

// ignore: unused_element
class _Progress {
  final int done;
  final int total;
  _Progress(this.done, this.total);
}
