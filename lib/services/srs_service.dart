import '../repositories/srs_repository.dart';
import '../repositories/vocabulary_repository.dart';

export '../repositories/srs_repository.dart' show SrsCardRow;

class SrsService {
  static const List<int> _intervalSessions = [1, 2, 3, 5, 8, 13, 21, 34];
  static int _currentSession = 0;

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
    final vocab =
        await VocabularyRepository.getByArabicClean(normalizedArabic);
    if (vocab == null) return null;
    return SrsRepository.getCard(vocab.id);
  }

  // ── Review actions ────────────────────────────────────────────────────────

  /// Mark as Known — advance stage, increase ease. Returns points earned.
  static Future<int> markKnown(String normalizedArabic) async {
    final vocab =
        await VocabularyRepository.getByArabicClean(normalizedArabic);
    if (vocab == null) return 0;
    final existing = await SrsRepository.getCard(vocab.id);
    final old = existing ??
        SrsCardRow(
          vocabWordId: vocab.id,
          stage: 0,
          nextReviewSession: 0,
          easeFactor: 2.5,
          failCount: 0,
          totalReviews: 0,
          lastResult: -1,
          isDeleted: 0,
        );
    final newStage =
        (old.stage + 1).clamp(0, _intervalSessions.length - 1);
    final newEase = (old.easeFactor + 0.1).clamp(1.3, 2.5);
    final pts = _pointsForStage(newStage);
    await SrsRepository.upsertCard(SrsCardRow(
      vocabWordId: vocab.id,
      stage: newStage,
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

  /// Mark as Unknown — drop stage, schedule sooner.
  static Future<void> markUnknown(String normalizedArabic) async {
    final vocab =
        await VocabularyRepository.getByArabicClean(normalizedArabic);
    if (vocab == null) return;
    final existing = await SrsRepository.getCard(vocab.id);
    final old = existing ??
        SrsCardRow(
          vocabWordId: vocab.id,
          stage: 0,
          nextReviewSession: 0,
          easeFactor: 2.5,
          failCount: 0,
          totalReviews: 0,
          lastResult: -1,
          isDeleted: 0,
        );
    await SrsRepository.upsertCard(SrsCardRow(
      vocabWordId: vocab.id,
      stage: (old.stage - 2).clamp(0, _intervalSessions.length - 1),
      nextReviewSession: _currentSession + 1,
      easeFactor: (old.easeFactor - 0.2).clamp(1.3, 2.5),
      failCount: old.failCount + 1,
      totalReviews: old.totalReviews + 1,
      lastResult: 0,
      isDeleted: 0,
    ));
  }

  /// Soft-delete a card (hidden from future sessions).
  static Future<void> deleteCard(String normalizedArabic) async {
    final vocab =
        await VocabularyRepository.getByArabicClean(normalizedArabic);
    if (vocab == null) return;
    await SrsRepository.deleteCard(vocab.id);
  }

  // ── Points ────────────────────────────────────────────────────────────────

  static Future<int> getTotalPoints() => SrsRepository.getTotalPoints();

  static Future<void> recordNewCardReviewed() =>
      SrsRepository.recordWordLearned();

  // ── Session persistence ───────────────────────────────────────────────────

  static Future<void> saveSession(
      List<String> normalizedWords, int index) async {
    final ids = await _wordsToIds(normalizedWords);
    await SrsRepository.saveSavedSession(ids, index);
  }

  static Future<SrsSession?> loadSession() async {
    final saved = await SrsRepository.loadSavedSession();
    if (saved == null) return null;
    final words = await _idsToWords(saved.ids);
    if (words.isEmpty) return null;
    return SrsSession(words: words, index: saved.index);
  }

  static Future<void> clearSession() => SrsRepository.clearSavedSession();

  // ── Card initialisation ───────────────────────────────────────────────────

  static Future<void> initMissingCards(List<String> words) async {
    final ids = await _wordsToIds(words);
    await SrsRepository.initMissingCards(ids);
  }

  static Future<void> initAllCards(List<String> words) =>
      initMissingCards(words);

  // ── Session building ──────────────────────────────────────────────────────

  static Future<SessionBuildResult> buildSession(
    List<String> allWords,
    int dailyGoal,
  ) async {
    _currentSession = await getCurrentSession();
    final vocabIds = await _wordsToIds(allWords);
    await SrsRepository.initMissingCards(vocabIds);
    final allCards = await SrsRepository.loadAllCards();

    final overdueReviews = <_CardWithPriority>[];
    final failedCards = <_CardWithPriority>[];
    final newCards = <_CardWithPriority>[];

    for (int i = 0; i < allWords.length; i++) {
      final word = allWords[i];
      final vocab = await VocabularyRepository.getByArabicClean(word);
      if (vocab == null) continue;
      final card = allCards[vocab.id] ??
          SrsCardRow(
            vocabWordId: vocab.id,
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
      } else if (card.totalReviews == 0) {
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
      List<String> allWords, int batchSize) async {
    final allCards = await SrsRepository.loadAllCards();
    final unseen = <String>[];
    for (final word in allWords) {
      final vocab = await VocabularyRepository.getByArabicClean(word);
      if (vocab == null) continue;
      final card = allCards[vocab.id];
      if (card == null || card.totalReviews == 0) {
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

  // ── Compatibility stubs ───────────────────────────────────────────────────

  static Future<bool> isInitialized() async => true;
  static Future<void> setInitialized() async {}

  // ── Private helpers ───────────────────────────────────────────────────────

  static int _pointsForStage(int stage) {
    const pts = [5, 10, 20, 30, 50, 80, 100, 120];
    return pts[stage.clamp(0, pts.length - 1)];
  }

  static Future<List<int>> _wordsToIds(List<String> words) async {
    final ids = <int>[];
    for (final w in words) {
      final vocab = await VocabularyRepository.getByArabicClean(w);
      if (vocab != null) ids.add(vocab.id);
    }
    return ids;
  }

  static Future<List<String>> _idsToWords(List<int> ids) async {
    final words = <String>[];
    for (final id in ids) {
      final vocab = await VocabularyRepository.getById(id);
      if (vocab != null) words.add(vocab.arabicClean);
    }
    return words;
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