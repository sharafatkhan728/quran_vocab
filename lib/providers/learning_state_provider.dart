import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_manager.dart';
import '../services/sync_service.dart';
import '../services/notification_service.dart';

/// Single source of truth for word known/unknown status.
/// All screens read from and write to this provider.
/// SQLite `known_words` table is the canonical store.
class LearningStateProvider extends ChangeNotifier {
  // vocabWordId → true (known)
  final Map<int, bool> _knownIds = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Returns true if vocab word is known
  bool isKnownById(int vocabWordId) => _knownIds[vocabWordId] == true;

bool isKnown(String arabicClean) {
    if (!_loaded) return false;
    final id = _cleanToId[arabicClean];
    if (id == null) return false;
    return _knownIds[id] == true;
  }

  // arabic_clean → vocabWordId cache (loaded once)
  final Map<String, int> _cleanToId = {};
  final Map<int, String> _idToClean = {};

  /// Load all known words and vocab cache from SQLite once at startup.
  Future<void> init() async {
    if (_loaded) return;
    final db = await DatabaseManager.db;

    // Load vocab cache
    final vocabRows =
        await db.query('vocab_words', columns: ['id', 'arabic_clean']);
    for (final r in vocabRows) {
      final id = r['id'] as int;
      final clean = r['arabic_clean'] as String;
      _cleanToId[clean] = id;
      _idToClean[id] = clean;
    }

    // Load known words
    final knownRows = await db.query('known_words', columns: ['vocab_word_id']);
    for (final r in knownRows) {
      _knownIds[r['vocab_word_id'] as int] = true;
    }

    _loaded = true;
    notifyListeners();
  }

  /// Mark word as known. Writes to SQLite then notifies.
  Future<void> setKnown(int vocabWordId) async {
    if (_knownIds[vocabWordId] == true) return; // already known
    final db = await DatabaseManager.db;
    await db.insert(
      'known_words',
      {
        'vocab_word_id': vocabWordId,
        'marked_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _knownIds[vocabWordId] = true;
    notifyListeners();
    SyncService.scheduleSyncUp();
  }

  /// Mark word as known by arabic_clean string.
  Future<void> setKnownByClean(String arabicClean) async {
    final id = _cleanToId[arabicClean];
    if (id == null) return;
    await setKnown(id);
  }

  /// Mark word as unknown. Removes from known_words.
  Future<void> setUnknown(int vocabWordId) async {
    if (_knownIds[vocabWordId] != true) return; // already unknown
    final db = await DatabaseManager.db;
    await db.delete(
      'known_words',
      where: 'vocab_word_id = ?',
      whereArgs: [vocabWordId],
    );
    _knownIds.remove(vocabWordId);
    notifyListeners();
    SyncService.scheduleSyncUp();
  }

  /// Mark word as unknown by arabic_clean string.
  Future<void> setUnknownByClean(String arabicClean) async {
    final id = _cleanToId[arabicClean];
    if (id == null) return;
    await setUnknown(id);
  }

  /// Toggle known/unknown. Returns new known state.
  Future<bool> toggle(int vocabWordId) async {
    if (_knownIds[vocabWordId] == true) {
      await setUnknown(vocabWordId);
      return false;
    } else {
      await setKnown(vocabWordId);
      return true;
    }
  }

  /// Toggle by arabic_clean. Returns new known state.
  Future<bool> toggleByClean(String arabicClean) async {
    final id = _cleanToId[arabicClean];
    if (id == null) return false;
    return toggle(id);
  }

  /// All known arabic_clean strings (for progress calculation).
  Set<String> get allKnownCleans {
    final result = <String>{};
    for (final id in _knownIds.keys) {
      final clean = _idToClean[id];
      if (clean != null) result.add(clean);
    }
    return result;
  }

  /// Reload known words from SQLite (called after cloud sync restores data).
  Future<void> reload() async {
    final db = await DatabaseManager.db;
    _knownIds.clear();
    final knownRows = await db.query('known_words', columns: ['vocab_word_id']);
    for (final r in knownRows) {
      _knownIds[r['vocab_word_id'] as int] = true;
    }
    notifyListeners();
  }

  int get knownCount => _knownIds.length;

  int? vocabIdForClean(String arabicClean) => _cleanToId[arabicClean];
  String? cleanForVocabId(int vocabWordId) => _idToClean[vocabWordId];
}