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

  static Future<void> logAyahOpened(int surahId, int ayahNumber) =>
      logEvent('ayah_opened', parameters: {
        'surah_id': surahId,
        'ayah_number': ayahNumber,
      });

  static Future<void> logVocabularyViewed(String tab, int wordCountShown) =>
      logEvent('vocabulary_viewed', parameters: {
        'tab': tab,
        'word_count_shown': wordCountShown,
      });

  static Future<void> logSrsReviewCompleted({
    required int cardsReviewed,
    required int pointsEarned,
    required int overdueCount,
    required int newCount,
  }) =>
      logEvent('srs_review_completed', parameters: {
        'cards_reviewed': cardsReviewed,
        'points_earned': pointsEarned,
        'overdue_count': overdueCount,
        'new_count': newCount,
      });

  static Future<void> logSearchUsed(String searchType, int resultCount) =>
      logEvent('search_used', parameters: {
        'search_type': searchType,
        'result_count': resultCount,
      });

  static Future<void> logFeatureUsed(String featureName) =>
      logEvent('feature_used', parameters: {'feature_name': featureName});

  static Future<void> logOnboardingCompleted({
    required int stepsCompleted,
    required String themeChoice,
    required int dailyGoalSelected,
  }) =>
      logEvent('onboarding_completed', parameters: {
        'steps_completed': stepsCompleted,
        'theme_choice': themeChoice,
        'daily_goal_selected': dailyGoalSelected,
      });

  static Future<void> logErrorOccurred({
    required String errorCode,
    required String screenName,
    bool isFatal = false,
  }) =>
      logEvent('error_occurred', parameters: {
        'error_code': errorCode,
        'screen_name': screenName,
        'is_fatal': isFatal,
      });

  static Future<void> logSurahCompleted(int surahId) =>
      logEvent('surah_completed', parameters: {'surah_id': surahId});

  static Future<void> logStreakMilestone(int streakDays) {
    final bucket = streakDays >= 100
        ? '100+'
        : streakDays >= 30
            ? '30-99'
            : '7-29';
    return logEvent('streak_milestone', parameters: {'streak_bucket': bucket});
  }

  static Future<void> logDonationScreenOpened(String region) =>
      logEvent('donation_screen_opened', parameters: {'region': region});
}