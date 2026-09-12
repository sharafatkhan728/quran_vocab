import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/announcement.dart';
import '../widgets/announcement_dialog.dart';
import 'crashlytics_service.dart';

/// Live in-app announcement system — lets you push new-feature notes, update
/// reminders, payment reminders, maintenance notices, or developer messages
/// to users without an app release, by adding documents to the Firestore
/// `announcements` collection (see announcement.dart for the schema).
///
/// This is entirely separate from NotificationService (local OS push
/// notifications scheduled from device data). AnnouncementService only shows
/// messages while the app is open, sourced live from Firestore.
class AnnouncementService {
  AnnouncementService._();

  static const String _collection = 'announcements';
  static const String _dismissedKey = 'dismissed_announcement_ids';

  // Prevents the same announcement from showing twice in one app session,
  // even before a "don't show again" dismissal has been persisted.
  static final Set<String> _seenThisSession = {};

  /// Call once after the main app UI is up (see MainNavigation.initState).
  /// Fetches active announcements and shows them one at a time. Fully
  /// wrapped so any failure (offline, permission, malformed doc, etc.) is
  /// silent and can never affect the rest of the app.
  static Future<void> checkAndShow(BuildContext context) async {
    try {
      final announcements = await _fetchEligible();
      if (announcements.isEmpty) return;
      await _showQueue(context, announcements);
    } catch (e, stack) {
      debugPrint('AnnouncementService: check failed — $e');
      CrashlyticsService.recordError(e, stack,
          context: 'AnnouncementService.checkAndShow');
    }
  }

  // ── Fetch + filter ─────────────────────────────────────────────────────────

  static Future<List<Announcement>> _fetchEligible() async {
    final snap = await FirebaseFirestore.instance
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .get()
        .timeout(const Duration(seconds: 8));

    final now = DateTime.now();
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final platform = Platform.isIOS ? 'ios' : 'android';

    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getStringList(_dismissedKey)?.toSet() ?? {};

    final result = <Announcement>[];
    for (final doc in snap.docs) {
      final a = Announcement.fromFirestore(doc.id, doc.data());

      if (_seenThisSession.contains(a.id)) continue;
      if (a.dismissible && dismissed.contains(a.id)) continue;
      if (a.startAt != null && now.isBefore(a.startAt!)) continue;
      if (a.expiresAt != null && now.isAfter(a.expiresAt!)) continue;
      if (a.targetPlatforms.isNotEmpty &&
          !a.targetPlatforms.contains(platform)) continue;
      if (!a.targetAll && !(uid != null && a.targetUserIds.contains(uid))) {
        continue;
      }
      if (a.minAppVersion != null &&
          _compareVersions(currentVersion, a.minAppVersion!) < 0) continue;
      if (a.maxAppVersion != null &&
          _compareVersions(currentVersion, a.maxAppVersion!) > 0) continue;

      result.add(a);
    }

    result.sort((a, b) => b.priority.compareTo(a.priority));
    return result;
  }

  // ── Display queue ─────────────────────────────────────────────────────────

  static Future<void> _showQueue(
      BuildContext context, List<Announcement> items) async {
    for (final a in items) {
      if (!context.mounted) return;
      _seenThisSession.add(a.id);
      final permanentlyDismiss = await showAnnouncementDialog(context, a);
      if (permanentlyDismiss && a.dismissible) {
        await _markDismissed(a.id);
      }
    }
  }

  static Future<void> _markDismissed(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_dismissedKey) ?? [];
    if (!list.contains(id)) {
      list.add(id);
      await prefs.setStringList(_dismissedKey, list);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Small numeric segment-by-segment version comparator so "1.10.0" is
  /// correctly seen as greater than "1.9.0" (plain string compare would get
  /// this wrong). Ignores any "+buildNumber" suffix.
  static int _compareVersions(String a, String b) {
    final pa = a
        .split('+')
        .first
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final pb = b
        .split('+')
        .first
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (int i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}