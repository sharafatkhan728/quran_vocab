import 'package:shared_preferences/shared_preferences.dart';
import 'sync_service.dart';

/// Spaced Repetition System — SM-2 variant
/// Card data stored as: srs_{word} = "stage|nextReview|easeFactor|failCount|totalReviews|lastResult"
class SrsService {
  static const _pre = 'srs_';
  static const _pointsKey = 'srs_total_points';
  static const _srsInitializedKey = 'srs_initialized';
  static const _sessionKey = 'srs_session_v2';
  static const _todayNewKey = 'srs_today_new';
  static const _todayDateKey = 'srs_today_date';

  // SM-2 intervals in days by stage
  static const List<int> _intervals = [1, 3, 7, 14, 30, 90, 180, 365];

  // ── Card CRUD ─────────────────────────────────────────────────────────────

  static Future<SrsCard?> getCard(String word) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_pre$word');
    if (raw == null) return null;
    return SrsCard.fromRaw(word, raw);
  }

  static Future<void> saveCard(SrsCard card) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_pre${card.word}', card.toRaw());
  }

  static Future<void> initCard(String word) async {
    final existing = await getCard(word);
    if (existing != null) return;
    await saveCard(SrsCard.newCard(word));
  }

  /// Initialize SRS cards for a list of words in one bulk pass.
  /// Much faster than calling initCard() in a loop.
  static Future<void> initAllCards(List<String> words) async {
    final prefs = await SharedPreferences.getInstance();
    final existingKeys = prefs.getKeys();
    for (final word in words) {
      final key = '$_pre$word';
      if (!existingKeys.contains(key)) {
        await prefs.setString(key, SrsCard.newCard(word).toRaw());
      }
    }
  }

  // ── Review actions ────────────────────────────────────────────────────────

  /// Mark as Known — advance stage, increase ease
  static Future<int> markKnown(String word) async {
    final prefs = await SharedPreferences.getInstance();
    final card = await getCard(word) ?? SrsCard.newCard(word);

    final newStage = (card.stage + 1).clamp(0, _intervals.length - 1);
    final days = _intervals[newStage];
    // Ease factor increases slightly on success
    final newEase = (card.easeFactor + 0.1).clamp(1.3, 2.5);
    final pts = _pointsForStage(newStage);

    final updated = card.copyWith(
      stage: newStage,
      nextReview: DateTime.now().add(Duration(days: days)),
      easeFactor: newEase,
      totalReviews: card.totalReviews + 1,
      lastResult: 1,
    );
    await saveCard(updated);

    // Add points
    final total = prefs.getInt(_pointsKey) ?? 0;
    await prefs.setInt(_pointsKey, total + pts);
    SyncService.scheduleSyncUp();
    return pts;
  }

  /// Mark as Unknown — reset stage, schedule for tomorrow, high priority
  static Future<void> markUnknown(String word) async {
    final card = await getCard(word) ?? SrsCard.newCard(word);

    // Drop stage (min 0), reduce ease factor
    final newStage = (card.stage - 2).clamp(0, _intervals.length - 1);
    final newEase = (card.easeFactor - 0.2).clamp(1.3, 2.5);

    final updated = card.copyWith(
      stage: newStage,
      // Due tomorrow but also gets re-inserted in same session
      nextReview: DateTime.now().add(const Duration(days: 1)),
      easeFactor: newEase,
      failCount: card.failCount + 1,
      totalReviews: card.totalReviews + 1,
      lastResult: 0,
    );
    await saveCard(updated);
    SyncService.scheduleSyncUp();
  }

  static Future<bool> isInitialized() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_srsInitializedKey) ?? false;
  }

  static Future<void> setInitialized() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_srsInitializedKey, true);
  }

  static Future<void> deleteCard(String word) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('deleted_$word', true);
  }

  static Future<bool> isDeleted(String word) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('deleted_$word') ?? false;
  }

  static int _pointsForStage(int stage) {
    const pts = [5, 10, 20, 30, 50, 80, 100, 120];
    return pts[stage.clamp(0, pts.length - 1)];
  }

  // ── Session building ──────────────────────────────────────────────────────

  /// Load ALL srs cards in one pass from SharedPreferences.
  /// Returns a map of word → SrsCard for fast O(1) lookup.
  static Future<Map<String, SrsCard>> _loadAllCards(
      SharedPreferences prefs) async {
    final result = <String, SrsCard>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_pre)) {
        continue;
      }
      // Skip non-card keys
      if (key == _pointsKey ||
          key == _srsInitializedKey ||
          key == _sessionKey ||
          key == _todayNewKey ||
          key == _todayDateKey) {
        continue;
      }
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final word = key.substring(_pre.length);
      result[word] = SrsCard.fromRaw(word, raw);
    }
    return result;
  }

  /// Build today's session with correct priority order:
  /// 1. Overdue reviews (stage > 0, past due date) — highest priority
  /// 2. Failed cards from recent sessions (failCount > 0, stage == 0)
  /// 3. New cards (never reviewed) — limited by dailyGoal
  static Future<SessionBuildResult> buildSession(
    List<String> allWords,
    int dailyGoal,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month}-${now.day}';

    // Reset daily new count if new day
    final savedDate = prefs.getString(_todayDateKey);
    if (savedDate != todayStr) {
      await prefs.setString(_todayDateKey, todayStr);
      await prefs.setInt(_todayNewKey, 0);
    }
    final todayNewCount = prefs.getInt(_todayNewKey) ?? 0;
    final remainingNew = (dailyGoal - todayNewCount).clamp(0, dailyGoal);

    // ── Single bulk read — replaces per-word await getCard() ─────────────
    final allCards = await _loadAllCards(prefs);
    final deletedKeys =
        prefs.getKeys().where((k) => k.startsWith('deleted_')).toSet();

    final overdueReviews = <_CardWithPriority>[];
    final failedCards = <_CardWithPriority>[];
    final newCards = <_CardWithPriority>[];

    for (final word in allWords) {
      if (deletedKeys.contains('deleted_$word')) continue;
      final card = allCards[word];
      if (card == null) continue;

      if (card.stage > 0 && !card.nextReview.isAfter(now)) {
        final daysOverdue = now.difference(card.nextReview).inDays;
        overdueReviews
            .add(_CardWithPriority(word, daysOverdue * 10 + card.failCount));
      } else if (card.stage == 0 &&
          card.failCount > 0 &&
          !card.nextReview.isAfter(now)) {
        failedCards.add(_CardWithPriority(word, card.failCount));
      } else if (card.stage == 0 &&
          card.failCount == 0 &&
          card.totalReviews == 0) {
        newCards.add(_CardWithPriority(word, 0));
      }
    }

    overdueReviews.sort((a, b) => b.priority.compareTo(a.priority));
    failedCards.sort((a, b) => b.priority.compareTo(a.priority));

    final session = <String>[
      ...overdueReviews.map((c) => c.word),
      ...failedCards.map((c) => c.word),
      ...newCards.take(remainingNew).map((c) => c.word),
    ];

    return SessionBuildResult(
      words: session,
      overdueCount: overdueReviews.length,
      failedCount: failedCards.length,
      newCount: newCards.take(remainingNew).length,
      hasMoreNew: newCards.length > remainingNew,
    );
  }

  /// Build extra session (user confirmed warning)
  static Future<SessionBuildResult> buildExtraSession(
    List<String> allWords,
    int batchSize,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    // ── Single bulk read ──────────────────────────────────────────────────
    final allCards = await _loadAllCards(prefs);
    final deletedKeys =
        prefs.getKeys().where((k) => k.startsWith('deleted_')).toSet();

    final unseen = <String>[];
    for (final word in allWords) {
      if (deletedKeys.contains('deleted_$word')) continue;
      final card = allCards[word];
      if (card != null && card.totalReviews == 0) {
        unseen.add(word);
        if (unseen.length >= batchSize) break;
      }
    }

    final todayNew = prefs.getInt(_todayNewKey) ?? 0;
    await prefs.setInt(_todayNewKey, todayNew + unseen.length);

    return SessionBuildResult(
      words: unseen,
      overdueCount: 0,
      failedCount: 0,
      newCount: unseen.length,
      hasMoreNew: false,
    );
  }

  /// Call after marking a card known/unknown to update daily new count
  static Future<void> recordNewCardReviewed() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_todayNewKey) ?? 0;
    await prefs.setInt(_todayNewKey, count + 1);
  }

  // ── Points ────────────────────────────────────────────────────────────────

  static Future<int> getTotalPoints() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_pointsKey) ?? 0;
  }

  // ── Session persistence ───────────────────────────────────────────────────

  static Future<void> saveSession(List<String> words, int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, '$index|${words.join(",")}');
  }

  static Future<SrsSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    final pipe = raw.indexOf('|');
    if (pipe < 0) return null;
    final index = int.tryParse(raw.substring(0, pipe)) ?? 0;
    final words =
        raw.substring(pipe + 1).split(',').where((s) => s.isNotEmpty).toList();
    if (words.isEmpty) return null;
    return SrsSession(words: words, index: index);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  static Future<SrsStats> getStats() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    int due = 0, learning = 0, known = 0;

    final keys = prefs.getKeys().where((k) => k.startsWith(_pre));
    for (final key in keys) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final word = key.substring(_pre.length);
      final card = SrsCard.fromRaw(word, raw);
      if (card.stage == 0) {
        learning++;
      } else if (!card.nextReview.isAfter(now)) {
        due++;
      } else {
        known++;
      }
    }
    return SrsStats(due: due, learning: learning, known: known);
  }
}

