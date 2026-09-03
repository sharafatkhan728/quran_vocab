import '../database/database_manager.dart';
import '../repositories/srs_repository.dart';

export '../repositories/srs_repository.dart' show SrsCardRow;

class SrsService {
  static const List<int> _intervalSessions = [1, 2, 3, 5, 8, 13, 21, 34];
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
    // Do not process deleted cards — they should not be re-added to SRS
    if (await SrsRepository.isCardDeleted(id)) return 0;
    final old = await SrsRepository.getCard(id) ??
        SrsCardRow(
          vocabWordId: id,
          stage: 0,
          nextReviewSession: 0,
          easeFactor: 2.5,
          failCount: 0,
          totalReviews: 0,
          lastResult: -1,
          isDeleted: 0,
        );
    final newStage = (old.stage + 1).clamp(0, _intervalSessions.length - 1);
    final newEase = (old.easeFactor + 0.1).clamp(1.3, 2.5);
    final pts = _pointsForStage(newStage);
    await SrsRepository.upsertCard(SrsCardRow(
      vocabWordId: id,
      stage: newStage,
      // Known: schedule for future session using interval
      nextReviewSession: _currentSession + _intervalSessions[newStage],
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
    // Do not process deleted cards
    if (await SrsRepository.isCardDeleted(id)) return;
    final old = await SrsRepository.getCard(id) ??
        SrsCardRow(
          vocabWordId: id,
          stage: 0,
          nextReviewSession: 0,
          easeFactor: 2.5,
          failCount: 0,
          totalReviews: 0,
          lastResult: -1,
          isDeleted: 0,
        );
    await SrsRepository.upsertCard(SrsCardRow(
      vocabWordId: id,
      stage: (old.stage - 2).clamp(0, _intervalSessions.length - 1),
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

  // ── Card initialisation ───────────────────────────────────────────────────

  static Future<void> initMissingCards(List<String> words) async {
    final ids = await _wordsToIds(words);
    await SrsRepository.initMissingCards(ids);
  }

  static Future<void> initAllCards(List<String> words) =>
      initMissingCards(words);

  // ── Session building ──────────────────────────────────────────────────────
  //
  // Priority order: OVERDUE REVIEWS → FAILED cards → NEW words
  //
  // Overdue reviews take full priority so users never miss cards that are due.
  // Failed cards (stage 0, failCount > 0, due) are shown next.
  // New words fill remaining slots up to dailyGoal.

  static Future<SessionBuildResult> buildSession(
    List<String> allWords,
    int dailyGoal, {
    Set<String> knownCleans = const {},
  }) async {
    _currentSession = await getCurrentSession();

    // Load vocab cache once — replaces N sequential getByArabicClean calls
    await _ensureVocabCache();
    final cleanToId = _cleanToId!;

    // Map words → ids entirely in memory (zero DB queries)
    final vocabIds = <int>[];
    for (final w in allWords) {
      final id = cleanToId[w];
      if (id != null) vocabIds.add(id);
    }

    // One bulk query — insert any missing card rows
    await SrsRepository.initMissingCards(vocabIds);

    // One query — load all cards into memory
    final allCards = await SrsRepository.loadAllCards();

    // One query — load deleted card ids so we never reconstruct them as "new"
    final deletedIds = await SrsRepository.getDeletedCardIds();

    final overdueReviews = <_CardWithPriority>[];
    final failedCards = <_CardWithPriority>[];
    final newCards = <_CardWithPriority>[];

    for (int i = 0; i < allWords.length; i++) {
      final word = allWords[i];
      final id = cleanToId[word];
      if (id == null || deletedIds.contains(id)) continue;

      final card = allCards[id] ??
          SrsCardRow(
            vocabWordId: id,
            stage: 0,
            nextReviewSession: 0,
            easeFactor: 2.5,
            failCount: 0,
            totalReviews: 0,
            lastResult: -1,
            isDeleted: 0,
          );

      if (card.stage > 0 && card.totalReviews > 0) {
        if (_currentSession >= card.nextReviewSession) {
          final overdue = _currentSession - card.nextReviewSession;
          overdueReviews
              .add(_CardWithPriority(word, overdue * 10 + card.failCount));
        }
      } else if (card.stage == 0 &&
          card.failCount > 0 &&
          _currentSession >= card.nextReviewSession) {
        failedCards.add(_CardWithPriority(word, card.failCount));
      } else if (card.totalReviews == 0 && !knownCleans.contains(word)) {
        newCards.add(_CardWithPriority(word, -i));
      }
    }

    overdueReviews.sort((a, b) => b.priority.compareTo(a.priority));
    failedCards.sort((a, b) => b.priority.compareTo(a.priority));
    newCards.sort((a, b) => b.priority.compareTo(a.priority));

    final session = [
      ...overdueReviews.map((c) => c.word),
      ...failedCards.map((c) => c.word),
      ...newCards.take(dailyGoal).map((c) => c.word),
    ];

    return SessionBuildResult(
      words: session,
      overdueCount: overdueReviews.length,
      failedCount: failedCards.length,
      newCount: newCards.take(dailyGoal).length,
      hasMoreNew: newCards.length > dailyGoal,
    );
  }

  static Future<SessionBuildResult> buildExtraSession(
      List<String> allWords, int batchSize,
      {Set<String> knownCleans = const {}}) async {
    await _ensureVocabCache();
    final cleanToId = _cleanToId!;
    final allCards = await SrsRepository.loadAllCards();
    final unseen = <String>[];
    for (final word in allWords) {
      final id = cleanToId[word];
      if (id == null) continue;
      final card = allCards[id];
      if (card == null || card.totalReviews == 0) {
        if (knownCleans.contains(word)) continue;
        unseen.add(word);
        if (unseen.length >= batchSize) break;
      }
    }
    return SessionBuildResult(
      words: unseen,
      overdueCount: 0,
      failedCount: 0,
      newCount: unseen.length,
      hasMoreNew: false,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static int _pointsForStage(int stage) {
    const pts = [5, 10, 20, 30, 50, 80, 100, 120];
    return pts[stage.clamp(0, pts.length - 1)];
  }

  /// arabic_clean strings → vocab_word_ids using in-memory cache.
  /// Zero DB queries after first call.
  static Future<List<int>> _wordsToIds(List<String> words) async {
    await _ensureVocabCache();
    final ids = <int>[];
    for (final w in words) {
      final id = _cleanToId![w];
      if (id != null) ids.add(id);
    }
    return ids;
  }

}

// ── Supporting models ─────────────────────────────────────────────────────────

class _CardWithPriority {
  final String word;
  final int priority;
  _CardWithPriority(this.word, this.priority);
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