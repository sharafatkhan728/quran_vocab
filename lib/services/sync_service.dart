import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Syncs all user learning data between SharedPreferences (local) and
/// Firestore (cloud). Uses a debounce so rapid word taps only trigger
/// one write instead of many.
///
/// Firestore structure:
///   users/{uid}/progress/known_words   → {word: true, ...}
///   users/{uid}/progress/srs_cards     → {word: "stage|date|ease|...", ...}
///   users/{uid}/progress/daily_stats   → {date: count, ...}
///   users/{uid}/progress/surah_data    → {surah_words_1: [...], ...}
///   users/{uid}/progress/meta          → {lastSync: timestamp, ...}

class SyncService {
  SyncService._();

  static final _db = FirebaseFirestore.instance;
  static Timer? _debounceTimer;
  static bool _syncing = false;

  // Stream controller so UI can show sync status
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
  /// Waits 3 seconds of inactivity before actually writing to Firestore.
  static void scheduleSyncUp() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), () => syncUp());
  }

  /// Push all local data to Firestore immediately.
  static Future<void> syncUp() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_syncing) return;
    _syncing = true;
    _emit(SyncStatus.syncing);

    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      // ── 1. Known words ────────────────────────────────────────────────────
      final knownWords = <String, bool>{};
      for (final k in allKeys) {
        if (k.startsWith('known_word_')) {
          final word = k.replaceFirst('known_word_', '');
          knownWords[word] = true;
        }
      }

      // ── 2. SRS cards ──────────────────────────────────────────────────────
      final srsCards = <String, String>{};
      for (final k in allKeys) {
        if (k.startsWith('srs_') &&
            !k.contains('srs_total_points') &&
            !k.contains('srs_initialized') &&
            !k.contains('srs_session') &&
            !k.contains('srs_today')) {
          srsCards[k.replaceFirst('srs_', '')] = prefs.getString(k) ?? '';
        }
      }

      // ── 3. Daily stats (last 90 days) ─────────────────────────────────────
      final dailyStats = <String, int>{};
      for (final k in allKeys) {
        if (k.startsWith('daily_')) {
          dailyStats[k] = prefs.getInt(k) ?? 0;
        }
      }

      // ── 4. Surah word lists only (skip urdu/orig — rebuilt on read) ──────
      final surahData = <String, dynamic>{};
      for (final k in allKeys) {
        if (k.startsWith('surah_words_')) {
          surahData[k] = prefs.getStringList(k) ?? [];
        }
        if (k.startsWith('surah_word_counts_')) {
          surahData[k] = prefs.getStringList(k) ?? [];
        }
        // Skip urdu_ and orig_ keys — they are large and rebuilt automatically
        // when the user opens surahs. Syncing them risks Firestore field limits.
      }

      // ── 5. Meta ───────────────────────────────────────────────────────────
      final srsPoints = prefs.getInt('srs_total_points') ?? 0;
      final longestStreak = prefs.getInt('longest_streak') ?? 0;

      final ref = _db.collection('users').doc(uid).collection('progress');

      // Firestore has 1MB doc limit — chunk large maps if needed
      final batch = _db.batch();

      batch.set(ref.doc('known_words'), knownWords);
      batch.set(ref.doc('srs_cards'), srsCards);
      batch.set(ref.doc('daily_stats'), dailyStats);
      batch.set(ref.doc('meta'), {
        'lastSync': FieldValue.serverTimestamp(),
        'srs_total_points': srsPoints,
        'longest_streak': longestStreak,
        'srs_initialized': prefs.getBool('srs_initialized') ?? false,
        'todayDate': prefs.getString('srs_today_date') ?? '',
        'todayNew': prefs.getInt('srs_today_new') ?? 0,
      });

      await batch.commit();

      // Surah data can be large — write in a separate doc
      // Split into chunks of 400 keys to stay under Firestore 1MB limit
      final surahChunks = _chunkMap(surahData, 400);
      for (int i = 0; i < surahChunks.length; i++) {
        await ref.doc('surah_data_$i').set(surahChunks[i]);
      }

      _emit(SyncStatus.done);
    } catch (e) {
      debugPrint('SyncService.syncUp error: $e');
      _emit(SyncStatus.error);
    } finally {
      _syncing = false;
    }
  }

  /// Restore all data from Firestore to local SharedPreferences.
  /// Called on login. Will NOT overwrite local if local is newer.
  static Future<RestoreResult> syncDown() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return RestoreResult.noUser;
    _emit(SyncStatus.syncing);

    try {
      final ref = _db.collection('users').doc(uid).collection('progress');
      final prefs = await SharedPreferences.getInstance();

      // Check if cloud has any data at all
      final metaDoc = await ref.doc('meta').get();
      if (!metaDoc.exists) {
        // No cloud data — upload what we have locally
        _emit(SyncStatus.idle);
        await syncUp();
        return RestoreResult.uploadedLocal;
      }

      final meta = metaDoc.data()!;
      final cloudTimestamp = meta['lastSync'] as Timestamp?;
      final localLastSync = prefs.getInt('_last_sync_ts') ?? 0;

      // If local data is newer than cloud, push local instead
      if (cloudTimestamp != null) {
        final cloudMs = cloudTimestamp.millisecondsSinceEpoch;
        if (localLastSync > cloudMs) {
          _emit(SyncStatus.idle);
          await syncUp();
          return RestoreResult.uploadedLocal;
        }
      }

      // ── Restore known words ───────────────────────────────────────────────
      final knownDoc = await ref.doc('known_words').get();
      if (knownDoc.exists) {
        final data = knownDoc.data()!;
        for (final entry in data.entries) {
          await prefs.setBool('known_word_${entry.key}', true);
        }
      }

      // ── Restore SRS cards ─────────────────────────────────────────────────
      final srsDoc = await ref.doc('srs_cards').get();
      if (srsDoc.exists) {
        final data = srsDoc.data()!;
        for (final entry in data.entries) {
          await prefs.setString('srs_${entry.key}', entry.value.toString());
        }
      }

      // ── Restore daily stats ───────────────────────────────────────────────
      final dailyDoc = await ref.doc('daily_stats').get();
      if (dailyDoc.exists) {
        final data = dailyDoc.data()!;
        for (final entry in data.entries) {
          await prefs.setInt(entry.key, (entry.value as num).toInt());
        }
      }

      // ── Restore meta ──────────────────────────────────────────────────────
      await prefs.setInt(
          'srs_total_points', (meta['srs_total_points'] as num?)?.toInt() ?? 0);
      await prefs.setInt(
          'longest_streak', (meta['longest_streak'] as num?)?.toInt() ?? 0);
      await prefs.setBool(
          'srs_initialized', meta['srs_initialized'] as bool? ?? false);
      final todayDate = meta['todayDate'] as String?;
      if (todayDate != null && todayDate.isNotEmpty) {
        await prefs.setString('srs_today_date', todayDate);
      }
      final todayNew = meta['todayNew'];
      if (todayNew != null) {
        await prefs.setInt('srs_today_new', (todayNew as num).toInt());
      }

      // ── Restore surah data ────────────────────────────────────────────────
      for (int i = 0; i < 5; i++) {
        final surahDoc = await ref.doc('surah_data_$i').get();
        if (!surahDoc.exists) break;
        final data = surahDoc.data()!;
        for (final entry in data.entries) {
          final k = entry.key;
          final v = entry.value;
          if (k.startsWith('surah_words_') ||
              k.startsWith('surah_word_counts_')) {
            await prefs.setStringList(k, List<String>.from(v as List));
          } else if (k.startsWith('urdu_') || k.startsWith('orig_')) {
            await prefs.setString(k, v.toString());
          }
        }
      }

      // Save local timestamp so next restore can compare
      await prefs.setInt(
          '_last_sync_ts', DateTime.now().millisecondsSinceEpoch);

      _emit(SyncStatus.done);
      return RestoreResult.restoredFromCloud;
    } catch (e) {
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

  static List<Map<String, dynamic>> _chunkMap(
      Map<String, dynamic> map, int chunkSize) {
    final chunks = <Map<String, dynamic>>[];
    final keys = map.keys.toList();
    for (int i = 0; i < keys.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, keys.length);
      final chunk = {for (final k in keys.sublist(i, end)) k: map[k]};
      chunks.add(chunk);
    }
    if (chunks.isEmpty) chunks.add({});
    return chunks;
  }
}

enum SyncStatus { idle, syncing, done, error }

enum RestoreResult { restoredFromCloud, uploadedLocal, noUser, error }
