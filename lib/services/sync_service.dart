import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_manager.dart';

class SyncService {
  SyncService._();

  static final _db = FirebaseFirestore.instance;
  static Timer? _debounceTimer;
  static bool _syncing = false;
  static bool _syncQueued = false;

  static final _statusCtrl = StreamController<SyncStatus>.broadcast();
  static Stream<SyncStatus> get statusStream => _statusCtrl.stream;
  static SyncStatus _lastStatus = SyncStatus.idle;
  static SyncStatus get lastStatus => _lastStatus;

  static void _emit(SyncStatus s) {
    _lastStatus = s;
    _statusCtrl.add(s);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call after any word toggle or SRS card update.
  /// Waits 3 seconds of inactivity before writing to Firestore.
  static void scheduleSyncUp() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), () => syncUp());
  }

  /// Push all local SQLite user data to Firestore.
  static Future<void> syncUp() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_syncing) {
      _syncQueued = true;
      return;
    }
    _syncing = true;
    _emit(SyncStatus.syncing);
    try {
      final db = await DatabaseManager.db;

      // ── 1. Known words ────────────────────────────────────────────────────
      final knownRows = await db.rawQuery('''
        SELECT v.arabic_clean
        FROM known_words k
        JOIN vocab_words v ON v.id = k.vocab_word_id
      ''');
      final knownWords = <String, bool>{
        for (final r in knownRows) r['arabic_clean'] as String: true,
      };

      // ── 2. SRS cards ──────────────────────────────────────────────────────
      // Encode as "stage|nextSession|easeFactor|failCount|totalReviews|lastResult"
      final srsRows = await db.query('srs_cards',
          where: 'is_deleted = 0 OR is_deleted IS NULL');
      final srsCards = <String, String>{};
      for (final r in srsRows) {
        final id = (r['vocab_word_id'] as int).toString();
        srsCards[id] =
            '${r['stage']}|${r['next_review_session']}|${r['ease_factor']}'
            '|${r['fail_count']}|${r['total_reviews']}|${r['last_result']}';
      }

      // ── 3. Daily stats (last 90 days) ─────────────────────────────────────
      final today = DateTime.now();
      final cutoff = today.subtract(const Duration(days: 90));
      final cutoffKey =
          '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-'
          '${cutoff.day.toString().padLeft(2, '0')}';
      final dailyRows = await db.query('daily_stats',
          where: 'date_key >= ?', whereArgs: [cutoffKey]);
      final dailyStats = <String, int>{
        for (final r in dailyRows)
          r['date_key'] as String: (r['words_learned'] as int? ?? 0),
      };

      // ── 4. Reading progress ───────────────────────────────────────────────
      final progressRows = await db.query('reading_progress');
      final readingProgress = <String, int>{
        for (final r in progressRows)
          (r['surah_id'] as int).toString(): (r['last_ayah'] as int? ?? 0),
      };

      // ── 5. Bookmarks ──────────────────────────────────────────────────────
      final bookmarkRows = await db.query('bookmarks');
      final bookmarks = bookmarkRows
          .map((r) => '${r['surah_id']}:${r['ayah_number']}')
          .toList();

      // ── 6. User meta ──────────────────────────────────────────────────────
      final metaRows = await db.query('user_meta');
      final srsPoints = _metaInt(metaRows, 'srs_total_points');
      final longestStreak = _metaInt(metaRows, 'longest_streak');
      final srsSessions = _metaInt(metaRows, 'srs_total_sessions');

      final ref = _db.collection('users').doc(uid).collection('progress');
      final batch = _db.batch();

      batch.set(ref.doc('known_words'), knownWords);
      batch.set(ref.doc('srs_cards'), srsCards);
      batch.set(ref.doc('daily_stats'), dailyStats);
      batch.set(ref.doc('reading_progress'), readingProgress);
      batch.set(ref.doc('bookmarks'), {'list': bookmarks});
      batch.set(ref.doc('meta'), {
        'lastSync': FieldValue.serverTimestamp(),
        'srs_total_points': srsPoints,
        'longest_streak': longestStreak,
        'srs_total_sessions': srsSessions,
      });

      await batch.commit();

      // Store local sync timestamp in user_meta
      await db.insert(
        'user_meta',
        {
          'key': '_last_sync_ts',
          'value': '${DateTime.now().millisecondsSinceEpoch}',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      _emit(SyncStatus.done);
    } catch (e, stack) {
      debugPrint('SyncService.syncUp error: $e\n$stack');
      _emit(SyncStatus.error);
    } finally {
      _syncing = false;
      if (_syncQueued) {
        _syncQueued = false;
        scheduleSyncUp();
      }
    }
  }

  /// Restore all data from Firestore into local SQLite.
  /// Called on login. Will NOT overwrite local if local is newer.
  static Future<RestoreResult> syncDown() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return RestoreResult.noUser;
    _emit(SyncStatus.syncing);
    try {
      final ref = _db.collection('users').doc(uid).collection('progress');
      final db = await DatabaseManager.db;

      // Check if cloud has any data at all
      final metaDoc = await ref.doc('meta').get();
      if (!metaDoc.exists) {
        _emit(SyncStatus.idle);
        await syncUp();
        return RestoreResult.uploadedLocal;
      }

      final meta = metaDoc.data()!;
      final cloudTimestamp = meta['lastSync'] as Timestamp?;

      // Compare cloud vs local timestamps
      final localMetaRows = await db.query('user_meta',
          where: 'key = ?', whereArgs: ['_last_sync_ts'], limit: 1);
      final localLastSync = localMetaRows.isEmpty
          ? 0
          : int.tryParse(localMetaRows.first['value'] as String) ?? 0;

      if (cloudTimestamp != null) {
        final cloudMs = cloudTimestamp.millisecondsSinceEpoch;
        if (localLastSync > cloudMs) {
          // Local is newer — push up instead
          _emit(SyncStatus.idle);
          await syncUp();
          return RestoreResult.uploadedLocal;
        }
      }

      // Build vocab lookup once: arabic_clean → vocab_word_id
      final vocabRows =
          await db.query('vocab_words', columns: ['id', 'arabic_clean']);
      final vocabMap = <String, int>{
        for (final r in vocabRows)
          r['arabic_clean'] as String: r['id'] as int,
      };

      final now = DateTime.now().millisecondsSinceEpoch;

      // ── Restore known words ───────────────────────────────────────────────
      final knownDoc = await ref.doc('known_words').get();
      if (knownDoc.exists) {
        for (final entry in knownDoc.data()!.entries) {
          final vocabId = vocabMap[entry.key];
          if (vocabId == null) continue;
          await db.insert(
            'known_words',
            {'vocab_word_id': vocabId, 'marked_at': now},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      // ── Restore SRS cards ─────────────────────────────────────────────────
      final srsDoc = await ref.doc('srs_cards').get();
      if (srsDoc.exists) {
        for (final entry in srsDoc.data()!.entries) {
          final vocabId = int.tryParse(entry.key);
          if (vocabId == null) continue;
          final parts = entry.value.toString().split('|');
          await db.insert(
            'srs_cards',
            {
              'vocab_word_id': vocabId,
              'stage': int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0,
              'next_review_session':
                  int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
              'ease_factor':
                  double.tryParse(parts.elementAtOrNull(2) ?? '') ?? 2.5,
              'fail_count':
                  int.tryParse(parts.elementAtOrNull(3) ?? '') ?? 0,
              'total_reviews':
                  int.tryParse(parts.elementAtOrNull(4) ?? '') ?? 0,
              'last_result':
                  int.tryParse(parts.elementAtOrNull(5) ?? '') ?? -1,
              'is_deleted': 0,
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      // ── Restore daily stats ───────────────────────────────────────────────
      final dailyDoc = await ref.doc('daily_stats').get();
      if (dailyDoc.exists) {
        for (final entry in dailyDoc.data()!.entries) {
          await db.insert(
            'daily_stats',
            {
              'date_key': entry.key,
              'words_learned': (entry.value as num?)?.toInt() ?? 0,
              'sessions': 0,
              'points': 0,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      // ── Restore reading progress ──────────────────────────────────────────
      final progressDoc = await ref.doc('reading_progress').get();
      if (progressDoc.exists) {
        for (final entry in progressDoc.data()!.entries) {
          final surahId = int.tryParse(entry.key);
          final ayah = (entry.value as num?)?.toInt() ?? 0;
          if (surahId == null || ayah == 0) continue;
          await db.insert(
            'reading_progress',
            {
              'surah_id': surahId,
              'last_ayah': ayah,
              'last_read_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      // ── Restore bookmarks ─────────────────────────────────────────────────
      final bookmarkDoc = await ref.doc('bookmarks').get();
      if (bookmarkDoc.exists) {
        final list = bookmarkDoc.data()!['list'] as List? ?? [];
        for (final b in list) {
          final parts = b.toString().split(':');
          if (parts.length < 2) continue;
          final surahId = int.tryParse(parts[0]);
          final ayahNum = int.tryParse(parts[1]);
          if (surahId == null || ayahNum == null) continue;
          await db.insert(
            'bookmarks',
            {
              'surah_id': surahId,
              'ayah_number': ayahNum,
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      // ── Restore user meta ─────────────────────────────────────────────────
      final metaBatch = db.batch();
      for (final entry in {
        'srs_total_points':
            '${(meta['srs_total_points'] as num?)?.toInt() ?? 0}',
        'longest_streak':
            '${(meta['longest_streak'] as num?)?.toInt() ?? 0}',
        'srs_total_sessions':
            '${(meta['srs_total_sessions'] as num?)?.toInt() ?? 0}',
        '_last_sync_ts': '${DateTime.now().millisecondsSinceEpoch}',
      }.entries) {
        metaBatch.insert(
          'user_meta',
          {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await metaBatch.commit(noResult: true);

      _emit(SyncStatus.done);
      return RestoreResult.restoredFromCloud;

    } catch (e, stack) {
      debugPrint('SyncService.syncUp error: $e\n$stack');
      _emit(SyncStatus.error);
      return RestoreResult.error;
    }
  }

  /// Wipe all cloud data for the current user (used on account delete).
  static Future<void> deleteCloudData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final ref = _db.collection('users').doc(uid).collection('progress');
      final docs = await ref.get();
      final batch = _db.batch();
      for (final doc in docs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {}
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static int _metaInt(List<Map<String, Object?>> rows, String key) {
    final row = rows.where((r) => r['key'] == key).firstOrNull;
    if (row == null) return 0;
    return int.tryParse(row['value'] as String) ?? 0;
  }
}

enum SyncStatus { idle, syncing, done, error }

enum RestoreResult { restoredFromCloud, uploadedLocal, noUser, error }