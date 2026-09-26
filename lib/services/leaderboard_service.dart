import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_manager.dart';
import '../models/leaderboard_models.dart';

/// Handles the public-safe leaderboard profile: push (sync) + pull (fetch).
/// Deliberately throttled so a very active user can NEVER push more often
/// than [_minPushInterval] — this is what guarantees the free Firestore
/// quota (20k writes/day on Spark plan) can never be exceeded by normal use.
class LeaderboardService {
  LeaderboardService._();

  static final _db = FirebaseFirestore.instance;
  static const _minPushInterval = Duration(minutes: 10);
  static const _lastPushKey = 'leaderboard_last_push_ms';
  static const _hasProfileKey = 'leaderboard_has_profile';

  static Timer? _debounce;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── Profile existence (cached locally so we don't re-check every launch) ──
  // CRITICAL: the cache key is scoped by uid. Without this, switching
  // accounts on the same device (logout -> login with a different email)
  // would reuse account A's "has profile" flag for account B, silently
  // skipping profile setup and leaving account B with no leaderboard doc.

  static Future<bool> hasProfile() async {
    final uid = _uid;
    if (uid == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final key = '${_hasProfileKey}_$uid';
    if (prefs.getBool(key) == true) return true;
    try {
      final doc = await _db.collection('leaderboard').doc(uid).get();
      if (doc.exists) {
        await prefs.setBool(key, true);
        return true;
      }
    } catch (e) {
      debugPrint('LeaderboardService.hasProfile failed: $e');
    }
    return false;
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?> getMyProfile() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      return await _db.collection('leaderboard').doc(uid).get();
    } catch (_) {
      return null;
    }
  }

  /// Creates/updates the leaderboard profile. Call this from the setup
  /// screen — this is a rare, user-initiated action so no throttle needed.
  static Future<String> saveProfile({
    required String displayName,
    required String avatarEmoji,
    required String country,
    required String city,
    required bool visibleGlobal,
    required bool visibleCountry,
    required bool visibleCity,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not signed in');

    final existing = await _db.collection('leaderboard').doc(uid).get();
    String friendCode = (existing.data()?['friendCode'] as String?) ?? '';
    if (friendCode.isEmpty) {
      friendCode = await _generateUniqueFriendCode();
    }

    final stats = await _collectLocalStats();

    await _db.collection('leaderboard').doc(uid).set({
      'uid': uid,
      'displayName': displayName.trim(),
      'avatarEmoji': avatarEmoji,
      'country': country.trim(),
      'countryKey': country.trim().toLowerCase(),
      'city': city.trim(),
      'cityKey': city.trim().toLowerCase(),
      'friendCode': friendCode,
      'visibleGlobal': visibleGlobal,
      'visibleCountry': visibleCountry,
      'visibleCity': visibleCity,
      'points': stats.$1,
      'knownWords': stats.$2,
      'streak': stats.$3,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_hasProfileKey}_$uid', true);
    return friendCode;
  }

  static Future<String> _generateUniqueFriendCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no O/0/I/1 confusion
    final rand = Random();
    for (int attempt = 0; attempt < 5; attempt++) {
      final code =
          List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
      final dup = await _db
          .collection('leaderboard')
          .where('friendCode', isEqualTo: code)
          .limit(1)
          .get();
      if (dup.docs.isEmpty) return code;
    }
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  // ── Local stats (SQLite) ────────────────────────────────────────────────

  /// Returns (points, knownWords, streak)
  static Future<(int, int, int)> _collectLocalStats() async {
    final db = await DatabaseManager.db;

    final pointRows = await db.query('user_meta',
        where: 'key = ?', whereArgs: ['srs_total_points'], limit: 1);
    final points = pointRows.isEmpty
        ? 0
        : int.tryParse(pointRows.first['value'] as String) ?? 0;

    final knownRows =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM known_words');
    final knownWords = (knownRows.first['cnt'] as int?) ?? 0;

    final today = DateTime.now();
    final cutoff = today.subtract(const Duration(days: 365));
    final cutoffKey = _dateKey(cutoff);
    final dailyRows = await db.query('daily_stats',
        where: 'date_key >= ?', whereArgs: [cutoffKey]);
    final dailyMap = <String, int>{
      for (final r in dailyRows)
        r['date_key'] as String: (r['words_learned'] as int? ?? 0)
    };
    int streak = 0;
    for (int d = 0; d < 365; d++) {
      final day = today.subtract(Duration(days: d));
      if ((dailyMap[_dateKey(day)] ?? 0) > 0) {
        streak++;
      } else if (d > 0) {
        break;
      }
    }

    return (points, knownWords, streak);
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── Throttled push (called periodically / on resume) ────────────────────

  static void scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 20), () => pushNow());
  }

  static Future<void> pushNow({bool force = false}) async {
    final uid = _uid;
    if (uid == null) return;
    if (!await hasProfile()) return; // user hasn't set up leaderboard yet

    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      final last = prefs.getInt(_lastPushKey) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - last;
      if (elapsed < _minPushInterval.inMilliseconds) return; // throttled
    }

    try {
      final stats = await _collectLocalStats();
      await _db.collection('leaderboard').doc(uid).set({
        'points': stats.$1,
        'knownWords': stats.$2,
        'streak': stats.$3,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Also refresh my snapshot inside every group I belong to.
      final myGroups = await _db
          .collectionGroup('members')
          .where('uid', isEqualTo: uid)
          .get();
      for (final m in myGroups.docs) {
        await m.reference.set({
          'points': stats.$1,
          'knownWords': stats.$2,
          'streak': stats.$3,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await prefs.setInt(_lastPushKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('LeaderboardService.pushNow failed: $e');
    }
  }

  // ── Fetch (one-time reads, capped, no live listeners) ───────────────────

  static Future<List<LeaderboardEntry>> fetchGlobal({int limit = 100}) async {
    try {
      final snap = await _db
          .collection('leaderboard')
          .where('visibleGlobal', isEqualTo: true)
          .orderBy('points', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map(LeaderboardEntry.fromDoc).toList();
    } catch (e) {
      debugPrint('LeaderboardService.fetchGlobal failed: $e');
      rethrow;
    }
  }

  static Future<List<LeaderboardEntry>> fetchCountry(String country,
      {int limit = 100}) async {
    try {
      final snap = await _db
          .collection('leaderboard')
          .where('visibleCountry', isEqualTo: true)
          .where('countryKey', isEqualTo: country.trim().toLowerCase())
          .orderBy('points', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map(LeaderboardEntry.fromDoc).toList();
    } catch (e) {
      debugPrint('LeaderboardService.fetchCountry failed: $e');
      rethrow;
    }
  }

  static Future<List<LeaderboardEntry>> fetchCity(String city,
      {int limit = 100}) async {
    try {
      final snap = await _db
          .collection('leaderboard')
          .where('visibleCity', isEqualTo: true)
          .where('cityKey', isEqualTo: city.trim().toLowerCase())
          .orderBy('points', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map(LeaderboardEntry.fromDoc).toList();
    } catch (e) {
      debugPrint('LeaderboardService.fetchCity failed: $e');
      rethrow;
    }
  }

  static Future<List<LeaderboardEntry>> fetchByUids(List<String> uids) async {
    if (uids.isEmpty) return [];
    final results = <LeaderboardEntry>[];
    for (int i = 0; i < uids.length; i += 30) {
      final chunk = uids.sublist(i, min(i + 30, uids.length));
      final snap = await _db
          .collection('leaderboard')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      results.addAll(snap.docs.map(LeaderboardEntry.fromDoc));
    }
    results.sort((a, b) => b.points.compareTo(a.points));
    return results;
  }
}