// ignore_for_file: unused_local_variable, use_build_context_synchronously
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../database/database_manager.dart';

/// NotificationService — local notifications only, no FCM.
/// SQLite is the source of truth. SharedPreferences stores only settings.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // ── Channel IDs ───────────────────────────────────────────────────────────
  static const _chReview    = 'quran_review';
  static const _chDaily     = 'quran_daily';
  static const _chStreak    = 'quran_streak';
  static const _chWeekly    = 'quran_weekly';

  // ── Notification IDs ─────────────────────────────────────────────────────
  static const _idReview    = 1;
  static const _idDaily     = 2;
  static const _idNewVocab  = 3;
  static const _idStreak    = 4;
  static const _idWeekly    = 5;

  // ── Prefs keys ────────────────────────────────────────────────────────────
  static const _kEnabled        = 'notif_enabled';
  static const _kReview         = 'notif_review';
  static const _kDailyQuran     = 'notif_daily_quran';
  static const _kNewVocab       = 'notif_new_vocab';
  static const _kStreak         = 'notif_streak';
  static const _kWeekly         = 'notif_weekly';
  static const _kHour           = 'notif_hour';
  static const _kMinute         = 'notif_minute';
  static const _kQuietStart     = 'notif_quiet_start';
  static const _kQuietEnd       = 'notif_quiet_end';
  static const _kFrequency      = 'notif_frequency'; // minimal/normal/frequent

  // ── Error callback (set from main.dart so we can show a snackbar) ────────
  /// Called when scheduling a notification fails (e.g. Android 14+ without
  /// exact-alarm permission). Set this in main.dart after init().
  static void Function(String message)? onScheduleError;

  /// Last scheduling error message, if any. Checked by the notification
  /// settings screen after [rescheduleAll] to show a user-visible hint.
  static String? lastScheduleError;

  // ── Init ──────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();

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

    // Create Android notification channels
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
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
    }

    _initialized = true;
  }

  // ── Permission ────────────────────────────────────────────────────────────

  static Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? false;
      return granted;
    }
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
            alert: true, badge: true, sound: true) ?? false;
      return granted;
    }
    return true;
  }

  // ── Tap handler (deep link) ───────────────────────────────────────────────

  static void _onTap(NotificationResponse response) {
    final payload = response.payload ?? '';
    if (payload == 'flashcards') {
      navigatorKey?.currentState?.pushNamedAndRemoveUntil(
          '/flashcards', (r) => false);
    } else if (payload == 'progress') {
      navigatorKey?.currentState?.pushNamedAndRemoveUntil(
          '/progress', (r) => false);
    } else if (payload == 'quran') {
      navigatorKey?.currentState?.pushNamedAndRemoveUntil(
          '/', (r) => false);
    }
  }

  /// Set this from main.dart so notification taps can navigate
  static GlobalKey<NavigatorState>? navigatorKey;

  // ── Smart scheduling — main entry point ───────────────────────────────────
  /// Call this after any significant user action (known word, session done)
  /// and on app startup. It checks SQLite, then schedules only what is needed.
  static Future<void> rescheduleAll() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabled) ?? true;
    if (!enabled) {
      await _plugin.cancelAll();
      return;
    }

    final hour   = prefs.getInt(_kHour) ?? 18;
    final minute = prefs.getInt(_kMinute) ?? 0;
    final quietStart = prefs.getInt(_kQuietStart) ?? 22;
    final quietEnd   = prefs.getInt(_kQuietEnd) ?? 7;

    // Cancel all then selectively reschedule based on SQLite state
    await _plugin.cancelAll();

    final db = await DatabaseManager.db;

    // ── 1. Check SRS reviews due ─────────────────────────────────────────
    if (prefs.getBool(_kReview) ?? true) {
      final sessionRows = await db.query('user_meta',
          where: 'key = ?', whereArgs: ['srs_total_sessions'], limit: 1);
      final currentSession =
          sessionRows.isEmpty ? 0 : int.tryParse(
              sessionRows.first['value'] as String) ?? 0;

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
        await _scheduleDaily(
          id: _idReview,
          channelId: _chReview,
          title: title,
          body: body,
          hour: hour,
          minute: minute,
          quietStart: quietStart,
          quietEnd: quietEnd,
          payload: 'flashcards',
        );
      }
    }

    // ── 2. Daily Quran reminder ──────────────────────────────────────────
    if (prefs.getBool(_kDailyQuran) ?? true) {
      final todayKey = _todayKey();
      final readRows = await db.query('reading_progress',
          where: 'last_read_at > ?',
          whereArgs: [_todayStartMs()]);
      final readToday = readRows.isNotEmpty;

      if (!readToday) {
        const messages = [
          'Take 5 minutes for Quran today. 📖',
          'Your daily Quran reading is waiting.',
          'Begin your day with the Quran. ☀️',
          'Even one ayah brings reward. 🌙',
        ];
        final msg = messages[DateTime.now().day % messages.length];
        await _scheduleDaily(
          id: _idDaily,
          channelId: _chDaily,
          title: 'Daily Quran Reminder',
          body: msg,
          hour: hour,
          minute: minute,
          quietStart: quietStart,
          quietEnd: quietEnd,
          payload: 'quran',
        );
      }
    }

    // ── 3. New vocabulary goal ───────────────────────────────────────────
    if (prefs.getBool(_kNewVocab) ?? true) {
      final goalRows = await db.query('user_meta',
          where: 'key = ?', whereArgs: ['notif_daily_goal'], limit: 1);
      // Read daily goal from user_meta or prefs
      final goalPrefs = prefs.getInt('daily_goal') ?? 5;

      final todayKey = _todayKey();
      final todayRows = await db.query('daily_stats',
          where: 'date_key = ?', whereArgs: [todayKey], limit: 1);
      final learnedToday =
          todayRows.isEmpty ? 0 : (todayRows.first['words_learned'] as int? ?? 0);

      if (learnedToday < goalPrefs) {
        final remaining = goalPrefs - learnedToday;
        // Schedule slightly later than main reminder
        final vocabMin = (minute + 5) % 60;
        final vocabHour = vocabMin < minute ? hour + 1 : hour;
        await _scheduleDaily(
          id: _idNewVocab,
          channelId: _chDaily,
          title: 'Today\'s Vocabulary Goal',
          body: 'Learn $remaining more Quran words today to reach your goal.',
          hour: vocabHour % 24,
          minute: vocabMin,
          quietStart: quietStart,
          quietEnd: quietEnd,
          payload: 'flashcards',
        );
      }
    }

    // ── 4. Streak reminder ───────────────────────────────────────────────
    if (prefs.getBool(_kStreak) ?? true) {
      // Only send if user has a streak and hasn't practiced today
      final todayKey = _todayKey();
      final todayRows = await db.query('daily_stats',
          where: 'date_key = ?', whereArgs: [todayKey], limit: 1);
      final learnedToday =
          todayRows.isEmpty ? 0 : (todayRows.first['words_learned'] as int? ?? 0);

      if (learnedToday == 0) {
        // Calculate streak
        final today = DateTime.now();
        int streak = 0;
        for (int d = 1; d <= 365; d++) {
          final day = today.subtract(Duration(days: d));
          final key = _dateKey(day);
          final rows = await db.query('daily_stats',
              where: 'date_key = ?', whereArgs: [key], limit: 1);
          if (rows.isNotEmpty &&
              (rows.first['words_learned'] as int? ?? 0) > 0) {
            streak++;
          } else {
            break;
          }
        }
        if (streak >= 2) {
          // Send streak reminder in the evening
          final streakHour = (hour + 2).clamp(0, 21);
          await _scheduleDaily(
            id: _idStreak,
            channelId: _chStreak,
            title: 'Your $streak-day streak is at risk! 🔥',
            body: 'Practice even one word to keep your streak alive.',
            hour: streakHour,
            minute: minute,
            quietStart: quietStart,
            quietEnd: quietEnd,
            payload: 'flashcards',
          );
        }
      }
    }

    // ── 5. Weekly progress (Sunday only) ────────────────────────────────
    if (prefs.getBool(_kWeekly) ?? true) {
      final now = DateTime.now();
      if (now.weekday == DateTime.sunday) {
        final lastWeekKey = prefs.getString('notif_last_weekly') ?? '';
        final thisWeekKey = '${now.year}-W${_weekNumber(now)}';
        if (lastWeekKey != thisWeekKey) {
          // Build weekly stats from SQLite
          int weekWords = 0;
          int weekSessions = 0;
          for (int d = 0; d < 7; d++) {
            final day = now.subtract(Duration(days: d));
            final key = _dateKey(day);
            final rows = await db.query('daily_stats',
                where: 'date_key = ?', whereArgs: [key], limit: 1);
            if (rows.isNotEmpty) {
              weekWords   += (rows.first['words_learned'] as int? ?? 0);
              weekSessions += (rows.first['sessions'] as int? ?? 0);
            }
          }
          // Count reading sessions this week
          final readRows = await db.rawQuery('''
            SELECT COUNT(*) as cnt FROM reading_progress
            WHERE last_read_at > ?
          ''', [now.subtract(const Duration(days: 7)).millisecondsSinceEpoch]);

          // Streak from user_meta
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
    required int quietStart,
    required int quietEnd,
    required String payload,
  }) async {
    // Skip if in quiet hours
    if (_inQuietHours(hour, quietStart, quietEnd)) return;

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day,
        hour, minute);
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
      lastScheduleError =
          'Reminder scheduling is unavailable on this device. '
          'Open Settings → Apps → Quran Kalima → Notifications and allow '
          'scheduling.';
      onScheduleError?.call(lastScheduleError!);
    } catch (e) {
      debugPrint('NotificationService: zonedSchedule error: $e');
      lastScheduleError = 'Unable to schedule reminder. Please check notification settings.';
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

  // ── Settings getters/setters ──────────────────────────────────────────────

  static Future<NotifSettings> getSettings() async {
    final p = await SharedPreferences.getInstance();
    return NotifSettings(
      enabled:      p.getBool(_kEnabled)    ?? true,
      review:       p.getBool(_kReview)     ?? true,
      dailyQuran:   p.getBool(_kDailyQuran) ?? true,
      newVocab:     p.getBool(_kNewVocab)   ?? true,
      streak:       p.getBool(_kStreak)     ?? true,
      weekly:       p.getBool(_kWeekly)     ?? true,
      hour:         p.getInt(_kHour)        ?? 18,
      minute:       p.getInt(_kMinute)      ?? 0,
      quietStart:   p.getInt(_kQuietStart)  ?? 22,
      quietEnd:     p.getInt(_kQuietEnd)    ?? 7,
      frequency:    p.getString(_kFrequency)?? 'normal',
    );
  }

  static Future<void> saveSettings(NotifSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled,    s.enabled);
    await p.setBool(_kReview,     s.review);
    await p.setBool(_kDailyQuran, s.dailyQuran);
    await p.setBool(_kNewVocab,   s.newVocab);
    await p.setBool(_kStreak,     s.streak);
    await p.setBool(_kWeekly,     s.weekly);
    await p.setInt(_kHour,        s.hour);
    await p.setInt(_kMinute,      s.minute);
    await p.setInt(_kQuietStart,  s.quietStart);
    await p.setInt(_kQuietEnd,    s.quietEnd);
    await p.setString(_kFrequency, s.frequency);
    await rescheduleAll();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static bool _inQuietHours(int hour, int quietStart, int quietEnd) {
    if (quietStart <= quietEnd) {
      return hour >= quietStart && hour < quietEnd;
    } else {
      // Wraps midnight e.g. 22→7
      return hour >= quietStart || hour < quietEnd;
    }
  }

  static String _todayKey() => _dateKey(DateTime.now());
  static String _dateKey(DateTime d) =>
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

// ── Settings model ────────────────────────────────────────────────────────────
class NotifSettings {
  bool enabled;
  bool review;
  bool dailyQuran;
  bool newVocab;
  bool streak;
  bool weekly;
  int hour;
  int minute;
  int quietStart;
  int quietEnd;
  String frequency;

  NotifSettings({
    required this.enabled,
    required this.review,
    required this.dailyQuran,
    required this.newVocab,
    required this.streak,
    required this.weekly,
    required this.hour,
    required this.minute,
    required this.quietStart,
    required this.quietEnd,
    required this.frequency,
  });

  NotifSettings copyWith({
    bool? enabled, bool? review, bool? dailyQuran, bool? newVocab,
    bool? streak, bool? weekly, int? hour, int? minute,
    int? quietStart, int? quietEnd, String? frequency,
  }) => NotifSettings(
    enabled:    enabled    ?? this.enabled,
    review:     review     ?? this.review,
    dailyQuran: dailyQuran ?? this.dailyQuran,
    newVocab:   newVocab   ?? this.newVocab,
    streak:     streak     ?? this.streak,
    weekly:     weekly     ?? this.weekly,
    hour:       hour       ?? this.hour,
    minute:     minute     ?? this.minute,
    quietStart: quietStart ?? this.quietStart,
    quietEnd:   quietEnd   ?? this.quietEnd,
    frequency:  frequency  ?? this.frequency,
  );
}