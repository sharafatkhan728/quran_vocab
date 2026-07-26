import 'package:shared_preferences/shared_preferences.dart';
import 'database_manager.dart';
import 'package:sqflite/sqflite.dart';

class MigrationManager {
  static Future<void> migrateIfNeeded() async {
    final db = await DatabaseManager.db;

    // Check if content import is complete — if not, skip user migration
    // because vocab_words table may be empty and lookups would fail
    final contentRows = await db.query('db_meta',
        where: 'key = ?', whereArgs: ['content_version']);
    if (contentRows.isEmpty) {
      // Content not imported yet — migration will run after import completes
      return;
    }

    final metaRows = await db.query('user_meta',
        where: 'key = ?', whereArgs: ['migration_v1_completed']);
    if (metaRows.isNotEmpty) return; // already done

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Build vocab lookup once: arabic_clean → vocab_word_id
    final vocabRows = await db.query('vocab_words',
        columns: ['id', 'arabic_clean']);
    final vocabMap = <String, int>{
      for (final r in vocabRows)
        r['arabic_clean'] as String: r['id'] as int
    };

    // ── Known words ─────────────────────────────────────────────────────────
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('known_word_')) continue;
      final clean = key.replaceFirst('known_word_', '');
      final vocabId = vocabMap[clean];
      if (vocabId == null) continue;
      await db.insert('known_words', {
        'vocab_word_id': vocabId,
        'marked_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // ── SRS cards ────────────────────────────────────────────────────────────
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('srs_')) continue;
      if (!_isSrsCardKey(key)) continue;
      final clean = key.replaceFirst('srs_', '');
      final vocabId = vocabMap[clean];
      if (vocabId == null) continue;
      final raw = prefs.getString(key) ?? '';
      final parts = raw.split('|');
      await db.insert('srs_cards', {
        'vocab_word_id': vocabId,
        'stage': int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0,
        'next_review_session': int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
        'ease_factor': double.tryParse(parts.elementAtOrNull(2) ?? '') ?? 2.5,
        'fail_count': int.tryParse(parts.elementAtOrNull(3) ?? '') ?? 0,
        'total_reviews': int.tryParse(parts.elementAtOrNull(4) ?? '') ?? 0,
        'last_result': int.tryParse(parts.elementAtOrNull(5) ?? '') ?? -1,
        'is_deleted': 0,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // ── Reading progress ─────────────────────────────────────────────────────
    for (int i = 1; i <= 114; i++) {
      final ayah = prefs.getInt('last_read_$i') ?? 0;
      if (ayah > 0) {
        await db.insert('reading_progress', {
          'surah_id': i,
          'last_ayah': ayah,
          'last_read_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    // ── Bookmarks ────────────────────────────────────────────────────────────
    final bookmarkList = prefs.getStringList('bookmarks') ?? [];
    for (final b in bookmarkList) {
      final parts = b.split(':');
      if (parts.length < 2) continue;
      final surahId = int.tryParse(parts[0]);
      final ayahNum = int.tryParse(parts[1]);
      if (surahId == null || ayahNum == null) continue;
      await db.insert('bookmarks', {
        'surah_id': surahId,
        'ayah_number': ayahNum,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // ── Daily stats ──────────────────────────────────────────────────────────
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('daily_')) continue;
      final dateKey = key.replaceFirst('daily_', '');
      final count = prefs.getInt(key) ?? 0;
      if (count > 0) {
        await db.insert('daily_stats', {
          'date_key': dateKey,
          'words_learned': count,
          'sessions': 0,
          'points': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    // ── User meta ────────────────────────────────────────────────────────────
    final pts = prefs.getInt('srs_total_points') ?? 0;
    final streak = prefs.getInt('longest_streak') ?? 0;
    final sessions = prefs.getInt('srs_total_sessions') ?? 0;
    for (final entry in {
      'srs_total_points': '$pts',
      'longest_streak': '$streak',
      'srs_total_sessions': '$sessions',
    }.entries) {
      await db.insert('user_meta', {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Mark complete
    await db.insert('user_meta',
        {'key': 'migration_v1_completed', 'value': 'true'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Inline card key check to avoid importing SrsService here
  static bool _isSrsCardKey(String key) =>
      key.startsWith('srs_') &&
      key != 'srs_total_points' &&
      key != 'srs_initialized' &&
      key != 'srs_session_v2' &&
      key != 'srs_today_new' &&
      key != 'srs_total_sessions';
}