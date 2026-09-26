import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardEntry {
  final String uid;
  final String displayName;
  final String avatarEmoji;
  final int points;
  final int knownWords;
  final int streak;
  final String country;
  final String city;

  const LeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.avatarEmoji,
    required this.points,
    required this.knownWords,
    required this.streak,
    required this.country,
    required this.city,
  });

  factory LeaderboardEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return LeaderboardEntry(
      uid: d.id,
      displayName: (m['displayName'] ?? 'Learner').toString(),
      avatarEmoji: (m['avatarEmoji'] ?? '📖').toString(),
      points: (m['points'] as num?)?.toInt() ?? 0,
      knownWords: (m['knownWords'] as num?)?.toInt() ?? 0,
      streak: (m['streak'] as num?)?.toInt() ?? 0,
      country: (m['country'] ?? '').toString(),
      city: (m['city'] ?? '').toString(),
    );
  }
}

class GroupInfo {
  final String id;
  final String name;
  final String code;
  final String ownerUid;
  final int weeklyGoalPoints;

  const GroupInfo({
    required this.id,
    required this.name,
    required this.code,
    required this.ownerUid,
    required this.weeklyGoalPoints,
  });

  factory GroupInfo.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return GroupInfo(
      id: d.id,
      name: (m['name'] ?? 'Group').toString(),
      code: (m['code'] ?? '').toString(),
      ownerUid: (m['ownerUid'] ?? '').toString(),
      weeklyGoalPoints: (m['weeklyGoalPoints'] as num?)?.toInt() ?? 500,
    );
  }
}

class GroupMemberEntry {
  final String uid;
  final String displayName;
  final String avatarEmoji;
  final int points;
  final int knownWords;
  final int streak;
  final int weekStartPoints;

  const GroupMemberEntry({
    required this.uid,
    required this.displayName,
    required this.avatarEmoji,
    required this.points,
    required this.knownWords,
    required this.streak,
    required this.weekStartPoints,
  });

  int get weeklyPoints => (points - weekStartPoints).clamp(0, 1 << 30);

  factory GroupMemberEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return GroupMemberEntry(
      uid: d.id,
      displayName: (m['displayName'] ?? 'Learner').toString(),
      avatarEmoji: (m['avatarEmoji'] ?? '📖').toString(),
      points: (m['points'] as num?)?.toInt() ?? 0,
      knownWords: (m['knownWords'] as num?)?.toInt() ?? 0,
      streak: (m['streak'] as num?)?.toInt() ?? 0,
      weekStartPoints: (m['weekStartPoints'] as num?)?.toInt() ?? 0,
    );
  }
}

class FriendRequestEntry {
  final String fromUid;
  final String fromDisplayName;
  final String fromAvatarEmoji;

  const FriendRequestEntry({
    required this.fromUid,
    required this.fromDisplayName,
    required this.fromAvatarEmoji,
  });

  factory FriendRequestEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return FriendRequestEntry(
      fromUid: d.id,
      fromDisplayName: (m['fromDisplayName'] ?? 'Learner').toString(),
      fromAvatarEmoji: (m['fromAvatarEmoji'] ?? '📖').toString(),
    );
  }
}

const kAvatarEmojis = [
  '📖', '🕌', '⭐', '🌙', '🦅', '🦁', '🌸', '🔥', '💎', '🎯', '🌿', '🕋'
];