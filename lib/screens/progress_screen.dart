import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/word_progress_service.dart';
import 'package:quran/quran.dart' as quran;

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with TickerProviderStateMixin {
  // Core stats
  double _percent = 0;
  int _knownCount = 0;
  int _discoveredCount = 0;
  bool _loading = true;

  // Surah completion
  List<int> _completedSurahs = [];
  Map<int, double> _surahProgress = {};

  // Streak & daily stats
  int _currentStreak = 0;
  int _longestStreak = 0;
  int _todayLearned = 0;
  int _weekLearned = 0;
  Map<String, int> _heatmapData = {};

  // Animations
  late AnimationController _ringController;
  late AnimationController _barController;
  late AnimationController _pulseController;
  late Animation<double> _ringAnim;
  late Animation<double> _barAnim;
  late Animation<double> _pulseAnim;

  static const _gold = Color(0xFFD4AF37);
  static const _green = Color(0xFF1B4332);
  static const _teal = Color(0xFF2D6A4F);
  static const _navy = Color(0xFF1A237E);
  static const _emerald = Color(0xFF00897B);

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _barController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _ringAnim =
        CurvedAnimation(parent: _ringController, curve: Curves.easeOutCubic);
    _barAnim =
        CurvedAnimation(parent: _barController, curve: Curves.easeOutCubic);
    _pulseAnim =
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
    _load();
  }

  @override
  void dispose() {
    _ringController.dispose();
    _barController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final known = await WordProgressService.getAllKnownWords();
    final freq = await WordProgressService.getWordFrequencies();
    final p = await WordProgressService.getProgressPercent();
    final surahProg = await WordProgressService.getAllSurahProgress();

    // Find completed surahs (100%)
    final completed = <int>[];
    for (int i = 1; i <= 114; i++) {
      if ((surahProg[i] ?? 0) >= 100) completed.add(i);
    }

    // Streak calculation
    final today = DateTime.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final todayCount = prefs.getInt('daily_$todayKey') ?? 0;

    int streak = 0;
    int longest = prefs.getInt('longest_streak') ?? 0;
    for (int d = 0; d < 365; d++) {
      final day = today.subtract(Duration(days: d));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      if ((prefs.getInt('daily_$key') ?? 0) > 0) {
        streak++;
      } else if (d > 0) {
        break;
      }
    }

    // Week learned
    int weekTotal = 0;
    for (int d = 0; d < 7; d++) {
      final day = today.subtract(Duration(days: d));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      weekTotal += prefs.getInt('daily_$key') ?? 0;
    }

    // Heatmap (last 12 weeks)
    final heatmap = <String, int>{};
    for (int d = 0; d < 84; d++) {
      final day = today.subtract(Duration(days: d));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      heatmap[key] = prefs.getInt('daily_$key') ?? 0;
    }

    if (mounted) {
      setState(() {
        _percent = p;
        _knownCount = known.length;
        _discoveredCount = freq.length;
        _completedSurahs = completed;
        _surahProgress = surahProg;
        _currentStreak = streak;
        _longestStreak = math.max(streak, longest);
        _todayLearned = todayCount;
        _weekLearned = weekTotal;
        _heatmapData = heatmap;
        _loading = false;
      });
    }

    _ringController.forward();
    Future.delayed(
        const Duration(milliseconds: 400), () => _barController.forward());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F0E8),
      appBar: AppBar(
        title: const Column(children: [
          Text('My Progress'),
          Text('تقدمي في القرآن',
              style: TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        centerTitle: true,
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildMainRing(isDark),
                  const SizedBox(height: 16),
                  _buildStreakRow(isDark),
                  const SizedBox(height: 16),
                  _buildStatGrid(isDark),
                  const SizedBox(height: 16),
                  _buildProgressBars(isDark),
                  const SizedBox(height: 16),
                  _buildMilestoneJourney(isDark),
                  const SizedBox(height: 16),
                  _buildHeatmap(isDark),
                  const SizedBox(height: 16),
                  _buildCompletedSurahs(isDark),
                  const SizedBox(height: 16),
                  _buildAchievements(isDark),
                  const SizedBox(height: 16),
                  _buildMotivation(isDark),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ── Main ring ───────────────────────────────────────────────────────────────
  Widget _buildMainRing(bool isDark) {
    return AnimatedBuilder(
      animation: _ringAnim,
      builder: (_, __) => _card(
        isDark,
        child: Column(
          children: [
            Text('﷽',
                style: TextStyle(
                    fontSize: 22, color: _gold.withValues(alpha: 0.9))),
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 2,
                    color: _gold.withValues(alpha: 0.15),
                  ),
                ),
                SizedBox(
                  width: 188,
                  height: 188,
                  child: CircularProgressIndicator(
                    value: (_percent / 100) * _ringAnim.value,
                    strokeWidth: 18,
                    backgroundColor:
                        isDark ? Colors.white12 : Colors.grey.shade200,
                    strokeCap: StrokeCap.round,
                    valueColor: AlwaysStoppedAnimation(
                        _percent > 30 ? _gold : _emerald),
                  ),
                ),
                SizedBox(
                  width: 144,
                  height: 144,
                  child: CircularProgressIndicator(
                    value: (_knownCount / 14870) * _ringAnim.value,
                    strokeWidth: 6,
                    backgroundColor: Colors.transparent,
                    strokeCap: StrokeCap.round,
                    valueColor: const AlwaysStoppedAnimation(_gold),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${(_percent * _ringAnim.value).toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : _green),
                    ),
                    Text('of Quran',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white54
                                : Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _gold.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '$_knownCount words',
                        style: const TextStyle(
                            fontSize: 10,
                            color: _gold,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _shortMotivation(_percent),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: _gold, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  // ── Streak row ──────────────────────────────────────────────────────────────
  Widget _buildStreakRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _miniCard(
            isDark,
            icon: Icons.local_fire_department,
            iconColor: Colors.orange,
            value: '$_currentStreak',
            label: 'Day Streak',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _miniCard(
            isDark,
            icon: Icons.today,
            iconColor: _teal,
            value: '$_todayLearned',
            label: 'Today',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _miniCard(
            isDark,
            icon: Icons.date_range,
            iconColor: _navy,
            value: '$_weekLearned',
            label: 'This Week',
          ),
        ),
      ],
    );
  }

  // ── Stat grid ───────────────────────────────────────────────────────────────
  Widget _buildStatGrid(bool isDark) {
    final items = [
      _S('Known', '$_knownCount', Icons.check_circle, Colors.green),
      _S('Discovered', '$_discoveredCount', Icons.explore, _teal),
      _S('Remaining', '${14870 - _knownCount}', Icons.hourglass_empty,
          Colors.orange),
      _S('Completed\nSurahs', '${_completedSurahs.length}',
          Icons.menu_book, _gold),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: items.map((s) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                s.color.withValues(alpha: 0.18),
                s.color.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: s.color.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                  color: s.color.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(s.icon, color: s.color, size: 26),
              const SizedBox(height: 6),
              Text(s.value,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : _green)),
              Text(s.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white60 : Colors.grey.shade600)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Progress bars ───────────────────────────────────────────────────────────
  Widget _buildProgressBars(bool isDark) {
    final bars = [
      _B('Words Known', _knownCount / 14870, Colors.green),
      _B('Words Discovered', _discoveredCount / 14870, _teal),
      _B('300 Core Words (80% Quran)', math.min(_knownCount / 300, 1.0), _gold),
      _B('Surahs Completed', _completedSurahs.length / 114, _emerald),
    ];

    return AnimatedBuilder(
      animation: _barAnim,
      builder: (_, __) => _card(
        isDark,
        title: 'Progress Breakdown',
        child: Column(
          children: bars.map((b) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(b.label,
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade700)),
                      Text(
                          '${(b.value * 100 * _barAnim.value).toStringAsFixed(1)}%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: b.color)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: b.value * _barAnim.value,
                      backgroundColor:
                          isDark ? Colors.white12 : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(b.color),
                      minHeight: 10,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Milestone journey ───────────────────────────────────────────────────────
  Widget _buildMilestoneJourney(bool isDark) {
    final milestones = [
      _M(50, 'Beginner', Icons.star_outline),
      _M(100, 'Seeker', Icons.auto_stories),
      _M(300, '80% Quran', Icons.workspace_premium),
      _M(500, 'Student', Icons.school),
      _M(1000, 'Scholar', Icons.emoji_events),
      _M(3000, 'Hafiz Path', Icons.military_tech),
      _M(7000, 'Advanced', Icons.diamond),
      _M(14870, 'Complete!', Icons.mosque),
    ];

    return _card(
      isDark,
      title: 'Spiritual Journey',
      child: Column(
        children: [
          const Text(
            'Your path to understanding the Quran',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          // Staircase visual
          SizedBox(
            height: 140,
            child: AnimatedBuilder(
              animation: _barAnim,
              builder: (_, __) => CustomPaint(
                painter: _StaircasePainter(
                  milestones: milestones,
                  known: _knownCount,
                  isDark: isDark,
                  progress: _barAnim.value,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Milestone chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: milestones.map((m) {
              final reached = _knownCount >= m.words;
              return AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) {
                  final isNext = !reached &&
                      milestones.indexOf(m) > 0 &&
                      _knownCount >=
                          milestones[milestones.indexOf(m) - 1].words;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: reached
                          ? _gold.withValues(alpha: 0.2)
                          : isNext
                              ? _emerald
                                  .withValues(alpha: 0.1 + _pulseAnim.value * 0.1)
                              : Colors.transparent,
                      border: Border.all(
                        color: reached
                            ? _gold
                            : isNext
                                ? _emerald
                                : Colors.grey.withValues(alpha: 0.3),
                        width: reached ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(m.icon,
                            size: 14,
                            color: reached
                                ? _gold
                                : isNext
                                    ? _emerald
                                    : Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          m.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: reached
                                ? _gold
                                : isNext
                                    ? _emerald
                                    : Colors.grey,
                            fontWeight: reached
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Heatmap ─────────────────────────────────────────────────────────────────
  Widget _buildHeatmap(bool isDark) {
    final today = DateTime.now();
    final days = List.generate(84, (i) => today.subtract(Duration(days: 83 - i)));

    return _card(
      isDark,
      title: 'Learning Heatmap (12 weeks)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mon Wed Fri Sun',
              style: TextStyle(fontSize: 9, color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 3,
            runSpacing: 3,
            children: days.map((day) {
              final key =
                  '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
              final count = _heatmapData[key] ?? 0;
              Color color;
              if (count == 0) {
                color = isDark ? Colors.white12 : Colors.grey.shade200;
              } else if (count < 5) {
                color = _emerald.withValues(alpha: 0.3);
              } else if (count < 15) {
                color = _emerald.withValues(alpha: 0.6);
              } else if (count < 30) {
                color = _teal;
              } else {
                color = _gold;
              }
              return Tooltip(
                message: '$count words on ${day.day}/${day.month}',
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Less', style: TextStyle(fontSize: 9, color: Colors.grey)),
              const SizedBox(width: 4),
              ...['12', '30', '60', '80'].asMap().entries.map((e) {
                final colors = [
                  Colors.grey.shade200,
                  _emerald.withValues(alpha: 0.3),
                  _teal,
                  _gold,
                ];
                return Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: colors[e.key],
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
              const SizedBox(width: 4),
              const Text('More', style: TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Completed surahs ────────────────────────────────────────────────────────
  Widget _buildCompletedSurahs(bool isDark) {
    if (_completedSurahs.isEmpty) {
      return _card(
        isDark,
        title: 'Completed Surahs',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.auto_stories_outlined,
                    size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(
                  'Complete a surah by learning all its words',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _card(
      isDark,
      title: 'Completed Surahs 🎉',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _completedSurahs.map((id) {
          return AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 64,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    _gold.withValues(
                        alpha: 0.8 + _pulseAnim.value * 0.2),
                    _green.withValues(alpha: 0.9),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: _gold, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: _gold.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: Colors.white, size: 16),
                  const SizedBox(height: 4),
                  Text(
                    '$id',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    quran.getSurahName(id).split('-').last.trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 8),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Achievements ────────────────────────────────────────────────────────────
  Widget _buildAchievements(bool isDark) {
    final badges = [
      _Badge('First Word', Icons.star, _knownCount >= 1, Colors.amber),
      _Badge('10 Words', Icons.military_tech, _knownCount >= 10, _teal),
      _Badge('50 Words', Icons.workspace_premium, _knownCount >= 50, _emerald),
      _Badge('100 Words', Icons.emoji_events, _knownCount >= 100, _gold),
      _Badge('300 Words\n80% Quran', Icons.mosque, _knownCount >= 300, _green),
      _Badge('7-Day Streak', Icons.local_fire_department,
          _currentStreak >= 7, Colors.orange),
      _Badge('30-Day Streak', Icons.whatshot,
          _currentStreak >= 30, Colors.deepOrange),
      _Badge('First Surah', Icons.menu_book,
          _completedSurahs.isNotEmpty, Colors.purple),
    ];

    return _card(
      isDark,
      title: 'Achievements',
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        children: badges.map((b) {
          return Tooltip(
            message: b.label,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: b.unlocked
                    ? b.color.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.1),
                border: Border.all(
                  color: b.unlocked
                      ? b.color
                      : Colors.grey.withValues(alpha: 0.3),
                  width: b.unlocked ? 2 : 1,
                ),
              ),
              child: Icon(
                b.icon,
                color: b.unlocked ? b.color : Colors.grey.withValues(alpha: 0.3),
                size: 28,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Motivation ──────────────────────────────────────────────────────────────
  Widget _buildMotivation(bool isDark) {
    final msg = _getMotivation(_percent);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [_green, _teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: _green.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Text(msg['arabic']!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20, color: _gold, height: 1.8)),
          const SizedBox(height: 8),
          Text(msg['urdu']!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: Colors.white, height: 1.5)),
          const SizedBox(height: 6),
          Text(msg['ref']!,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6),
                  fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  Widget _card(bool isDark, {required Widget child, String? title}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
              color: _green.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark ? Colors.white : _green)),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }

  Widget _miniCard(bool isDark,
      {required IconData icon,
      required Color iconColor,
      required String value,
      required String label}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
        border: Border.all(color: iconColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: iconColor.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : _green)),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color:
                      isDark ? Colors.white54 : Colors.grey.shade600)),
        ],
      ),
    );
  }

  String _shortMotivation(double p) {
    if (p == 0) return 'Begin your journey today';
    if (p < 2) return 'A beautiful start — keep going!';
    if (p < 10) return 'Mashallah! Growing steadily';
    if (p < 30) return 'SubhanAllah! Real progress!';
    if (p < 60) return 'Halfway — you are amazing!';
    if (p < 90) return 'Almost there — incredible!';
    return '🌟 Mashallah — Near Complete!';
  }

  Map<String, String> _getMotivation(double p) {
    if (p < 10) {
      return {
        'arabic': 'اقْرَأْ بِاسْمِ رَبِّكَ الَّذِي خَلَقَ',
        'urdu': 'پڑھو اپنے رب کے نام سے جس نے پیدا کیا',
        'ref': 'Al-Alaq 96:1',
      };
    } else if (p < 40) {
      return {
        'arabic': 'إِنَّ مَعَ الْعُسْرِ يُسْرًا',
        'urdu': 'بیشک مشکل کے ساتھ آسانی ہے',
        'ref': 'Ash-Sharh 94:6',
      };
    } else {
      return {
        'arabic': 'وَمَن يَتَوَكَّلْ عَلَى اللَّهِ فَهُوَ حَسْبُهُ',
        'urdu': 'جو اللہ پر بھروسہ رکھے، وہی اس کے لیے کافی ہے',
        'ref': 'At-Talaq 65:3',
      };
    }
  }
}

// ── Data classes ──────────────────────────────────────────────────────────────
class _S {
  final String label, value;
  final IconData icon;
  final Color color;
  _S(this.label, this.value, this.icon, this.color);
}

class _B {
  final String label;
  final double value;
  final Color color;
  _B(this.label, this.value, this.color);
}

class _M {
  final int words;
  final String label;
  final IconData icon;
  _M(this.words, this.label, this.icon);
}

class _Badge {
  final String label;
  final IconData icon;
  final bool unlocked;
  final Color color;
  _Badge(this.label, this.icon, this.unlocked, this.color);
}

// ── Staircase painter ─────────────────────────────────────────────────────────
class _StaircasePainter extends CustomPainter {
  final List<_M> milestones;
  final int known;
  final bool isDark;
  final double progress;

  _StaircasePainter({
    required this.milestones,
    required this.known,
    required this.isDark,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const gold = Color(0xFFD4AF37);
    const emerald = Color(0xFF00897B);

    final stepW = size.width / milestones.length;
    final maxH = size.height * 0.85;

    for (int i = 0; i < milestones.length; i++) {
      final m = milestones[i];
      final reached = known >= m.words;
      final stepH = (maxH / milestones.length) * (i + 1);
      final x = i * stepW;
      final y = size.height - stepH;

      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = reached
            ? gold.withValues(alpha: 0.7 * progress)
            : (isDark
                ? const Color.fromARGB(31, 110, 19, 19)
                : Colors.grey.shade200);

      final rect = Rect.fromLTWH(x + 2, y, stepW - 4, stepH);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);

      // Border
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        // ignore: deprecated_member_use
        ..color = reached ? gold : Colors.grey.withOpacity(0.3)
        ..strokeWidth = 1.5;
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          borderPaint);
    }

    // Person marker
    final personX = math.min(known, milestones.last.words);
    final idx = milestones.indexWhere((m) => personX < m.words);
    final markerIdx = idx == -1 ? milestones.length - 1 : math.max(0, idx - 1);
    final mx = (markerIdx * stepW + stepW / 2);
    final stepH = (maxH / milestones.length) * (markerIdx + 1);
    final my = size.height - stepH - 16;

    final markerPaint = Paint()
      ..color = emerald
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(mx, my), 10 * progress, markerPaint);
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(mx, my), 5 * progress, innerPaint);
  }

  @override
  bool shouldRepaint(_StaircasePainter old) =>
      old.known != known || old.progress != progress;
}