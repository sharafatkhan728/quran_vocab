import 'package:sqflite/sqflite.dart';
import '../database/database_manager.dart';

class SrsCardRow {
  final int vocabWordId;
  final int stage;
  final int nextReviewSession;
  final double easeFactor;
  final int failCount;
  final int totalReviews;
  final int lastResult;
  final int isDeleted;

  const SrsCardRow({
    required this.vocabWordId,
    required this.stage,
    required this.nextReviewSession,
    required this.easeFactor,
    required this.failCount,
    required this.totalReviews,
    required this.lastResult,
    required this.isDeleted,
  });

  factory SrsCardRow.fromMap(Map<String, dynamic> m) => SrsCardRow(
        vocabWordId: m['vocab_word_id'] as int,
        stage: m['stage'] as int? ?? 0,
        nextReviewSession: m['next_review_session'] as int? ?? 0,
        easeFactor: (m['ease_factor'] as num?)?.toDouble() ?? 2.5,
        failCount: m['fail_count'] as int? ?? 0,
        totalReviews: m['total_reviews'] as int? ?? 0,
        lastResult: m['last_result'] as int? ?? -1,
        isDeleted: m['is_deleted'] as int? ?? 0,
      );

  bool get isNew => totalReviews == 0;
  bool get isFailed => failCount > 0 && stage == 0;
}

class SrsRepository {
  static Future<SrsCardRow?> getCard(int vocabWordId) async {
    final db = await DatabaseManager.db;
    final rows = await db.query('srs_cards',
        where: 'vocab_word_id = ?', whereArgs: [vocabWordId], limit: 1);
    if (rows.isEmpty) return null;
    return SrsCardRow.fromMap(rows.first);
  }

  static Future<void> upsertCard(SrsCardRow card) async {
    final db = await DatabaseManager.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
        'srs_cards',
        {
          'vocab_word_id': card.vocabWordId,
          'stage': card.stage,
          'next_review_session': card.nextReviewSession,
          'ease_factor': card.easeFactor,
          'fail_count': card.failCount,
          'total_reviews': card.totalReviews,
          'last_result': card.lastResult,
          'is_deleted': card.isDeleted,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> initMissingCards(List<int> vocabWordIds) async {
    if (vocabWordIds.isEmpty) return;
    final db = await DatabaseManager.db;
    // Only fetch ids that already exist — avoids loading all cards
    final placeholders = vocabWordIds.map((_) => '?').join(',');
    final existing = await db.rawQuery(
        'SELECT vocab_word_id FROM srs_cards WHERE vocab_word_id IN ($placeholders)',
        vocabWordIds);
    final existingIds = existing.map((r) => r['vocab_word_id'] as int).toSet();
    final now = DateTime.now().millisecondsSinceEpoch;
    const batchSize = 300;
    var batch = db.batch();
    int count = 0;
    for (final id in vocabWordIds) {
      if (existingIds.contains(id)) continue;
      batch.insert(
          'srs_cards',
          {
            'vocab_word_id': id,
            'stage': 0,
            'next_review_session': 0,
            'ease_factor': 2.5,
            'fail_count': 0,
            'total_reviews': 0,
            'last_result': -1,
            'is_deleted': 0,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      count++;
      if (count % batchSize == 0) {
        await batch.commit(noResult: true);
        batch = db.batch();
      }
    }
    await batch.commit(noResult: true);
  }

  // Loads only non-deleted cards — one query
  static Future<Map<int, SrsCardRow>> loadAllCards() async {
    final db = await DatabaseManager.db;
    final rows =
        await db.query('srs_cards', where: 'is_deleted = 0 OR is_deleted IS NULL');
    return {
      for (final r in rows) (r['vocab_word_id'] as int): SrsCardRow.fromMap(r)
    };
  }

  static Future<int> getTotalPoints() async {
    final db = await DatabaseManager.db;
    final rows = await db.query('user_meta',
        where: 'key = ?', whereArgs: ['srs_total_points'], limit: 1);
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String) ?? 0;
  }

  static Future<void> addPoints(int pts) async {
    final current = await getTotalPoints();
    final db = await DatabaseManager.db;
    await db.insert('user_meta',
        {'key': 'srs_total_points', 'value': '${current + pts}'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> getCurrentSession() async {
    final db = await DatabaseManager.db;
    final rows = await db.query('user_meta',
        where: 'key = ?', whereArgs: ['srs_total_sessions'], limit: 1);
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String) ?? 0;
  }

  static Future<int> startNewSession() async {
    final current = await getCurrentSession();
    final next = current + 1;
    final db = await DatabaseManager.db;
    await db.insert('user_meta',
        {'key': 'srs_total_sessions', 'value': '$next'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return next;
  }

  static Future<void> deleteCard(int vocabWordId) async {
    final db = await DatabaseManager.db;
    await db.update(
      'srs_cards',
      {'is_deleted': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'vocab_word_id = ?',
      whereArgs: [vocabWordId],
    );
  }

  static Future<void> saveSavedSession(
      List<int> vocabWordIds, int index) async {
    final db = await DatabaseManager.db;
    await db.insert('user_meta',
        {'key': 'srs_session_v2', 'value': '$index|${vocabWordIds.join(",")}'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<({List<int> ids, int index})?> loadSavedSession() async {
    final db = await DatabaseManager.db;
    final rows = await db.query('user_meta',
        where: 'key = ?', whereArgs: ['srs_session_v2'], limit: 1);
    if (rows.isEmpty) return null;
    final raw = rows.first['value'] as String;
    final pipe = raw.indexOf('|');
    if (pipe < 0) return null;
    final index = int.tryParse(raw.substring(0, pipe)) ?? 0;
    final ids = raw
        .substring(pipe + 1)
        .split(',')
        .where((s) => s.isNotEmpty)
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .toList();
    if (ids.isEmpty) return null;
    return (ids: ids, index: index);
  }

  static Future<void> clearSavedSession() async {
    final db = await DatabaseManager.db;
    await db
        .delete('user_meta', where: 'key = ?', whereArgs: ['srs_session_v2']);
  }

  static Future<void> recordWordLearned() async {
    final today = _todayKey();
    final db = await DatabaseManager.db;
    await db.execute('''
      INSERT INTO daily_stats(date_key, words_learned, sessions, points)
      VALUES(?, 1, 0, 0)
      ON CONFLICT(date_key) DO UPDATE
      SET words_learned = words_learned + 1
    ''', [today]);
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Fetches next unseen words via LEFT JOIN — no Dart-side 15K scan.
  /// Uses srs_cards absence as the "unseen" signal.
  static Future<List<String>> fetchNextUnseenWords({
    required int limit,
  }) async {
    final db = await DatabaseManager.db;
    final rows = await db.rawQuery('''
      SELECT v.arabic_clean
      FROM vocab_words v
      LEFT JOIN srs_cards s ON s.vocab_word_id = v.id
      WHERE (s.vocab_word_id IS NULL OR s.is_deleted = 0 AND s.total_reviews = 0)
        AND v.frequency > 0
        AND v.meaning_ur != ''
      ORDER BY v.frequency DESC
      LIMIT ?
    ''', [limit]);
    return rows.map((r) => r['arabic_clean'] as String).toList();
  }
}