// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/theme_provider.dart';
import '../providers/display_provider.dart';
import '../providers/user_provider.dart';
import '../services/sync_service.dart';
import '../screens/auth_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});
  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);
  static const _teal = Color(0xFF2D6A4F);

  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = 'v${info.version}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final display = context.watch<DisplayProvider>();
    final user = context.watch<UserProvider>();
    final isDark = theme.isDark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F0E8),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: _green,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_green, _teal],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: _gold.withValues(alpha: 0.3),
                            backgroundImage: user.photoUrl.isNotEmpty
                                ? NetworkImage(user.photoUrl)
                                : null,
                            child: user.photoUrl.isEmpty
                                ? Text(
                                    user.displayName.isNotEmpty
                                        ? user.displayName[0].toUpperCase()
                                        : 'Q',
                                    style: const TextStyle(
                                        fontSize: 36,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                  color: _gold, shape: BoxShape.circle),
                              child: const Icon(Icons.edit,
                                  size: 14, color: _green),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(user.displayName,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      Text(user.email,
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
              ),
              title: const Text('Profile & Settings',
                  style: TextStyle(fontSize: 14)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ── Display Preview ───────────────────────────────────
                  _buildDisplayPreview(display, isDark),
                  const SizedBox(height: 16),

                  // ── Display Settings ──────────────────────────────────
                  _buildDisplaySettings(display, theme, isDark),
                  const SizedBox(height: 16),

                  // ── Profile Settings ──────────────────────────────────
                  _buildProfileSettings(user, isDark),
                  const SizedBox(height: 16),

                  // ── Notifications ─────────────────────────────────────
                  _buildSection(isDark, title: 'Reminders', items: [
                    _buildTile(isDark,
                        icon: Icons.notifications_active,
                        iconColor: Colors.orange,
                        title: 'Daily Reminder',
                        subtitle: 'Coming Soon',
                        onTap: null),
                  ]),
                  const SizedBox(height: 16),

                  // ── App ───────────────────────────────────────────────
                  _buildSection(isDark, title: 'App', items: [
                    _buildTile(isDark,
                        icon: Icons.share,
                        iconColor: _teal,
                        title: 'Share App',
                        subtitle: 'Coming Soon',
                        onTap: null),
                    _buildTile(isDark,
                        icon: Icons.star_rate,
                        iconColor: _gold,
                        title: 'Rate App',
                        subtitle: 'Available after Play Store release',
                        onTap: null),
                    _buildTile(isDark,
                        icon: Icons.volunteer_activism,
                        iconColor: Colors.red,
                        title: 'Donate',
                        subtitle: 'Coming Soon',
                        onTap: null),
                    _buildTile(isDark,
                        icon: Icons.shopping_bag,
                        iconColor: Colors.purple,
                        title: 'Purchase Premium',
                        subtitle: 'Coming Soon',
                        onTap: null),
                  ]),
                  const SizedBox(height: 16),

                  // ── Support ───────────────────────────────────────────
                  _buildSection(isDark, title: 'Support & Info', items: [
                    _buildTile(isDark,
                        icon: Icons.new_releases,
                        iconColor: Colors.blue,
                        title: "What's New",
                        subtitle: _appVersion,
                        onTap: () => _showWhatsNew()),
                    _buildTile(isDark,
                        icon: Icons.tour,
                        iconColor: _teal,
                        title: 'App Tour',
                        subtitle: 'Coming Soon',
                        onTap: null),
                    _buildTile(isDark,
                        icon: Icons.help_outline,
                        iconColor: Colors.orange,
                        title: 'FAQ',
                        subtitle: 'Frequently Asked Questions',
                        onTap: () => _showFAQ()),
                    _buildTile(isDark,
                        icon: Icons.support_agent,
                        iconColor: Colors.green,
                        title: 'Support',
                        subtitle: 'support@qurankalima.com',
                        onTap: () => _email()),
                    _buildTile(isDark,
                        icon: Icons.camera_alt,
                        iconColor: Colors.pink,
                        title: 'Instagram',
                        subtitle: '@qurankalima',
                        onTap: () => _instagram()),
                  ]),
                  const SizedBox(height: 16),

                  // ── Cloud Sync ────────────────────────────────────────
                  _buildSyncCard(isDark, user),
                  const SizedBox(height: 16),

                  // ── Account ───────────────────────────────────────────
                  _buildSection(isDark, title: 'Account', items: [
                    _buildTile(isDark,
                        icon: Icons.lock,
                        iconColor: Colors.grey,
                        title: 'Change Password',
                        subtitle: 'Send reset email',
                        onTap: () => _changePassword()),
                    _buildTile(isDark,
                        icon: Icons.logout,
                        iconColor: Colors.orange,
                        title: 'Log Out',
                        onTap: () => _logout()),
                    _buildTile(isDark,
                        icon: Icons.delete_forever,
                        iconColor: Colors.red,
                        title: 'Delete Account',
                        titleColor: Colors.red,
                        onTap: () => _deleteAccount()),
                  ]),
                  const SizedBox(height: 32),

                  Text('Quran Kalima $_appVersion',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              isDark ? Colors.white38 : Colors.grey.shade400)),
                  const SizedBox(height: 4),
                  Text('Made with ❤️ for Quran learners',
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              isDark ? Colors.white24 : Colors.grey.shade400)),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Display preview ───────────────────────────────────────────────────────
  Widget _buildDisplayPreview(DisplayProvider display, bool isDark) {
    return _card(isDark,
        title: 'Preview',
        titleIcon: Icons.visibility,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D1B12) : const Color(0xFFFDF8F0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gold.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(
                'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: _arabicStyle(display),
              ),
              const SizedBox(height: 8),
              Text(
                'اللہ کے نام سے جو بڑا مہربان نہایت رحم والا ہے',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: TextStyle(
                  // Urdu Nastaliq font
                  fontFamily: 'JameelNoori',
                  fontSize: display.urduFontSize,
                  color: isDark ? Colors.white70 : _teal,
                  height: 1.8,
                ),
              ),
            ],
          ),
        ));
  }

  TextStyle _arabicStyle(DisplayProvider display) {
    switch (display.arabicFont) {
      case 'indopak':
        return TextStyle(
            fontFamily: 'IndoPak',
            fontSize: display.arabicFontSize,
            height: 1.8);
      case 'noorehuda':
        return TextStyle(
            fontFamily: 'NoorehudaFont',
            fontSize: display.arabicFontSize,
            height: 1.8);
      default:
        return GoogleFonts.amiriQuran(
            fontSize: display.arabicFontSize, height: 1.8);
    }
  }

  // ── Display settings ──────────────────────────────────────────────────────
  Widget _buildDisplaySettings(
      DisplayProvider display, ThemeProvider theme, bool isDark) {
    return _card(isDark,
        title: 'Display',
        titleIcon: Icons.text_fields,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(theme.isDark ? Icons.dark_mode : Icons.light_mode,
                      color: _gold, size: 20),
                  const SizedBox(width: 8),
                  const Text('Dark Mode'),
                ]),
                Switch(
                  value: theme.isDark,
                  onChanged: (_) => theme.toggleTheme(),
                  activeColor: _green,
                ),
              ],
            ),
            const Divider(),
            const Text('Arabic Font',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _fontChip('Noorehuda', 'noorehuda', display),
                _fontChip('Uthmani', 'uthmani', display),
                _fontChip('Indo-Pak', 'indopak', display),
              ],
            ),
            const SizedBox(height: 14),
            _slider(
              label: 'Arabic Size',
              value: display.arabicFontSize,
              min: 18,
              max: 80,
              onChanged: display.setArabicSize,
              isDark: isDark,
            ),
            _slider(
              label: 'Urdu Size',
              value: display.urduFontSize,
              min: 10,
              max: 40,
              onChanged: display.setUrduSize,
              isDark: isDark,
            ),
          ],
        ));
  }

  Widget _fontChip(String label, String key, DisplayProvider display) {
    final selected = display.arabicFont == key;
    return GestureDetector(
      onTap: () => display.setArabicFont(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _green : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _green : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : Colors.grey,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required Function(double) onChanged,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.grey.shade700)),
            Text(value.toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: _gold)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions ?? ((max - min) * 2).round(),
          activeColor: _green,
          inactiveColor: Colors.grey.shade300,
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ── Profile settings ──────────────────────────────────────────────────────
  Widget _buildProfileSettings(UserProvider user, bool isDark) {
    final nameCtrl = TextEditingController(text: user.displayName);
    return _card(isDark,
        title: 'Profile',
        titleIcon: Icons.person,
        child: Column(
          children: [
            _buildTile(isDark,
                icon: Icons.person,
                iconColor: _teal,
                title: 'Name',
                subtitle: user.displayName,
                onTap: () => _editField('Name', nameCtrl, (v) {
                      user.updateProfile({'name': v});
                    })),
            _buildTile(isDark,
                icon: Icons.wc,
                iconColor: Colors.purple,
                title: 'Gender',
                subtitle: user.gender.isEmpty ? 'Not set' : user.gender,
                onTap: () => _pickGender(user)),
            _buildTile(isDark,
                icon: Icons.flag,
                iconColor: Colors.blue,
                title: 'Daily Goal',
                subtitle: '${user.dailyGoal} words/day',
                onTap: () => _setDailyGoal(user)),
            _buildTile(isDark,
                icon: Icons.email,
                iconColor: Colors.red,
                title: 'Email',
                subtitle: user.email,
                onTap: null),
          ],
        ));
  }

  // ── Sync card ─────────────────────────────────────────────────────────────
  Widget _buildSyncCard(bool isDark, UserProvider user) {
    return StreamBuilder<SyncStatus>(
      stream: SyncService.statusStream,
      initialData: SyncService.lastStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncStatus.idle;
        final (icon, color, label) = switch (status) {
          SyncStatus.syncing => (Icons.sync, Colors.blue, 'Syncing...'),
          SyncStatus.done => (
              Icons.cloud_done,
              Colors.green,
              'Synced to cloud'
            ),
          SyncStatus.error => (
              Icons.cloud_off,
              Colors.red,
              SyncService.lastError != null
                  ? 'Error: ${SyncService.lastError}'
                  : 'Sync failed — tap to retry'
            ),
          SyncStatus.idle => (
              Icons.cloud_upload_outlined,
              _teal,
              user.isLoggedIn
                  ? 'Sync progress to cloud'
                  : 'Login to enable sync'
            ),
        };
        return _card(
          isDark,
          title: 'Cloud Backup',
          titleIcon: Icons.cloud,
          child: Column(
            children: [
              Row(
                children: [
                  AnimatedRotation(
                    turns: status == SyncStatus.syncing ? 1 : 0,
                    duration: const Duration(seconds: 1),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                  if (status != SyncStatus.syncing)
                    TextButton(
                      onPressed: () async {
                        if (!user.isLoggedIn) {
                          // Not logged in — go to auth screen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const AuthScreen()),
                          );
                          return;
                        }
                        await SyncService.syncUp();
                      },
                      style: TextButton.styleFrom(foregroundColor: _teal),
                      child: Text(user.isLoggedIn ? 'Sync Now' : 'Login'),
                    ),
                ],
              ),
              if (user.isLoggedIn) ...[
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      'Auto-syncs 3 seconds after any change',
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.grey),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection(bool isDark,
      {required String title, required List<Widget> items}) {
    return _card(isDark,
        title: title,
        titleIcon: Icons.settings,
        child: Column(children: items));
  }

  Widget _card(bool isDark,
      {required String title,
      required IconData titleIcon,
      required Widget child}) {
    return Container(
      width: double.infinity,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                  bottom: BorderSide(color: _gold.withValues(alpha: 0.2))),
            ),
            child: Row(
              children: [
                Icon(titleIcon, color: _gold, size: 18),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : _green)),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  Widget _buildTile(bool isDark,
      {required IconData icon,
      required Color iconColor,
      required String title,
      String? subtitle,
      Color? titleColor,
      VoidCallback? onTap}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: iconColor.withValues(alpha: 0.15),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: 14,
              color: titleColor ?? (isDark ? Colors.white : Colors.black87))),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(
                  fontSize: 12, color: isDark ? Colors.white54 : Colors.grey))
          : null,
      trailing: onTap != null
          ? Icon(Icons.chevron_right,
              color: isDark ? Colors.white38 : Colors.grey.shade300)
          : null,
      onTap: onTap,
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _editField(
      String label, TextEditingController ctrl, Function(String) onSave) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Edit $label'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            onPressed: () {
              onSave(ctrl.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _pickGender(UserProvider user) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Select Gender'),
        children: ['Male', 'Female', 'Prefer not to say'].map((g) {
          return SimpleDialogOption(
            onPressed: () {
              user.updateProfile({'gender': g});
              Navigator.pop(context);
            },
            child: Text(g),
          );
        }).toList(),
      ),
    );
  }

  void _setDailyGoal(UserProvider user) {
    int goal = user.dailyGoal;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Daily Word Goal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$goal words/day',
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _green)),
              Slider(
                value: goal.toDouble(),
                min: 1,
                max: 50,
                divisions: 49,
                activeColor: _green,
                onChanged: (v) => setD(() => goal = v.round()),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _green),
              onPressed: () {
                user.updateProfile({'dailyGoal': goal});
                Navigator.pop(context);
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showWhatsNew() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("What's New"),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Word-by-word Urdu translation'),
            Text('• Long press to mark words as known'),
            Text('• Vocabulary screen with swipe gestures'),
            Text('• Progress dashboard with heatmap'),
            Text('• Font customization'),
            Text('• Cloud sync across devices'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'))
        ],
      ),
    );
  }

  void _showFAQ() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Color(0xFF1B4332)),
            SizedBox(width: 8),
            Text('FAQ'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _faqItem(
                'How does the Flashcard system work?',
                'Quran Kalima uses Spaced Repetition (SRS). Words you know are shown less often. Words you struggle with appear more frequently. This is scientifically proven to maximize memory retention. Swipe right (Known) or left (Unknown) on each card.',
              ),
              const Divider(),
              _faqItem(
                'How do I mark a word as known in the Quran Reader?',
                'Long press any word in the Surah Reader to toggle it between Known and Unknown. Known words become faded so you can focus on words you have not learned yet. The count badge on each ayah updates instantly.',
              ),
              const Divider(),
              _faqItem(
                'Will my progress sync across devices?',
                'Yes. Make sure you are logged in with the same account on both devices. Your known words, flashcard progress, bookmarks, and reading position are all backed up to the cloud and restored automatically when you log in.',
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4332)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _faqItem(String question, String answer) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF1B4332)),
          ),
          const SizedBox(height: 6),
          Text(
            answer,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }



  Future<void> _email() async {
    final url = Uri.parse('mailto:support@qurankalima.com');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('support@qurankalima.com')));
      }
    }
  }

  Future<void> _instagram() async {
    final url = Uri.parse('https://instagram.com/qurankalima');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('instagram.com/qurankalima')));
      }
    }
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No email associated with account')));
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Password reset email sent to ${user.email}'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await context.read<UserProvider>().signOut();
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
            'This will permanently delete your account and all progress. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await SyncService.deleteCloudData();
        await FirebaseAuth.instance.currentUser?.delete();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }
}
