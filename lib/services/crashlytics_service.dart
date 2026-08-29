/// Global crash and error reporting via Firebase Crashlytics.
///
/// Call [init] once in [main.dart] before [runApp].
/// It wires three Flutter error hooks:
///   1. [FlutterError.onError]           — widget build/render errors
///   2. [PlatformDispatcher.instance.onError] — uncaught platform errors
///   3. [runZonedGuarded] in main.dart  — uncaught async & zone errors
///
/// Call [recordError] from catch blocks in [SyncService] and
/// [DatabaseImporter] so their failures also surface in Crashlytics.
library;

import 'dart:async';
import 'dart:developer' as dev;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashlyticsService {
  CrashlyticsService._();

  /// Call this once before runApp. Safe to call even if Firebase is not
  /// initialised — future calls will no-op until Firebase is ready.
  static Future<void> init() async {
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterError(details);
      // Also print to console so devtools / logcat still shows it
      FlutterError.dumpErrorToConsole(details);
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      FirebaseCrashlytics.instance.recordError(error, stackTrace,
          fatal: true);
      dev.log(error.toString(), level: 1000);
      return true; // handled
    };
  }

  /// Call from catch blocks to report application-level errors.
  /// [level] controls log level (300=warning, 1000=severe).
  static void recordError(
    Object error,
    StackTrace stackTrace, {
    String? context,
    int level = 1000,
  }) {
    final message = context != null ? '$context — $error' : error.toString();
    FirebaseCrashlytics.instance.recordError(error, stackTrace,
        reason: message);
    if (!kReleaseMode) {
      dev.log(message, level: level);
    }
  }
}
