import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper around Firebase Analytics — all screen-view and event
/// logging goes through here so call sites stay simple and any future
/// change (e.g. disabling analytics for a user who opts out) has one place
/// to change.
class AnalyticsService {
  AnalyticsService._();

  static final FirebaseAnalytics instance = FirebaseAnalytics.instance;

  static FirebaseAnalyticsObserver get navigatorObserver =>
      FirebaseAnalyticsObserver(analytics: instance);

  static Future<void> logScreenView(String screenName) async {
    try {
      await instance.logScreenView(screenName: screenName);
    } catch (e) {
      debugPrint('AnalyticsService.logScreenView failed: $e');
    }
  }

  static Future<void> logEvent(String name,
      {Map<String, Object>? parameters}) async {
    try {
      await instance.logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint('AnalyticsService.logEvent failed: $e');
    }
  }

  // ── Common app-specific events ────────────────────────────────────────────

  static Future<void> logWordMarkedKnown({required String source}) =>
      logEvent('word_marked_known', parameters: {'source': source});

  static Future<void> logWordMarkedUnknown({required String source}) =>
      logEvent('word_marked_unknown', parameters: {'source': source});

  static Future<void> logFlashcardSessionCompleted(
          {required int cardsReviewed, required int pointsEarned}) =>
      logEvent('flashcard_session_completed', parameters: {
        'cards_reviewed': cardsReviewed,
        'points_earned': pointsEarned,
      });

  static Future<void> logSurahOpened(int surahId) =>
      logEvent('surah_opened', parameters: {'surah_id': surahId});
}