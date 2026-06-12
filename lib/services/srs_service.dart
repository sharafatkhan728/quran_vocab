import 'package:shared_preferences/shared_preferences.dart';

/// Spaced Repetition System (SRS) service
/// Keys: srs_{word} = "stage|nextReview|points|deleted"
class SrsService {
  static const _pre = 'srs_';
  static const _pointsKey = 'srs_total_points';
  static const _sessionKey = 'srs_session';

  static const List<int> intervals = [1, 3, 7, 14, 30, 90, 180];

  // ── Card data ────────────────────────────────────────────────────────────

  static Future<SrsCard?> getCard(String arabic) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_pre$arabic');
    if (raw == null) return null;
    return SrsCard.fromRaw(arabic, raw);
  }

  static Future<void> saveCard(SrsCard card) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_pre${card.arabic}', card.toRaw());
  }

  static Future<void> initCard(String arabic) async {
    final existing = await getCard(arabic);
    if (existing != null) return;
    await saveCard(SrsCard(
      arabic: arabic,
      stage: 0,
      nextReview: DateTime.now(),
      points: 0,
      deleted: false,
    ));
  }

  /// Mark known — advance stage
  static Future<int> markKnown(String arabic) async {
    final prefs = await SharedPreferences.getInstance();
    final card = await getCard(arabic) ??
        SrsCard(
            arabic: arabic,
            stage: 0,
            nextReview: DateTime.now(),
            points: 0,
            deleted: false);
    final newStage = (card.stage + 1).clamp(0, intervals.length - 1);
    final days = intervals[newStage];
    final points = _pointsForStage(newStage);
    final updated = card.copyWith(
      stage: newStage,
      nextReview: DateTime.now().add(Duration(days: days)),
      points: card.points + points,
    );
    await saveCard(updated);
    // Add to total points
    final total = prefs.getInt(_pointsKey) ?? 0;
    await prefs.setInt(_pointsKey, total + points);
    return points;
  }

  /// Mark unknown — drop stage
  static Future<void> markUnknown(String arabic) async {
    final card = await getCard(arabic) ??
        SrsCard(
            arabic: arabic,
            stage: 0,
            nextReview: DateTime.now(),
            points: 0,
            deleted: false);
    final newStage = (card.stage - 1).clamp(0, intervals.length - 1);
    await saveCard(card.copyWith(
      stage: newStage,
      nextReview: DateTime.now().add(const Duration(hours: 4)),
    ));
  }

  static Future<void> deleteCard(String arabic) async {
    final card = await getCard(arabic);
    if (card != null) await saveCard(card.copyWith(deleted: true));
  }

  static int _pointsForStage(int stage) {
    const pts = [5, 10, 20, 30, 50, 80, 100];
    return pts[stage.clamp(0, pts.length - 1)];
  }

  // ── Points ────────────────────────────────────────────────────────────────

  static Future<int> getTotalPoints() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_pointsKey) ?? 0;
  }

  // ── Session ───────────────────────────────────────────────────────────────

  static Future<void> saveSession(List<String> remaining, int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, '$index|${remaining.join(",")}');
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
    return SrsSession(words: words, index: index);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  // ── Build session cards ───────────────────────────────────────────────────

  /// Returns ordered list of words for today's session
  static Future<List<String>> buildSession(
      List<String> allWords, int dailyGoal) async {
    final now = DateTime.now();
    final due = <String>[];
    final newCards = <String>[];

    for (final w in allWords) {
      final card = await getCard(w);
      if (card == null || card.deleted) continue;
      if (card.nextReview.isBefore(now)) {
        if (card.stage == 0) {
          newCards.add(w);
        } else {
          due.add(w);
        }
      }
    }

    newCards.shuffle();
    final todayNew = newCards.take(dailyGoal).toList();
    return [...due, ...todayNew];
  }
}

// ── Models ─────────────────────────────────────────────────────────────────

class SrsCard {
  final String arabic;
  final int stage;
  final DateTime nextReview;
  final int points;
  final bool deleted;

  SrsCard({
    required this.arabic,
    required this.stage,
    required this.nextReview,
    required this.points,
    required this.deleted,
  });

  factory SrsCard.fromRaw(String arabic, String raw) {
    final p = raw.split('|');
    return SrsCard(
      arabic: arabic,
      stage: int.tryParse(p[0]) ?? 0,
      nextReview: p.length > 1
          ? DateTime.tryParse(p[1]) ?? DateTime.now()
          : DateTime.now(),
      points: p.length > 2 ? int.tryParse(p[2]) ?? 0 : 0,
      deleted: p.length > 3 && p[3] == '1',
    );
  }

  String toRaw() =>
      '$stage|${nextReview.toIso8601String()}|$points|${deleted ? 1 : 0}';

  SrsCard copyWith({
    int? stage,
    DateTime? nextReview,
    int? points,
    bool? deleted,
  }) =>
      SrsCard(
        arabic: arabic,
        stage: stage ?? this.stage,
        nextReview: nextReview ?? this.nextReview,
        points: points ?? this.points,
        deleted: deleted ?? this.deleted,
      );
}

class SrsSession {
  final List<String> words;
  final int index;
  SrsSession({required this.words, required this.index});
}
