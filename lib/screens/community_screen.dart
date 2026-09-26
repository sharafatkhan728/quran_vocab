import 'package:flutter/material.dart';
import 'friends_screen.dart';
import 'groups_screen.dart';
import 'leaderboard_screen.dart';
import 'leaderboard_profile_screen.dart';
import '../services/leaderboard_service.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);
  late TabController _tabs;
  bool _checking = true;
  bool _hasProfile = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_onTabChanged);
    _check();
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final has = await LeaderboardService.hasProfile();
    if (mounted) setState(() {
      _hasProfile = has;
      _checking = false;
    });
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community'),
        centerTitle: true,
        backgroundColor: _green,
        foregroundColor: Colors.white,
        actions: (_hasProfile && _tabs.index == 0)
            ? [
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Leaderboard Settings',
                  onPressed: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const LeaderboardProfileScreen()));
                    LeaderboardBody.refreshNotifier.value++;
                  },
                ),
              ]
            : null,
        bottom: _hasProfile
            ? TabBar(
                controller: _tabs,
                indicatorColor: _gold,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(icon: Icon(Icons.leaderboard), text: 'Leaderboard'),
                  Tab(icon: Icon(Icons.people), text: 'Friends'),
                  Tab(icon: Icon(Icons.groups), text: 'Groups'),
                ],
              )
            : null,
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : !_hasProfile
              ? _buildSetupPrompt()
              : TabBarView(
                  controller: _tabs,
                  children: const [
                    LeaderboardBody(),
                    FriendsBody(),
                    GroupsBody(),
                  ],
                ),
    );
  }

  Widget _buildSetupPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌍', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text('Community mein aane ke liye',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            const Text(
                'Apna avatar aur Country/City set karo — taaki '
                'Leaderboard, Friends aur Groups sab kaam kar sakein.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              icon: const Icon(Icons.arrow_forward, color: Colors.white),
              label: const Text('Set Up Now', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LeaderboardProfileScreen()));
                _check();
              },
            ),
          ],
        ),
      ),
    );
  }
}