// ── Models ─────────────────────────────────────────────────────────────────

class SrsCard {
  final String word;
  final int stage;
  final DateTime nextReview;
  final double easeFactor;
  final int failCount;
  final int totalReviews;
  final int lastResult; // 0=fail 1=pass

  SrsCard({
    required this.word,
    required this.stage,
    required this.nextReview,
    required this.easeFactor,
    required this.failCount,
    required this.totalReviews,
    required this.lastResult,
  });

  factory SrsCard.newCard(String word) => SrsCard(
        word: word,
        stage: 0,
        nextReview: DateTime.now(),
        easeFactor: 2.5,
        failCount: 0,
        totalReviews: 0,
        lastResult: -1,
      );

  factory SrsCard.fromRaw(String word, String raw) {
    final p = raw.split('|');
    return SrsCard(
      word: word,
      stage: int.tryParse(p.elementAtOrNull(0) ?? '') ?? 0,
      nextReview:
          DateTime.tryParse(p.elementAtOrNull(1) ?? '') ?? DateTime.now(),
      easeFactor: double.tryParse(p.elementAtOrNull(2) ?? '') ?? 2.5,
      failCount: int.tryParse(p.elementAtOrNull(3) ?? '') ?? 0,
      totalReviews: int.tryParse(p.elementAtOrNull(4) ?? '') ?? 0,
      lastResult: int.tryParse(p.elementAtOrNull(5) ?? '') ?? -1,
    );
  }

  String toRaw() =>
      '$stage|${nextReview.toIso8601String()}|$easeFactor|$failCount|$totalReviews|$lastResult';

  SrsCard copyWith({
    int? stage,
    DateTime? nextReview,
    double? easeFactor,
    int? failCount,
    int? totalReviews,
    int? lastResult,
  }) =>
      SrsCard(
        word: word,
        stage: stage ?? this.stage,
        nextReview: nextReview ?? this.nextReview,
        easeFactor: easeFactor ?? this.easeFactor,
        failCount: failCount ?? this.failCount,
        totalReviews: totalReviews ?? this.totalReviews,
        lastResult: lastResult ?? this.lastResult,
      );

  bool get isDue => nextReview.isBefore(DateTime.now());
  bool get isNew => totalReviews == 0;
  bool get isFailed => failCount > 0 && stage == 0;
}

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
