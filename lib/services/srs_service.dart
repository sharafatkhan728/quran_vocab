import '../database/database_manager.dart';
import '../repositories/srs_repository.dart';

export '../repositories/srs_repository.dart' show SrsCardRow;

const int kMaxReviewsPerSession = 30;
const int kNewWordBuffer = 20;

class SrsService {
  static const List<int> _intervals = [1, 2, 3, 5, 8, 13, 21, 34];
  static int _currentSession = 0;

  static Map<String, int>? _cleanToId;
  static Map<int, String>? _idToClean;

  static Future<void> _ensureVocabCache() async {
    if (_cleanToId != null) return;
    final db = await DatabaseManager.db;
    final rows = await db.query('vocab_words', columns: ['id', 'arabic_clean']);
    _cleanToId = {
      for (final r in rows) r['arabic_clean'] as String: r['id'] as int
    };
    _idToClean = {
      for (final r in rows) r['id'] as int: r['arabic_clean'] as String
    };
  }

  static void clearVocabCache() {
    _cleanToId = null;
    _idToClean = null;
  }

  // ── Session counter ───────────────────────────────────────────────────────

  static Future<int> startNewSession() async {
    _currentSession = await SrsRepository.startNewSession();
    return _currentSession;
  }

  static Future<int> getCurrentSession() async {
    _currentSession = await SrsRepository.getCurrentSession();
    return _currentSession;
  }

  // ── Card access ───────────────────────────────────────────────────────────

  static Future<SrsCardRow?> getCard(String normalizedArabic) async {
    await _ensureVocabCache();
    final id = _cleanToId![normalizedArabic];
    if (id == null) return null;
    return SrsRepository.getCard(id);
  }

  // ── Review actions ────────────────────────────────────────────────────────

  static Future<int> markKnown(String normalizedArabic) async {
    await _ensureVocabCache();
    final id = _cleanToId![normalizedArabic];
    if (id == null) return 0;
    final old = await SrsRepository.getCard(id) ?? _defaultCard(id);
    final newStage = (old.stage + 1).clamp(0, _intervals.length - 1);
    final newEase = (old.easeFactor + 0.1).clamp(1.3, 2.5);
    final pts = _points(newStage);
    await SrsRepository.upsertCard(SrsCardRow(
      vocabWordId: id,
      stage: newStage,
      // Known: schedule for future session using interval
      nextReviewSession: _currentSession + _intervals[newStage],
      easeFactor: newEase,
      failCount: old.failCount,
      totalReviews: old.totalReviews + 1,
      lastResult: 1,
      isDeleted: 0,
    ));
    await SrsRepository.addPoints(pts);
    return pts;
  }

  static Future<void> markUnknown(String normalizedArabic) async {
    await _ensureVocabCache();
    final id = _cleanToId![normalizedArabic];
    if (id == null) return;
    final old = await SrsRepository.getCard(id) ?? _defaultCard(id);
    await SrsRepository.upsertCard(SrsCardRow(
      vocabWordId: id,
      stage: (old.stage - 1).clamp(0, _intervals.length - 1),
      // Unknown: schedule for NEXT session (not current) — not shown immediately
      nextReviewSession: _currentSession + 1,
      easeFactor: (old.easeFactor - 0.2).clamp(1.3, 2.5),
      failCount: old.failCount + 1,
      totalReviews: old.totalReviews + 1,
      lastResult: 0,
      isDeleted: 0,
    ));
  }

  static Future<void> deleteCard(String normalizedArabic) async {
    await _ensureVocabCache();
    final id = _cleanToId![normalizedArabic];
    if (id == null) return;
    await SrsRepository.deleteCard(id);
  }

  // ── Points ────────────────────────────────────────────────────────────────

  static Future<int> getTotalPoints() => SrsRepository.getTotalPoints();
  static Future<void> recordNewCardReviewed() =>
      SrsRepository.recordWordLearned();

  // ── Session persistence ───────────────────────────────────────────────────

  static Future<void> saveSession(
      List<String> normalizedWords, int index) async {
    await _ensureVocabCache();
    final ids = normalizedWords
        .map((w) => _cleanToId![w])
        .whereType<int>()
        .toList();
    await SrsRepository.saveSavedSession(ids, index);
  }

  static Future<SrsSession?> loadSession() async {
    final saved = await SrsRepository.loadSavedSession();
    if (saved == null) return null;
    await _ensureVocabCache();
    final words = saved.ids
        .map((id) => _idToClean![id])
        .whereType<String>()
        .toList();
    if (words.isEmpty) return null;
    return SrsSession(words: words, index: saved.index);
  }

  static Future<void> clearSession() => SrsRepository.clearSavedSession();

  // ── Compatibility stubs ───────────────────────────────────────────────────

  static Future<bool> isInitialized() async => true;
  static Future<void> setInitialized() async {}
  static Future<void> initMissingCards(List<String> words) async {}
  static Future<void> initAllCards(List<String> words) async {}
  static Future<void> initCard(String word) async {}

