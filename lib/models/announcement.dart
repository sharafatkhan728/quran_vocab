import 'package:cloud_firestore/cloud_firestore.dart';

/// Category of an in-app announcement — used to pick an icon/color and lets
/// you filter by type later if you build an admin list.
enum AnnouncementType { feature, update, payment, maintenance, developer, general }

AnnouncementType announcementTypeFromString(String? s) {
  switch (s) {
    case 'feature':
      return AnnouncementType.feature;
    case 'update':
      return AnnouncementType.update;
    case 'payment':
      return AnnouncementType.payment;
    case 'maintenance':
      return AnnouncementType.maintenance;
    case 'developer':
      return AnnouncementType.developer;
    default:
      return AnnouncementType.general;
  }
}

/// A single Firestore-driven in-app announcement.
///
/// Expected document shape in the `announcements` collection (all fields
/// except title/body/type are optional):
/// ```
/// {
///   "title": "New Feature: Mushaf Mode",
///   "body": "Continuous Quran reading is here! Check it out in the reader.",
///   "type": "feature",              // feature | update | payment | maintenance | developer | general
///   "priority": 0,                  // higher shows first when several are active
///   "startAt": Timestamp,           // optional — not shown before this time
///   "expiresAt": Timestamp,         // optional — not shown after this time
///   "targetPlatforms": ["android"], // optional — empty/absent = all platforms
///   "minAppVersion": "1.0.0",       // optional — inclusive
///   "maxAppVersion": "1.9.9",       // optional — inclusive
///   "targetAll": true,              // if false, only targetUserIds see it
///   "targetUserIds": ["uid1"],      // used when targetAll is false
///   "dismissible": true,            // false = reappears every launch until it expires
///   "actionLabel": "Update Now",    // optional CTA button text
///   "actionUrl": "https://...",     // optional CTA button link
///   "createdAt": Timestamp          // used for ordering
/// }
/// ```
class Announcement {
  final String id;
  final String title;
  final String body;
  final AnnouncementType type;
  final int priority;
  final DateTime? startAt;
  final DateTime? expiresAt;
  final List<String> targetPlatforms;
  final String? minAppVersion;
  final String? maxAppVersion;
  final bool targetAll;
  final List<String> targetUserIds;
  final bool dismissible;
  final String? actionLabel;
  final String? actionUrl;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.priority = 0,
    this.startAt,
    this.expiresAt,
    this.targetPlatforms = const [],
    this.minAppVersion,
    this.maxAppVersion,
    this.targetAll = true,
    this.targetUserIds = const [],
    this.dismissible = true,
    this.actionLabel,
    this.actionUrl,
  });

  factory Announcement.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? ts(String key) {
      final v = data[key];
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return Announcement(
      id: id,
      title: (data['title'] ?? '').toString(),
      body: (data['body'] ?? '').toString(),
      type: announcementTypeFromString(data['type'] as String?),
      priority: (data['priority'] as num?)?.toInt() ?? 0,
      startAt: ts('startAt'),
      expiresAt: ts('expiresAt'),
      targetPlatforms: (data['targetPlatforms'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      minAppVersion: data['minAppVersion'] as String?,
      maxAppVersion: data['maxAppVersion'] as String?,
      targetAll: data['targetAll'] as bool? ?? true,
      targetUserIds: (data['targetUserIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      dismissible: data['dismissible'] as bool? ?? true,
      actionLabel: data['actionLabel'] as String?,
      actionUrl: data['actionUrl'] as String?,
    );
  }
}