import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/leaderboard_models.dart';
import '../services/leaderboard_service.dart';
import '../services/social_service.dart';
import 'leaderboard_profile_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);

  late TabController _tabs;
  bool _hasProfile = false;
  bool _checking = true;
  String _myCountry = '', _myCity = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _check();
  }

  Future<void> _check() async {
    final has = await LeaderboardService.hasProfile();
    if (has) {
      final doc = await LeaderboardService.getMyProfile();
      _myCountry = (doc?.data()?['country'] ?? '').toString();
      _myCity = (doc?.data()?['city'] ?? '').toString();
    }
    if (mounted) setState(() {
      _hasProfile = has;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leaderboard'), backgroundColor: _green,
            foregroundColor: Colors.white),
        body: const Center(child: Text('Leaderboard ke liye login zaroori hai')),
      );
    }
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: _gold)));
    }
    if (!_hasProfile) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leaderboard'), backgroundColor: _green,
            foregroundColor: Colors.white),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏆', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                const Text('Leaderboard join karne ke liye pehle apna profile set karo'),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _green),
                  onPressed: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const LeaderboardProfileScreen()));
                    _check();
                  },
                  child: const Text('Set Up Profile',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LeaderboardProfileScreen()));
              _check();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _gold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: '🌍 Global'),
            Tab(text: '🇮🇳 Country'),
            Tab(text: '🏙️ City'),
            Tab(text: '👥 Friends'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _LbList(future: LeaderboardService.fetchGlobal()),
          _myCountry.isEmpty
              ? const _EmptyHint(text: 'Profile mein Country set karo')
              : _LbList(future: LeaderboardService.fetchCountry(_myCountry)),
          _myCity.isEmpty
              ? const _EmptyHint(text: 'Profile mein City set karo')
              : _LbList(future: LeaderboardService.fetchCity(_myCity)),
          _LbList(future: SocialService.getFriendsLeaderboard()),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});
  @override
  Widget build(BuildContext context) => Center(child: Text(text));
}

class _LbList extends StatelessWidget {
  final Future<List<LeaderboardEntry>> future;
  const _LbList({required this.future});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return FutureBuilder<List<LeaderboardEntry>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const Center(child: Text('Abhi koi data nahi — pehla ban jao! 🌟'));
        }
        return RefreshIndicator(
          onRefresh: () async {},
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final e = list[i];
              final isMe = e.uid == myUid;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFFD4AF37).withValues(alpha: 0.12) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isMe
                          ? const Color(0xFFD4AF37)
                          : Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                        width: 28,
                        child: Text('${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold))),
                    Text(e.avatarEmoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.displayName,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('${e.knownWords} words • 🔥 ${e.streak}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    Row(children: [
                      const Icon(Icons.stars, color: Color(0xFFD4AF37), size: 16),
                      const SizedBox(width: 4),
                      Text('${e.points}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
                    ]),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}