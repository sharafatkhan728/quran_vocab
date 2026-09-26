import 'package:flutter/material.dart';
import '../models/leaderboard_models.dart';
import '../services/social_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  static const _green = Color(0xFF1B4332);
  List<FriendRequestEntry> _requests = [];
  List<Map<String, dynamic>> _friends = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await SocialService.getIncomingRequests();
    final f = await SocialService.getFriendsRaw();
    if (mounted) setState(() { _requests = r; _friends = f; _loading = false; });
  }

  Future<void> _addByCode() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Friend'),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Enter 6-digit friend code'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Send Request')),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    final msg = await SocialService.sendRequestByCode(code);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.person_add), onPressed: _addByCode)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_requests.isNotEmpty) ...[
                    const Text('Requests', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._requests.map((r) => Card(
                          child: ListTile(
                            leading: Text(r.fromAvatarEmoji, style: const TextStyle(fontSize: 22)),
                            title: Text(r.fromDisplayName),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                onPressed: () async {
                                  await SocialService.acceptRequest(r);
                                  _load();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () async {
                                  await SocialService.declineRequest(r.fromUid);
                                  _load();
                                },
                              ),
                            ]),
                          ),
                        )),
                    const SizedBox(height: 16),
                  ],
                  const Text('My Friends', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_friends.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Koi friend nahi hai abhi — code se add karo')),
                    ),
                  ..._friends.map((f) => Card(
                        child: ListTile(
                          leading: Text(f['avatarEmoji'] ?? '📖',
                              style: const TextStyle(fontSize: 22)),
                          title: Text(f['displayName'] ?? 'Learner'),
                          trailing: IconButton(
                            icon: const Icon(Icons.person_remove, color: Colors.grey),
                            onPressed: () async {
                              await SocialService.removeFriend(f['uid']);
                              _load();
                            },
                          ),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}