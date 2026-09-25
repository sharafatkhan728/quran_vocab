import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../database/database_importer.dart';
import '../database/database_manager.dart';
import '../services/sync_service.dart';
import '../services/notification_service.dart';
import '../services/remote_config_service.dart';

/// Writes a lightweight, non-sensitive snapshot of this device's app state
/// to Firestore (users/{uid}/diagnostics/current), so that when a user
/// reports a problem, opening that one document in the Firebase Console
/// tells you their app version, content version, sync status, SRS session,
/// and last error — without asking the user ten questions.
///
/// This is diagnostics ONLY. It never contains Quran text, search queries,
/// or personal data beyond what Firebase Auth already has (uid/email).
class DiagnosticsService {
  DiagnosticsService._();

  static String? _lastActiveScreen;
  static Timer? _debounce;

  /// Call this from screens as they become visible (cheap, in-memory only
  /// until the next debounced write) so "last active feature" is accurate
  /// when a user reports an issue mid-session.
  static void setLastActiveScreen(String screenName) {
    _lastActiveScreen = screenName;
    _scheduleWrite();
  }

  /// Call once after login and after any sync completes.
  static void requestWrite() => _scheduleWrite();

  static void _scheduleWrite() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      unawaited(_writeNow());
    });
  }

  static Future<void> _writeNow() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return; // No account — nothing to attach diagnostics to.

    try {
      final info = await PackageInfo.fromPlatform();
      String deviceModel = 'unknown';
      String osVersion = 'unknown';
      if (Platform.isAndroid) {
        final android = await DeviceInfoPlugin().androidInfo;
        deviceModel = '${android.manufacturer} ${android.model}';
        osVersion = 'Android ${android.version.release}';
      } else if (Platform.isIOS) {
        final ios = await DeviceInfoPlugin().iosInfo;
        deviceModel = ios.utsname.machine;
        osVersion = 'iOS ${ios.systemVersion}';
      }

      final db = await DatabaseManager.db;
      final metaRows = await db.query('db_meta');
      final metaMap = {
        for (final r in metaRows) r['key'] as String: r['value'] as String
      };

      // Crashlytics crashes are tagged with this same uid via
      // setUserIdentifier() in UserProvider, so the uid itself is the
      // cross-reference key between Crashlytics and this diagnostics doc —
      // no separate installation-ID lookup is needed.
      final crashlyticsId = uid;

      final data = {
        'appVersion': info.version,
        'buildNumber': info.buildNumber,
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'deviceModel': deviceModel,
        'osVersion': osVersion,
        'contentCacheVersion': DatabaseImporter.contentCacheVersion,
        'importCompletedAt': metaMap['import_completed_at'] ?? '',
        'lastSuccessfulSync': SyncService.lastStatus == SyncStatus.done
            ? Timestamp.now()
            : null,
        'lastSyncStatus': SyncService.lastStatus.name,
        'lastSyncError': SyncService.lastError ?? '',
        'lastActiveScreen': _lastActiveScreen ?? '',
        'notificationScheduleError': NotificationService.lastScheduleError ?? '',
        'crashlyticsId': crashlyticsId,
        'remoteConfigMaintenanceMode': RemoteConfigService.maintenanceMode,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('diagnostics')
          .doc('current')
          .set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('DiagnosticsService write failed: $e');
      // Non-fatal — diagnostics are best-effort, never block the app.
    }
  }
}