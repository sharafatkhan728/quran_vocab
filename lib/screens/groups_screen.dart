import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/leaderboard_models.dart';
import '../services/leaderboard_service.dart';
import '../services/social_service.dart';
import 'group_detail_screen.dart';
import 'leaderboard_profile_screen.dart';

class GroupsBody extends StatefulWidget {
  const GroupsBody({super.key});
  @override
  State<GroupsBody> createState() => _GroupsBodyState();
}

class _GroupsBodyState extends State<GroupsBody> {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);
  List<GroupInfo> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await SocialService.getMyGroups();
      if (mounted) setState(() => _groups = list);
    } catch (e) {
      debugPrint('GroupsBody._load failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ensureProfileThen(Future<void> Function() action) async {
    if (!await LeaderboardService.hasProfile()) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => const LeaderboardProfileScreen()));
      if (!await LeaderboardService.hasProfile()) return;
    }
    await action();
  }

  Future<void> _createGroup() async {
    await _ensureProfileThen(() async {
      final ctrl = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Create Group'),
          content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Group name')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Create')),
          ],
        ),
      );
      if (name == null || name.trim().isEmpty) return;
      final group = await SocialService.createGroup(name);
      _load();
      if (mounted) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)));
      }
    });
  }

  Future<void> _joinGroup() async {
    await _ensureProfileThen(() async {
      final ctrl = TextEditingController();
      final code = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Join Group'),
          content: TextField(
              controller: ctrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'Enter group code')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Join')),
          ],
        ),
      );
      if (code == null || code.trim().isEmpty) return;
      final group = await SocialService.joinGroupByCode(code);
      if (group == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Code not found')));
        }
        return;
      }
      _load();
      if (mounted) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _loading
            ? const Center(child: CircularProgressIndicator())
            : _groups.isEmpty
                ? const Center(child: Text('Koi group nahi — create ya join karo'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                      itemCount: _groups.length,
                      itemBuilder: (_, i) {
                        final g = _groups[i];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.groups, color: _green),
                            title: Text(g.name),
                            subtitle: Text('Code: ${g.code}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => GroupDetailScreen(group: g))),
                          ),
                        );
                      },
                    ),
                  ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: 'join',
                onPressed: _joinGroup,
                backgroundColor: _gold,
                icon: const Icon(Icons.group_add),
                label: const Text('Join'),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'create',
                onPressed: _createGroup,
                backgroundColor: _green,
                icon: const Icon(Icons.add),
                label: const Text('Create'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}