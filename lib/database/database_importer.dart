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

  ImportProgress(this.step, this.done, this.total, this.label,
      {this.error});

  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
}

class DatabaseImporter {
  static const int _contentVersion = 1;
  static const int _schemaVersion = 1;

  static Future<bool> needsImport() async {
    try {
      final db = await DatabaseManager.db;
      final rows = await db.query('db_meta',
          where: 'key = ?', whereArgs: ['content_version']);
      if (rows.isEmpty) return true;
      final stored =
          int.tryParse(rows.first['value'].toString()) ?? 0;
      return stored < _contentVersion;
    } catch (_) {
      return true;
    }
  }

  static Stream<ImportProgress> runImport() async* {
    final db = await DatabaseManager.db;

    yield ImportProgress(ImportStep.surahs, 0, 114, 'Importing Surahs...');
    try {
      await SurahImporter(db).run();
    } catch (e) {
      yield ImportProgress(ImportStep.error, 0, 1, 'Surah import failed', error: e.toString());
      return;
    }
    yield ImportProgress(ImportStep.surahs, 114, 114, 'Surahs ✓');

    yield ImportProgress(ImportStep.ayahs, 0, 114, 'Importing Ayahs...');
    try {
      final sub = StreamController<_Progress>();
      AyahImporter(db).run((done, total) {
        sub.add(_Progress(done, total));
      }).then((_) => sub.close()).catchError((e) {
        sub.addError(e);
        sub.close();
      });
      await for (final p in sub.stream) {
        yield ImportProgress(ImportStep.ayahs, p.done, p.total, 'Ayahs: ${p.done}/114');
      }
    } catch (e) {
      yield ImportProgress(ImportStep.error, 0, 1, 'Ayah import failed', error: e.toString());
      return;
    }
    yield ImportProgress(ImportStep.ayahs, 114, 114, 'Ayahs ✓');

    yield ImportProgress(ImportStep.translations, 0, 1, 'Importing Translations...');
    try {
      await TranslationImporter(db).run();
    } catch (e) {
      debugPrint('Translation warning: $e');
    }
    yield ImportProgress(ImportStep.translations, 1, 1, 'Translations ✓');

    yield ImportProgress(ImportStep.words, 0, 228, 'Building Vocabulary...');
    try {
      final sub = StreamController<_Progress>();
      WordImporter(db).run((done, total) {
        sub.add(_Progress(done, total));
      }).then((_) => sub.close()).catchError((e) {
        sub.addError(e);
        sub.close();
      });
      await for (final p in sub.stream) {
        yield ImportProgress(ImportStep.words, p.done, p.total, 'Vocabulary: ${p.done}/228');
      }
    } catch (e) {
      yield ImportProgress(ImportStep.error, 0, 1, 'Vocabulary import failed', error: e.toString());
      return;
    }
    yield ImportProgress(ImportStep.words, 228, 228, 'Vocabulary ✓');

    yield ImportProgress(ImportStep.morphology, 0, 100, 'Importing Morphology...');
    try {
      final sub = StreamController<_Progress>();
      MorphologyImporter(db).run((done, total) {
        sub.add(_Progress(done, total));
      }).then((_) => sub.close()).catchError((e) {
        sub.addError(e);
        sub.close();
      });
      await for (final p in sub.stream) {
        yield ImportProgress(ImportStep.morphology, p.done, p.total,
            'Morphology: ${(p.done / p.total * 100).round()}%');
      }
    } catch (e) {
      debugPrint('Morphology warning: $e');
    }
    yield ImportProgress(ImportStep.morphology, 100, 100, 'Morphology ✓');

    yield ImportProgress(ImportStep.vocabRoots, 0, 1, 'Linking Roots...');
    try {
      await VocabRootImporter(db).run();
    } catch (e) {
      debugPrint('Root linking warning: $e');
    }
    yield ImportProgress(ImportStep.vocabRoots, 1, 1, 'Roots ✓');

    // This MUST run before yielding done
    try {
      await _markComplete(db);
    } catch (e) {
      debugPrint('markComplete error: $e');
    }

    yield ImportProgress(ImportStep.done, 1, 1, 'Setup Complete ✓');
  }

   

  static Future<void> _markComplete(Database db) async {
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    batch.insert(
        'db_meta',
        {'key': 'content_version', 'value': '$_contentVersion'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert(
        'db_meta',
        {'key': 'schema_version', 'value': '$_schemaVersion'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert(
        'db_meta',
        {'key': 'import_completed_at', 'value': now},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }
}

class _Progress {
  final int done;
  final int total;
  _Progress(this.done, this.total);
  double get fraction => total == 0 ? 0 : done / total;
}