import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_manager.dart';
import '../repositories/morphology_repository.dart';
import '../services/sync_service.dart';
import '../services/word_progress_service.dart';

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
    unawaited(loadMorphologyDerivation());
  }

  // ── Compound-word grouping (و/ف/ال + stem) ────────────────────────────────
  // إياك and وإياك (or الذین/والذین, لا/ولا, أُو۟لَٰٓئِكَ/وأُو۟لَٰٓئِكَ,
  // etc.) are treated as ONE underlying word for known/unknown purposes —
  // whichever direction the user acts on (stem or compound, known or
  // unknown), the whole group stays in sync. There is no "derived vs
  // manual" distinction and no permanent-override tracking: the group's
  // state is always exactly "any member known → every member known",
  // enforced on every write and re-checked once at startup so any
  // pre-existing inconsistent state (e.g. from an earlier build) self-heals
  // automatically.
  //
  // Matching is done on each prefix segment's LEMMA (from the corpus tag,
  // e.g. CONJ|PREF|LEM:و, DET|PREF|LEM:ال) rather than guessing from the
  // surface Arabic text — this is what the corpus itself encodes as the
  // grammatical identity of the prefix, so it's the reliable signal.
  static const _transparentLemmas = {'و', 'ف', 'ال'};

  final Map<String, List<MorphSegmentLite>> _segmentsByClean = {};
  // compoundClean -> its stem's clean form
  final Map<String, String> _stemOfCompound = {};
  // stemClean -> set of compound cleans built from that stem
  final Map<String, Set<String>> _compoundsOfStem = {};
  bool _morphologyLoaded = false;
  Future<void>? _morphologyLoadFuture;
  // Clean strings whose group-sync couldn't run yet because morphology
  // wasn't loaded at the moment the user action happened.
  final Set<String> _pendingDerivationChecks = {};

  // A word qualifies for grouping if it has at least one prefix segment,
  // every prefix segment is one of و/ف/ال (by lemma), and it has exactly
  // one stem segment. Any suffix segment is allowed through unchanged —
  // it's part of the word's own spelling on both sides of the comparison
  // (e.g. أُو۟لَٰٓئِكَ's trailing ADDR-suffix ك is intrinsic to the
  // demonstrative, present whether or not و is prefixed), so it never
  // blocks grouping and is never itself treated as transparent.
  bool _isCompoundShapedSegs(List<MorphSegmentLite> segs) {
    final hasPrefix = segs.any((s) => s.type == 'prefix');
    if (!hasPrefix) return false; // nothing to strip — not a compound
    for (final s in segs) {
      if (s.type != 'prefix') continue;
      final lemma = WordProgressService.normalizeArabic(s.lemma);
      if (!_transparentLemmas.contains(lemma)) return false;
    }
    final stemCount = segs.where((s) => s.type == 'stem').length;
    return stemCount == 1;
  }

  /// Reconstructs the word's identity with transparent prefixes removed —
  /// concatenates every non-prefix segment (stem + any suffix) in order
  /// and normalizes the result. This is what should match the base word's
  /// own arabic_clean (e.g. stripping و from وأُو۟لَٰٓئِكَ's
  /// prefix+stem+suffix segments reconstructs أُو۟لَٰٓئِكَ exactly).
  String _coreClean(List<MorphSegmentLite> segs) {
    final core = segs
        .where((s) => s.type != 'prefix')
        .map((s) => s.arabicText)
        .join();
    return WordProgressService.normalizeArabic(core);
  }

  /// All clean forms that share known/unknown status with [clean] —
  /// its stem plus every transparent-prefix compound built from that stem.
  /// Returns a singleton set if [clean] has no such relations.
  Set<String> _groupFor(String clean) {
    final stem = _stemOfCompound[clean] ?? clean;
    final compounds = _compoundsOfStem[stem];
    if (compounds == null || compounds.isEmpty) return {clean};
    return {stem, ...compounds};
  }

  Future<void> loadMorphologyDerivation() {
    if (_morphologyLoaded) return Future.value();
    return _morphologyLoadFuture ??= _doLoadMorphologyDerivation();
  }

  Future<void> _doLoadMorphologyDerivation() async {
    _segmentsByClean
        .addAll(await MorphologyRepository.getRepresentativeSegmentsByClean());

    for (final entry in _segmentsByClean.entries) {
      if (!_isCompoundShapedSegs(entry.value)) continue;
      final stemClean = _coreClean(entry.value);
      if (stemClean.isEmpty || stemClean == entry.key) continue;
      _stemOfCompound[entry.key] = stemClean;
      _compoundsOfStem.putIfAbsent(stemClean, () => {}).add(entry.key);
    }
    _morphologyLoaded = true;

    // Self-healing backfill: for every group, if ANY member is already
    // known (from before this logic existed, or any prior inconsistent
    // state), bring the rest of the group up to match.
    final toMark = <int>[];
    for (final stem in _compoundsOfStem.keys) {
      final group = {stem, ..._compoundsOfStem[stem]!};
      if (!group.any((m) => isKnown(m))) continue;
      for (final member in group) {
        if (isKnown(member)) continue;
        final id = _cleanToId[member];
        if (id != null) toMark.add(id);
      }
    }
    await _batchMarkKnown(toMark);

    // Replay any user actions that raced with this load.
    final pending = _pendingDerivationChecks.toList();
    _pendingDerivationChecks.clear();
    for (final clean in pending) {
      await _syncGroupKnown(clean, isKnown(clean));
    }
  }

  /// Inserts many vocab_word_ids into known_words in one transaction, then
  /// does exactly one notifyListeners — used for the startup backfill so
  /// hundreds of qualifying words don't each pay per-call overhead.
  Future<void> _batchMarkKnown(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await DatabaseManager.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final id in ids) {
      batch.insert(
        'known_words',
        {'vocab_word_id': id, 'marked_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
    for (final id in ids) {
      _knownIds[id] = true;
    }
    notifyListeners();
    SyncService.scheduleSyncUp();
  }

  /// Brings every other member of [triggerClean]'s group to the same
  /// known/unknown state. Guarded by skipGroupSync on the recursive calls
  /// so this never loops back on itself.
  Future<void> _syncGroupKnown(String triggerClean, bool known) async {
    final group = _groupFor(triggerClean);
    if (group.length <= 1) return;
    debugPrint('[MorphSync] group for "$triggerClean" = $group -> '
        'syncing to known=$known');
    for (final member in group) {
      if (member == triggerClean) continue;
      if (isKnown(member) == known) continue;
      final id = _cleanToId[member];
      if (id == null) continue;
      if (known) {
        await setKnown(id, skipGroupSync: true);
      } else {
        await setUnknown(id, skipGroupSync: true);
      }
    }
  }

  /// Mark word as known. Writes to SQLite then notifies.
  Future<void> setKnown(int vocabWordId, {bool skipGroupSync = false}) async {
    if (_knownIds[vocabWordId] != true) {
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
    if (skipGroupSync) return;
    final clean = _idToClean[vocabWordId];
    if (clean == null) return;
    if (_morphologyLoaded) {
      await _syncGroupKnown(clean, true);
    } else {
      _pendingDerivationChecks.add(clean);
    }
  }

  /// Mark word as known by arabic_clean string.
  Future<void> setKnownByClean(String arabicClean,
      {bool skipGroupSync = false}) async {
    final id = _cleanToId[arabicClean];
    if (id == null) return;
    await setKnown(id, skipGroupSync: skipGroupSync);
  }

  /// Mark word as unknown. Removes from known_words.
  Future<void> setUnknown(int vocabWordId,
      {bool skipGroupSync = false}) async {
    if (_knownIds[vocabWordId] == true) {
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
    if (skipGroupSync) return;
    final clean = _idToClean[vocabWordId];
    if (clean == null) return;
    if (_morphologyLoaded) {
      await _syncGroupKnown(clean, false);
    } else {
      _pendingDerivationChecks.add(clean);
    }
  }

  /// Mark word as unknown by arabic_clean string.
  Future<void> setUnknownByClean(String arabicClean,
      {bool skipGroupSync = false}) async {
    final id = _cleanToId[arabicClean];
    if (id == null) return;
    await setUnknown(id, skipGroupSync: skipGroupSync);
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
    if (_morphologyLoaded) {
      final toMark = <int>[];
      for (final stem in _compoundsOfStem.keys) {
        final group = {stem, ..._compoundsOfStem[stem]!};
        if (!group.any((m) => isKnown(m))) continue;
        for (final member in group) {
          if (isKnown(member)) continue;
          final id = _cleanToId[member];
          if (id != null) toMark.add(id);
        }
      }
      await _batchMarkKnown(toMark);
    }
  }

  int get knownCount => _knownIds.length;

  int? vocabIdForClean(String arabicClean) => _cleanToId[arabicClean];
  String? cleanForVocabId(int vocabWordId) => _idToClean[vocabWordId];
}