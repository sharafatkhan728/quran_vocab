import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/leaderboard_models.dart';
import '../services/social_service.dart';
import '../widgets/friend_mini_profile.dart';

class GroupDetailScreen extends StatefulWidget {
  final GroupInfo group;
  const GroupDetailScreen({super.key, required this.group});
  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);

  int _memberCount = 0;
  bool _resetChecked = false;
  late final Stream<List<GroupMemberEntry>> _membersStream;

  @override
  void initState() {
    super.initState();
    _membersStream = SocialService.streamGroupLeaderboard(widget.group.id);
    _init();
  }

  Future<void> _init() async {
    await SocialService.maybeResetWeek(widget.group);
    final count = await SocialService.getGroupMemberCount(widget.group.id);
    if (mounted) {
      setState(() {
        _memberCount = count;
        _resetChecked = true;
      });
    }
  }

  bool get _isOwner =>
      FirebaseAuth.instance.currentUser?.uid == widget.group.ownerUid;

  Future<void> _editGoal() async {
    final ctrl = TextEditingController(text: '${widget.group.weeklyGoalPoints}');
    final messenger = ScaffoldMessenger.of(context);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Weekly Goal (points)'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    final n = int.tryParse(v ?? '');
    if (n != null) {
      await SocialService.setWeeklyGoal(widget.group.id, n);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy join code',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.group.code));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Code ${widget.group.code} copied')));
            },
          ),
        ],
      ),
      body: !_resetChecked
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<GroupMemberEntry>>(
              stream: _membersStream,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final members = snap.data!;
                final weeklyTotal =
                    members.fold<int>(0, (s, m) => s + m.weeklyPoints);
                final goal = widget.group.weeklyGoalPoints;
                final progress =
                    goal == 0 ? 0.0 : (weeklyTotal / goal).clamp(0.0, 1.0);

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _gold.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('$_memberCount members • Code: ${widget.group.code}'),
                              if (_isOwner)
                                TextButton(onPressed: _editGoal, child: const Text('Edit Goal')),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('This week: $weeklyTotal / $goal points',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                                value: progress, minHeight: 8,
                                backgroundColor: Colors.grey.shade300,
                                valueColor: const AlwaysStoppedAnimation(_gold)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Group Leaderboard', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...members.asMap().entries.map((e) {
                      final i = e.key;
                      final m = e.value;
                      final isMe = m.uid == FirebaseAuth.instance.currentUser?.uid;
                      return GestureDetector(
                        onTap: () => showFriendMiniProfile(
                          context,
                          LeaderboardEntry(
                            uid: m.uid,
                            displayName: m.displayName,
                            avatarEmoji: m.avatarEmoji,
                            points: m.points,
                            knownWords: m.knownWords,
                            streak: m.streak,
                            country: '',
                            city: '',
                          ),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isMe ? _gold.withValues(alpha: 0.12) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isMe ? _gold : Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              SizedBox(width: 26, child: Text('${i + 1}')),
                              Text(m.avatarEmoji, style: const TextStyle(fontSize: 20)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(m.displayName)),
                              Text('${m.points} pts',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: _gold)),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    if (!_isOwner)
                      OutlinedButton(
                        onPressed: () async {
                          await SocialService.leaveGroup(widget.group.id);
                          if (!mounted) return;
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Leave Group'),
                      ),
                  ],
                );
              },
            ),
    );
  }
}