import 'package:flutter/material.dart';
import 'friends_screen.dart';
import 'groups_screen.dart';
import 'leaderboard_screen.dart';

/// Bottom-nav tab: houses Leaderboard, Friends, and Groups as sub-tabs so
/// only ONE new destination is added to the main navigation bar.
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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
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
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _gold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.leaderboard), text: 'Leaderboard'),
            Tab(icon: Icon(Icons.people), text: 'Friends'),
            Tab(icon: Icon(Icons.groups), text: 'Groups'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          LeaderboardScreen(),
          FriendsBody(),
          GroupsBody(),
        ],
      ),
    );
  }
}
