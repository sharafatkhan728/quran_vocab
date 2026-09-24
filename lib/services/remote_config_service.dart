import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Wraps Firebase Remote Config so the rest of the app reads flags through
/// simple static getters instead of touching the Firebase API directly.
/// Values here are OVERRIDES on top of local defaults — SQLite/local
/// SharedPreferences remain the source of truth for actual user data; this
/// only controls feature availability and safe limits, remotely.
class RemoteConfigService {
  RemoteConfigService._();

  static final FirebaseRemoteConfig _rc = FirebaseRemoteConfig.instance;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      await _rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // Short minimum fetch interval so console changes reach users
        // within an hour without needing a new release. Safe because
        // Remote Config fetches are free and lightweight.
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await _rc.setDefaults({
        'flashcards_enabled': true,
        'mushaf_mode_enabled': true,
        'cloud_sync_enabled': true,
        'donation_screen_enabled': true,
        'audio_playback_enabled': true,
        'maintenance_mode': false,
        'maintenance_message': '',
        'min_supported_app_version': '1.0.0',
        'daily_goal_min': 1,
        'daily_goal_max': 50,
      });
      await _rc.fetchAndActivate();
      _initialized = true;
    } catch (e) {
      debugPrint('RemoteConfigService.init failed (using defaults): $e');
      // Non-fatal — defaults above are already applied locally by
      // setDefaults(), so the app functions normally even fully offline
      // or on first-ever launch before any fetch succeeds.
    }
  }

  /// Call this occasionally (e.g. on app resume) to pick up console changes
  /// without waiting for the next cold start. Respects minimumFetchInterval
  /// above, so this is cheap to call often.
  static Future<void> refresh() async {
    try {
      await _rc.fetchAndActivate();
    } catch (e) {
      debugPrint('RemoteConfigService.refresh failed: $e');
    }
  }

  static bool get flashcardsEnabled => _rc.getBool('flashcards_enabled');
  static bool get mushafModeEnabled => _rc.getBool('mushaf_mode_enabled');
  static bool get cloudSyncEnabled => _rc.getBool('cloud_sync_enabled');
  static bool get donationScreenEnabled =>
      _rc.getBool('donation_screen_enabled');
  static bool get audioPlaybackEnabled =>
      _rc.getBool('audio_playback_enabled');
  static bool get maintenanceMode => _rc.getBool('maintenance_mode');
  static String get maintenanceMessage => _rc.getString('maintenance_message');
  static String get minSupportedAppVersion =>
      _rc.getString('min_supported_app_version');
  static int get dailyGoalMin => _rc.getInt('daily_goal_min');
  static int get dailyGoalMax => _rc.getInt('daily_goal_max');

  /// Firestore config version stamp — purely for diagnostics, so you can
  /// see in a user's diagnostics doc which config generation they're on.
  static String get activeConfigVersion =>
      _rc.getAll().isEmpty ? 'defaults' : 'fetched';
}