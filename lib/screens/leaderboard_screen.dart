import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/leaderboard_models.dart';
import '../services/leaderboard_service.dart';
import '../services/social_service.dart';
import '../widgets/friend_mini_profile.dart';
import 'leaderboard_profile_screen.dart';

class LeaderboardBody extends StatefulWidget {
  const LeaderboardBody({super.key});

  /// Bumped by CommunityScreen after the user returns from the Settings
  /// (profile) screen, so the leaderboard tabs refresh with the new
  /// country/city/visibility choices without needing a manual pull-to-refresh.
  static final ValueNotifier<int> refreshNotifier = ValueNotifier<int>(0);

  @override
  State<LeaderboardBody> createState() => _LeaderboardBodyState();
}

class _LeaderboardBodyState extends State<LeaderboardBody>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);

  late TabController _tabs;
  bool _hasProfile = false;
  bool _checking = true;
  String? _checkError;
  String _myCountry = '', _myCity = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    LeaderboardBody.refreshNotifier.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    LeaderboardBody.refreshNotifier.removeListener(_check);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _checkError = null;
    });
    try {
      final has = await LeaderboardService.hasProfile();
      if (has) {
        final doc = await LeaderboardService.getMyProfile();
        _myCountry = (doc?.data()?['country'] ?? '').toString();
        _myCity = (doc?.data()?['city'] ?? '').toString();
      }
      _hasProfile = has;
    } catch (e) {
      debugPrint('LeaderboardBody._check failed: $e');
      _checkError = e.toString();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const Center(child: Text('Leaderboard ke liye login zaroori hai'));
    }
    if (_checking) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }
    if (_checkError != null) {
      return _ErrorRetry(message: _checkError!, onRetry: _check);
    }
    if (!_hasProfile) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              const Text('Leaderboard join karne ke liye pehle apna profile set karo',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _green),
                onPressed: () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LeaderboardProfileScreen()));
                  _check();
                },
                child: const Text('Set Up Profile', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            indicatorColor: _gold,
            labelColor: _green,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: '🌍 Global'),
              Tab(text: '🇮🇳 Country'),
              Tab(text: '🏙️ City'),
              Tab(text: '👥 Friends'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _LbList(
                key: const ValueKey('global'),
                showWeeklyToggle: true,
                fetcher: ({bool weekly = false}) =>
                    LeaderboardService.fetchGlobal(weekly: weekly),
              ),
              _myCountry.isEmpty
                  ? const _EmptyHint(text: 'Profile mein Country set karo')
                  : _LbList(
                      key: ValueKey('country_$_myCountry'),
                      showWeeklyToggle: true,
                      fetcher: ({bool weekly = false}) =>
                          LeaderboardService.fetchCountry(_myCountry, weekly: weekly),
                    ),
              _myCity.isEmpty
                  ? const _EmptyHint(text: 'Profile mein City set karo')
                  : _LbList(
                      key: ValueKey('city_$_myCity'),
                      showWeeklyToggle: true,
                      fetcher: ({bool weekly = false}) =>
                          LeaderboardService.fetchCity(_myCity, weekly: weekly),
                    ),
              _LbList(
                key: const ValueKey('friends'),
                fetcher: ({bool weekly = false}) =>
                    SocialService.getFriendsLeaderboard(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});
  @override
  Widget build(BuildContext context) => Center(child: Text(text));
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            const Text('Kuch galat hua — neeche detail hai',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Reusable list with proper error surfacing + retry, plus an optional
/// All-Time / This-Week toggle for the global/country/city leaderboards.
class _LbList extends StatefulWidget {
  final Future<List<LeaderboardEntry>> Function({bool weekly}) fetcher;
  final bool showWeeklyToggle;
  const _LbList({
    super.key,
    required this.fetcher,
    this.showWeeklyToggle = false,
  });

  @override
  State<_LbList> createState() => _LbListState();
}

class _LbListState extends State<_LbList> {
  late Future<List<LeaderboardEntry>> _future;
  bool _weekly = false;

  @override
  void initState() {
    super.initState();
    _future = widget.fetcher(weekly: _weekly);
  }

  void _setPeriod(bool weekly) {
    if (_weekly == weekly) return;
    setState(() {
      _weekly = weekly;
      _future = widget.fetcher(weekly: weekly);
    });
  }

  /// Forces an immediate push of the current user's latest score before
  /// refetching — this is what makes "pull to refresh" show your own
  /// up-to-date score right away instead of waiting for the periodic sync.
  Future<void> _retry() async {
    await LeaderboardService.pushNow(force: true);
    if (!mounted) return;
    final newFuture = widget.fetcher(weekly: _weekly);
    setState(() => _future = newFuture);
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return Column(
      children: [
        if (widget.showWeeklyToggle)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(child: _periodChip('All-Time', !_weekly, () => _setPeriod(false))),
                const SizedBox(width: 8),
                Expanded(child: _periodChip('This Week', _weekly, () => _setPeriod(true))),
              ],
            ),
          ),
        Expanded(
          child: FutureBuilder<List<LeaderboardEntry>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
              }
              if (snap.hasError) {
                return _ErrorRetry(message: snap.error.toString(), onRetry: _retry);
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Abhi koi data nahi — pehla ban jao! 🌟'),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _retry, child: const Text('Refresh')),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _retry(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final e = list[i];
                    final isMe = e.uid == myUid;
                    final displayPoints = _weekly ? e.weeklyPoints : e.points;
                    return GestureDetector(
                      onTap: () => showFriendMiniProfile(context, e),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFFD4AF37).withValues(alpha: 0.12) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: isMe ? const Color(0xFFD4AF37) : Colors.grey.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            SizedBox(width: 28, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
                            Text(e.avatarEmoji, style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(e.displayName,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      if (e.badgeEmoji.isNotEmpty) ...[
                                        const SizedBox(width: 4),
                                        Text(e.badgeEmoji, style: const TextStyle(fontSize: 13)),
                                      ],
                                    ],
                                  ),
                                  Text('${e.knownWords} words • 🔥 ${e.streak}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                            Row(children: [
                              const Icon(Icons.stars, color: Color(0xFFD4AF37), size: 16),
                              const SizedBox(width: 4),
                              Text('$displayPoints',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
                            ]),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _periodChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1B4332) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.white : Colors.grey.shade600)),
      ),
    );
  }
}