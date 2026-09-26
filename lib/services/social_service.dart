import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/leaderboard_models.dart';
import 'leaderboard_service.dart';

/// Friends + Groups — all writes are either "your own doc" or "the doc that
/// represents you" (see firestore.rules), so no user ever needs write
/// access to someone else's private data.
class SocialService {
  SocialService._();

  static final _db = FirebaseFirestore.instance;
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── Friend requests ──────────────────────────────────────────────────────

  static Future<String> sendRequestByCode(String code) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not signed in');
    final clean = code.trim().toUpperCase();

    final match = await _db
        .collection('leaderboard')
        .where('friendCode', isEqualTo: clean)
        .limit(1)
        .get();
    if (match.docs.isEmpty) return 'Code not found';
    final target = match.docs.first;
    if (target.id == uid) return "That's your own code!";

    final myProfile = await LeaderboardService.getMyProfile();
    if (myProfile == null || !myProfile.exists) {
      return 'Set up your leaderboard profile first';
    }
    final myData = myProfile.data()!;

    final already = await _db
        .collection('friends')
        .doc(uid)
        .collection('list')
        .doc(target.id)
        .get();
    if (already.exists) return 'Already friends';

    await _db
        .collection('friend_requests')
        .doc(target.id)
        .collection('incoming')
        .doc(uid)
        .set({
      'fromUid': uid,
      'fromDisplayName': myData['displayName'] ?? 'Learner',
      'fromAvatarEmoji': myData['avatarEmoji'] ?? '📖',
      'sentAt': FieldValue.serverTimestamp(),
    });
    return 'Request sent!';
  }

  static Future<List<FriendRequestEntry>> getIncomingRequests() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _db
        .collection('friend_requests')
        .doc(uid)
        .collection('incoming')
        .get();
    return snap.docs.map(FriendRequestEntry.fromDoc).toList();
  }

  static Future<void> acceptRequest(FriendRequestEntry req) async {
    final uid = _uid;
    if (uid == null) return;
    final myProfile = await LeaderboardService.getMyProfile();
    final myData = myProfile?.data() ?? {};

    final now = FieldValue.serverTimestamp();
    // My own copy of the relation
    await _db
        .collection('friends')
        .doc(uid)
        .collection('list')
        .doc(req.fromUid)
        .set({
      'displayName': req.fromDisplayName,
      'avatarEmoji': req.fromAvatarEmoji,
      'addedAt': now,
    });
    // The doc that "represents me" inside their list (allowed since doc id == my uid)
    await _db
        .collection('friends')
        .doc(req.fromUid)
        .collection('list')
        .doc(uid)
        .set({
      'displayName': myData['displayName'] ?? 'Learner',
      'avatarEmoji': myData['avatarEmoji'] ?? '📖',
      'addedAt': now,
    });

    await _db
        .collection('friend_requests')
        .doc(uid)
        .collection('incoming')
        .doc(req.fromUid)
        .delete();
  }

  static Future<void> declineRequest(String fromUid) async {
    final uid = _uid;
    if (uid == null) return;
    await _db
        .collection('friend_requests')
        .doc(uid)
        .collection('incoming')
        .doc(fromUid)
        .delete();
  }

  static Future<List<Map<String, dynamic>>> getFriendsRaw() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap =
        await _db.collection('friends').doc(uid).collection('list').get();
    return snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
  }

  static Future<List<LeaderboardEntry>> getFriendsLeaderboard() async {
    final friends = await getFriendsRaw();
    final uids = friends.map((f) => f['uid'] as String).toList();
    return LeaderboardService.fetchByUids(uids);
  }

  static Future<void> removeFriend(String friendUid) async {
    final uid = _uid;
    if (uid == null) return;
    await _db
        .collection('friends')
        .doc(uid)
        .collection('list')
        .doc(friendUid)
        .delete();
    await _db
        .collection('friends')
        .doc(friendUid)
        .collection('list')
        .doc(uid)
        .delete();
  }

  // ── Groups ───────────────────────────────────────────────────────────────

  static Future<GroupInfo> createGroup(String name) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not signed in');
    final code = await _generateUniqueGroupCode();
    final ref = _db.collection('groups').doc();
    await ref.set({
      'name': name.trim(),
      'code': code,
      'ownerUid': uid,
      'weeklyGoalPoints': 500,
      'weekResetAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _joinAsMember(ref.id);
    return GroupInfo(
        id: ref.id, name: name.trim(), code: code, ownerUid: uid,
        weeklyGoalPoints: 500);
  }

  static Future<String> _generateUniqueGroupCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    for (int attempt = 0; attempt < 5; attempt++) {
      final code =
          List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
      final dup = await _db
          .collection('groups')
          .where('code', isEqualTo: code)
          .limit(1)
          .get();
      if (dup.docs.isEmpty) return code;
    }
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  static Future<GroupInfo?> joinGroupByCode(String code) async {
    final clean = code.trim().toUpperCase();
    final match = await _db
        .collection('groups')
        .where('code', isEqualTo: clean)
        .limit(1)
        .get();
    if (match.docs.isEmpty) return null;
    final groupDoc = match.docs.first;
    await _joinAsMember(groupDoc.id);
    return GroupInfo.fromDoc(groupDoc);
  }

  static Future<void> _joinAsMember(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    final myProfile = await LeaderboardService.getMyProfile();
    final myData = myProfile?.data() ?? {};
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .set({
      'uid': uid,
      'displayName': myData['displayName'] ?? 'Learner',
      'avatarEmoji': myData['avatarEmoji'] ?? '📖',
      'points': myData['points'] ?? 0,
      'knownWords': myData['knownWords'] ?? 0,
      'streak': myData['streak'] ?? 0,
      'weekStartPoints': myData['points'] ?? 0,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await LeaderboardService.pushNow(force: true);
  }

  static Future<void> leaveGroup(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .delete();
  }

  /// Uses a Collection Group Query — finds every "members" doc across ALL
  /// groups where uid == me, so we never need to separately track "which
  /// groups am I in" (saves writes).
  static Future<List<GroupInfo>> getMyGroups() async {
    final uid = _uid;
    if (uid == null) return [];
    final memberSnap = await _db
        .collectionGroup('members')
        .where('uid', isEqualTo: uid)
        .get();
    final groups = <GroupInfo>[];
    for (final m in memberSnap.docs) {
      final groupRef = m.reference.parent.parent;
      if (groupRef == null) continue;
      final groupDoc = await groupRef.get();
      if (groupDoc.exists) groups.add(GroupInfo.fromDoc(groupDoc));
    }
    return groups;
  }

  static Future<List<GroupMemberEntry>> getGroupLeaderboard(
      String groupId) async {
    final snap = await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .get();
    final list = snap.docs.map(GroupMemberEntry.fromDoc).toList();
    list.sort((a, b) => b.points.compareTo(a.points));
    return list;
  }

  static Future<int> getGroupMemberCount(String groupId) async {
    final agg = await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .count()
        .get();
    return agg.count ?? 0;
  }

  /// Best-effort weekly reset — any member opening the group can trigger
  /// this if 7 days have passed; harmless if it races with another device.
  static Future<void> maybeResetWeek(GroupInfo group) async {
    final groupDoc = await _db.collection('groups').doc(group.id).get();
    final resetAt = groupDoc.data()?['weekResetAt'] as Timestamp?;
    final isStale = resetAt == null ||
        DateTime.now().difference(resetAt.toDate()).inDays >= 7;
    if (!isStale) return;

    await _db.collection('groups').doc(group.id).set(
        {'weekResetAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    final uid = _uid;
    if (uid == null) return;
    final myMember = await _db
        .collection('groups')
        .doc(group.id)
        .collection('members')
        .doc(uid)
        .get();
    final currentPoints = (myMember.data()?['points'] as num?)?.toInt() ?? 0;
    await _db
        .collection('groups')
        .doc(group.id)
        .collection('members')
        .doc(uid)
        .set({'weekStartPoints': currentPoints}, SetOptions(merge: true));
  }

  static Future<void> setWeeklyGoal(String groupId, int points) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .set({'weeklyGoalPoints': points}, SetOptions(merge: true));
  }
}