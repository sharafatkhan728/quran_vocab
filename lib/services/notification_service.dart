// ignore_for_file: unused_local_variable, use_build_context_synchronously
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:quran_vocab/services/crashlytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../database/database_manager.dart';
import '../screens/flashcard_screen.dart';
import '../screens/progress_screen.dart';
import '../screens/main_navigation.dart';

/// NotificationService — local notifications only, no FCM.
///
/// Design note: there is intentionally NO in-app notification settings
/// screen and NO per-type on/off toggles, no reminder-time picker, no quiet
/// hours, and no frequency setting — exactly like most standard apps. Users
/// control notifications entirely through the OS's own
/// Settings → Apps → Notifications screen. This service only decides
/// *whether a reminder is currently relevant* (e.g. cards are actually due)
/// and, if so, schedules it for a reasonable, semi-randomised daytime time —
/// it never sends a notification that has nothing useful to say.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // ── Channel IDs ───────────────────────────────────────────────────────────
  static const _chReview = 'quran_review';
  static const _chDaily  = 'quran_daily';
  static const _chStreak = 'quran_streak';
  static const _chWeekly = 'quran_weekly';

  // ── Notification IDs ─────────────────────────────────────────────────────
  static const _idReview   = 1;
  static const _idDaily    = 2;
  static const _idNewVocab = 3;
  static const _idStreak   = 4;
  static const _idWeekly   = 5;

  // ── Reasonable daytime window for reminders. This IS the "quiet hours"
  // equivalent — just fixed and not user-configurable, like a standard app.
  static const int _windowStartHour = 9;  // 9 AM
  static const int _windowEndHour   = 21; // 9 PM

  /// Called when scheduling a notification fails (e.g. Android 14+ without
  /// exact-alarm permission).
  static void Function(String message)? onScheduleError;

  /// Last scheduling error message, if any.
  static String? lastScheduleError;

  /// Set this from main.dart so notification taps can navigate.
  static GlobalKey<NavigatorState>? navigatorKey;

  // ── Init ──────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    // CRITICAL: without this, tz.local silently defaults to UTC, and every
    // scheduled reminder below fires at the wrong wall-clock time for the
    // device's actual timezone (often appearing to the user as "never
    // arrives", since it lands hours off from the expected daytime window).
    try {
      final deviceTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(_resolveTzAlias(deviceTz)));
    } catch (e) {
      debugPrint(
          'NotificationService: could not detect device timezone ($e) — '
          'falling back to UTC, reminder times will be off');
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onTap,
    );

    if (Platform.isAndroid) {
      final prefs = await SharedPreferences.getInstance();
      // Channels only need to be created once, ever — recreating them on
      // every app launch is a harmless no-op to Android but still an
      // unnecessary round-trip. Skip it once we know they already exist.
      if (prefs.getBool('notif_channels_created') != true) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await android?.createNotificationChannel(const AndroidNotificationChannel(
          _chReview, 'Vocabulary Review',
          description: 'SRS review reminders',
          importance: Importance.high,
        ));
        await android?.createNotificationChannel(const AndroidNotificationChannel(
          _chDaily, 'Daily Quran Reminder',
          description: 'Daily Quran reading reminders',
          importance: Importance.defaultImportance,
        ));
        await android?.createNotificationChannel(const AndroidNotificationChannel(
          _chStreak, 'Streak Reminder',
          description: 'Streak protection reminders',
          importance: Importance.high,
        ));
        await android?.createNotificationChannel(const AndroidNotificationChannel(
          _chWeekly, 'Weekly Progress',
          description: 'Weekly progress summary',
          importance: Importance.low,
        ));
        await prefs.setBool('notif_channels_created', true);
      }
    }

    _initialized = true;
  }

  // ── Permission ────────────────────────────────────────────────────────────
  // Requested once at startup (standard first-run prompt). After that, all
  // on/off control lives in the OS notification settings for this app —
  // exactly like any standard app.

  static Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final android =
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() 
      ?? false;
      return granted;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
    IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
            alert: true, badge: true, sound: true) ?? false;
      return granted;
    }
    return true;
  }

  // ── Tap handler (deep link) ───────────────────────────────────────────────

  static void _onTap(NotificationResponse response) {
    // Uses direct MaterialPageRoute pushes rather than named routes —
    // MaterialApp in main.dart only declares a `home`, no routes table, so
    // pushNamedAndRemoveUntil('/flashcards', ...) would throw at runtime
    // (no registered route generator) every time a notification was tapped.
    final nav = navigatorKey?.currentState;
    if (nav == null) return;
    try {
      if (response.payload == 'flashcards') {
        nav.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const FlashcardScreen()),
            (r) => false);
      } else if (response.payload == 'progress') {
        nav.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ProgressScreen()),
            (r) => false);
      } else if (response.payload == 'quran') {
        nav.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainNavigation()),
            (r) => false);
      }
    } catch (e, stack) {
      debugPrint('NotificationService._onTap navigation failed: $e');
      CrashlyticsService.recordError(e, stack,
          context: 'NotificationService._onTap');
    }
  }

  // ── Smart scheduling — main entry point ───────────────────────────────────
  /// Call this after any significant user action (known word, session done)
  /// and on app startup. It checks SQLite, then schedules only the reminders
  /// that are actually relevant right now — nothing is scheduled "just to
  /// fill a slot". Actual delivery is still gated by the OS-level
  /// notification permission/settings, exactly like a standard app.
  static Future<void> rescheduleAll() async {
    try {
      await _plugin.cancelAll();

      final db = await DatabaseManager.db;

    // ── 1. SRS reviews due ────────────────────────────────────────────────
    final sessionRows = await db.query('user_meta',
        where: 'key = ?', whereArgs: ['srs_total_sessions'], limit: 1);
    final currentSession = sessionRows.isEmpty
        ? 0
        : int.tryParse(sessionRows.first['value'] as String) ?? 0;

    final dueRows = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM srs_cards
      WHERE is_deleted = 0
        AND total_reviews > 0
        AND next_review_session <= ?
    ''', [currentSession]);
    final due = (dueRows.first['cnt'] as int?) ?? 0;

    final failedRows = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM srs_cards
      WHERE is_deleted = 0 AND fail_count > 0 AND stage = 0
        AND next_review_session <= ?
    ''', [currentSession]);
    final failed = (failedRows.first['cnt'] as int?) ?? 0;

    if (due > 0 || failed > 0) {
      final title = failed > 0
          ? '$failed difficult words need review'
          : '$due Quran words due for review';
      final body = failed > 0
          ? 'Strengthen your memory — review failed words now'
          : 'Keep your streak going! Tap to start reviewing.';
      final time = await _reminderTimeFor('review');
      await _scheduleDaily(
        id: _idReview,
        channelId: _chReview,
        title: title,
        body: body,
        hour: time.$1,
        minute: time.$2,
        payload: 'flashcards',
      );
    }

    // ── 2. Daily Quran reminder ───────────────────────────────────────────
    final readRows = await db.query('reading_progress',
        where: 'last_read_at > ?', whereArgs: [_todayStartMs()]);
    final readToday = readRows.isNotEmpty;

    if (!readToday) {
      const messages = [
        'Take 5 minutes for Quran today. 📖',
        'Your daily Quran reading is waiting.',
        'Begin your day with the Quran. ☀️',
        'Even one ayah brings reward. 🌙',
      ];
      final msg = messages[DateTime.now().day % messages.length];
      final time = await _reminderTimeFor('daily');
      await _scheduleDaily(
        id: _idDaily,
        channelId: _chDaily,
        title: 'Daily Quran Reminder',
        body: msg,
        hour: time.$1,
        minute: time.$2,
        payload: 'quran',
      );
    }

    // ── 3. New vocabulary goal ────────────────────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final goalPrefs = prefs.getInt('daily_goal') ?? 5;
    final todayKey = _todayKey();
    final todayRows = await db.query('daily_stats',
        where: 'date_key = ?', whereArgs: [todayKey], limit: 1);
    final learnedToday = todayRows.isEmpty
        ? 0
        : (todayRows.first['words_learned'] as int? ?? 0);

    if (learnedToday < goalPrefs) {
      final remaining = goalPrefs - learnedToday;
      final time = await _reminderTimeFor('new_vocab');
      await _scheduleDaily(
        id: _idNewVocab,
        channelId: _chDaily,
        title: 'Today\'s Vocabulary Goal',
        body: 'Learn $remaining more Quran words today to reach your goal.',
        hour: time.$1,
        minute: time.$2,
        payload: 'flashcards',
      );
    }

    // ── 4. Streak reminder ────────────────────────────────────────────────
    if (learnedToday == 0) {
      final today = DateTime.now();
      // Single bulk query for the last year + in-memory walk, instead of up
      // to 365 sequential single-row DB queries. This path runs far more
      // often than a one-time screen load — it's called after every
      // flashcard swipe and every session completion — so the old per-day
      // query loop could add a noticeable stutter to normal app use.
      final cutoff = today.subtract(const Duration(days: 365));
      final cutoffKey = _dateKey(cutoff);
      final streakRows = await db.query('daily_stats',
          where: 'date_key >= ?', whereArgs: [cutoffKey]);
      final streakMap = <String, int>{
        for (final r in streakRows)
          r['date_key'] as String: (r['words_learned'] as int? ?? 0),
      };
      int streak = 0;
      for (int d = 1; d <= 365; d++) {
        final day = today.subtract(Duration(days: d));
        final key = _dateKey(day);
        if ((streakMap[key] ?? 0) > 0) {
          streak++;
        } else {
          break;
        }
      }
      if (streak >= 2) {
        // Later part of the window so it reads as a last-chance nudge
        // rather than a duplicate of the earlier reminders.
        final time = await _reminderTimeFor('streak', minHour: 17);
        await _scheduleDaily(
          id: _idStreak,
          channelId: _chStreak,
          title: 'Your $streak-day streak is at risk! 🔥',
          body: 'Practice even one word to keep your streak alive.',
          hour: time.$1,
          minute: time.$2,
          payload: 'flashcards',
        );
      }
    }

    // ── 5. Weekly progress (Sunday only) ─────────────────────────────────
    final now = DateTime.now();
    if (now.weekday == DateTime.sunday) {
      final lastWeekKey = prefs.getString('notif_last_weekly') ?? '';
      final thisWeekKey = '${now.year}-W${_weekNumber(now)}';
      if (lastWeekKey != thisWeekKey) {
        int weekWords = 0;
        int weekSessions = 0;
        for (int d = 0; d < 7; d++) {
          final day = now.subtract(Duration(days: d));
          final key = _dateKey(day);
          final rows = await db.query('daily_stats',
              where: 'date_key = ?', whereArgs: [key], limit: 1);
          if (rows.isNotEmpty) {
            weekWords += (rows.first['words_learned'] as int? ?? 0);
            weekSessions += (rows.first['sessions'] as int? ?? 0);
          }
        }

        final metaRows = await db.query('user_meta',
            where: 'key = ?', whereArgs: ['longest_streak'], limit: 1);
        final streak = metaRows.isEmpty
            ? 0
            : int.tryParse(metaRows.first['value'] as String) ?? 0;

        final body = 'Week: $weekWords words learned'
            '${weekSessions > 0 ? ' • $weekSessions sessions' : ''}'
            '${streak > 0 ? ' • $streak day streak' : ''}';

        await _showImmediate(
          id: _idWeekly,
          channelId: _chWeekly,
          title: '📊 Your Weekly Quran Progress',
          body: body,
          payload: 'progress',
        );
        await prefs.setString('notif_last_weekly', thisWeekKey);
      }
    }
    } catch (e) {
      debugPrint('NotificationService.rescheduleAll error: $e');
    }
  }

  // ── Schedule helpers ──────────────────────────────────────────────────────

  static Future<void> _scheduleDaily({
    required int id,
    required String channelId,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required String payload,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId, channelId,
            importance: channelId == _chStreak || channelId == _chReview
                ? Importance.high
                : Importance.defaultImportance,
            priority: Priority.defaultPriority,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
    } on PlatformException catch (e) {
      debugPrint(
          'NotificationService: zonedSchedule failed — ${e.message ?? e.code}');
      lastScheduleError = 'Reminder scheduling is unavailable on this device. '
          'Open Settings → Apps → Quran Kalima → Notifications and allow '
          'scheduling.';
      onScheduleError?.call(lastScheduleError!);
    } catch (e) {
      debugPrint('NotificationService: zonedSchedule error: $e');
      lastScheduleError =
          'Unable to schedule reminder. Please check notification settings.';
      onScheduleError?.call(lastScheduleError!);
    }
  }

  static Future<void> _showImmediate({
    required int id,
    required String channelId,
    required String title,
    required String body,
    required String payload,
  }) async {
    await _plugin.show(
      id, title, body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId, channelId,
          importance: Importance.low,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  // ── Randomised-but-stable daily reminder time ─────────────────────────────
  /// Picks a semi-random time within a reasonable daytime window for the
  /// given reminder [type], and remembers it for the rest of the day so
  /// calling rescheduleAll() multiple times today (e.g. reopening the app)
  /// doesn't jitter the scheduled time around. A fresh random time is picked
  /// each new day automatically. This replaces the old fixed user-set
  /// reminder time, quiet hours, and frequency setting entirely.
  static Future<(int, int)> _reminderTimeFor(
    String type, {
    int minHour = _windowStartHour,
    int maxHour = _windowEndHour,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'notif_time_${type}_${_todayKey()}';
    final stored = prefs.getInt(key);
    if (stored != null) {
      return (stored ~/ 60, stored % 60);
    }
    final rand = Random();
    final span = (maxHour - minHour).clamp(1, 24);
    final hour = minHour + rand.nextInt(span);
    final minute = rand.nextInt(60);
    await prefs.setInt(key, hour * 60 + minute);
    return (hour, minute);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  // Some Android devices/OEMs report legacy IANA timezone names that the
  // bundled tz database no longer recognizes under that exact string (the
  // IANA database periodically renames zones, keeping the old name only as
  // an alias elsewhere). This maps the ones most likely to appear back to
  // their current canonical name so setLocalLocation doesn't throw and
  // silently fall back to UTC.
  static const _tzAliases = {
    'Asia/Calcutta': 'Asia/Kolkata',
    'Asia/Katmandu': 'Asia/Kathmandu',
    'Asia/Dacca': 'Asia/Dhaka',
    'Asia/Rangoon': 'Asia/Yangon',
    'Asia/Saigon': 'Asia/Ho_Chi_Minh',
    'Asia/Ujung_Pandang': 'Asia/Makassar',
    'Europe/Kiev': 'Europe/Kyiv',
  };

  static String _resolveTzAlias(String name) => _tzAliases[name] ?? name;

  static String _todayKey() => _dateKey(DateTime.now());  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static int _todayStartMs() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  static int _weekNumber(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    final diff = date.difference(startOfYear).inDays;
    return (diff / 7).ceil();
  }
}