  // ── Session building ──────────────────────────────────────────────────────
  //
  // Order: NEW words → DUE reviews → FAILED cards
  //
  // New words are shown first so users always learn something new each session
  // before tackling reviews. Reviews and failed cards follow.
  //
  // Unknown cards swiped during a session are reinserted randomly several
  // positions ahead in the SAME session list by the flashcard screen.
  // Their nextReviewSession is set to _currentSession + 1 so they appear
  // at higher priority in the NEXT session.

  static Future<SessionBuildResult> buildSession(int dailyGoal) async {
    _currentSession = await getCurrentSession();
    await _ensureVocabCache();

    final allCards = await SrsRepository.loadAllCards();

    // Classify existing cards
    final dueReviews = <_CP>[];
    final failedCards = <_CP>[];

    for (final entry in allCards.entries) {
      final card = entry.value;
      if (card.totalReviews == 0) continue; // unseen — handled as new

      if (card.stage > 0 && _currentSession >= card.nextReviewSession) {
        final overdue = _currentSession - card.nextReviewSession;
        dueReviews.add(_CP(entry.key, overdue * 10 + card.failCount));
      } else if (card.stage == 0 &&
          card.failCount > 0 &&
          _currentSession >= card.nextReviewSession) {
        failedCards.add(_CP(entry.key, card.failCount));
      }
    }

    dueReviews.sort((a, b) => b.priority.compareTo(a.priority));
    failedCards.sort((a, b) => b.priority.compareTo(a.priority));

    final cappedDue = dueReviews.take(kMaxReviewsPerSession).toList();
    final cappedFailed = failedCards
        .take((kMaxReviewsPerSession - cappedDue.length).clamp(0, kMaxReviewsPerSession))
        .toList();

    final reviewCount = cappedDue.length + cappedFailed.length;
    final newSlots = (dailyGoal - reviewCount).clamp(0, dailyGoal);

    // Fetch new words from SQLite — no Dart-side scan
    List<String> newWords = [];
    if (newSlots > 0) {
      newWords = await SrsRepository.fetchNextUnseenWords(
        limit: newSlots + kNewWordBuffer,
      );
      if (newWords.isNotEmpty) {
        final newIds = newWords
            .map((w) => _cleanToId![w])
            .whereType<int>()
            .toList();
        await SrsRepository.initMissingCards(newIds);
      }
    }

    final reviewWords = [
      ...cappedDue.map((c) => _idToClean![c.id]).whereType<String>(),
      ...cappedFailed.map((c) => _idToClean![c.id]).whereType<String>(),
    ];

    // Session order: NEW first, then reviews, then failed
    final takenNew = newWords.take(newSlots).toList();
    final session = [
      ...takenNew,
      ...reviewWords,
    ];

    // Deduplicate while preserving order
    final seen = <String>{};
    final deduped = session.where((w) => seen.add(w)).toList();

    return SessionBuildResult(
      words: deduped,
      overdueCount: cappedDue.length,
      failedCount: cappedFailed.length,
      newCount: takenNew.length,
      hasMoreNew: newWords.length > newSlots,
    );
  }

  static Future<SessionBuildResult> buildExtraSession(int batchSize) async {
    await _ensureVocabCache();
    final newWords = await SrsRepository.fetchNextUnseenWords(
      limit: batchSize + kNewWordBuffer,
    );
    if (newWords.isNotEmpty) {
      final newIds = newWords
          .map((w) => _cleanToId![w])
          .whereType<int>()
          .toList();
      await SrsRepository.initMissingCards(newIds);
    }
    final taken = newWords.take(batchSize).toList();
    return SessionBuildResult(
      words: taken,
      overdueCount: 0,
      failedCount: 0,
      newCount: taken.length,
      hasMoreNew: newWords.length > batchSize,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static SrsCardRow _defaultCard(int id) => SrsCardRow(
        vocabWordId: id,
        stage: 0,
        nextReviewSession: 0,
        easeFactor: 2.5,
        failCount: 0,
        totalReviews: 0,
        lastResult: -1,
        isDeleted: 0,
      );

  static int _points(int stage) {
    const pts = [5, 10, 20, 30, 50, 80, 100, 120];
    return pts[stage.clamp(0, pts.length - 1)];
  }
}

class _CP {
  final int id;
  final int priority;
  _CP(this.id, this.priority);
}

class SrsSession {
  final List<String> words;
  final int index;
  SrsSession({required this.words, required this.index});
}

class SessionBuildResult {
  final List<String> words;
  final int overdueCount;
  final int failedCount;
  final int newCount;
  final bool hasMoreNew;
  SessionBuildResult({
    required this.words,
    required this.overdueCount,
    required this.failedCount,
    required this.newCount,
    required this.hasMoreNew,
  });
  bool get isEmpty => words.isEmpty;
}

class SrsStats {
  final int due;
  final int learning;
  final int known;
  SrsStats({required this.due, required this.learning, required this.known});
}