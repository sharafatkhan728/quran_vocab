// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'dart:async';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/theme_provider.dart';
import '../providers/display_provider.dart';
import '../providers/user_provider.dart';
import '../services/sync_service.dart';
import '../screens/auth_screen.dart';
import '../services/word_glossary_service.dart';
import 'notification_settings_screen.dart';
import 'feedback_screen.dart';
import '../services/translation_service.dart';

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
  bool _isUploadingPhoto = false;

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
  void dispose() {
    // Safety net: clear loading state if widget is disposed mid-upload
    if (_isUploadingPhoto && mounted) {
      setState(() => _isUploadingPhoto = false);
    }
    super.dispose();
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
                          if (_isUploadingPhoto)
                            const Positioned(
                              bottom: 0,
                              right: 0,
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          else
                            GestureDetector(
                              onTap: () => _pickAndUploadPhoto(),
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
                  style: TextStyle(fontSize: 14, color: Colors.white)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Column(
                children: [
                  _buildDisplayPreview(display, isDark),
                  const SizedBox(height: 5),
                  _buildDisplaySettings(display, theme, isDark),
                  const SizedBox(height: 5),
                  _buildProfileSettings(user, isDark),
                  const SizedBox(height: 5),
                  _buildSection(isDark, title: 'Reminders', items: [
                    _buildTile(isDark,
                        icon: Icons.notifications_active,
                        iconColor: Colors.orange,
                        title: 'Notifications',
                        subtitle: 'Review reminders, streak, weekly progress',
                        onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const NotificationSettingsScreen()),
                            )),
                  ]),
                  const SizedBox(height: 5),
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
                        subtitle: 'Support this app',
                        onTap: () => _showDonateDialog()),
                    _buildTile(isDark,
                        icon: Icons.shopping_bag,
                        iconColor: Colors.purple,
                        title: 'Purchase Premium',
                        subtitle: 'Coming Soon',
                        onTap: null),
                  ]),
                  const SizedBox(height: 5),
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
                        subtitle: 'Walkthrough of key features',
                        onTap: () => _startAppTour()),
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
                        icon: Icons.feedback,
                        iconColor: Colors.blue,
                        title: 'Feedback & Bug Report',
                        subtitle: 'Send screenshots, suggestions or bugs',
                        onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const FeedbackScreen()),
                            )),
                    _buildTile(isDark,
                        icon: Icons.camera_alt,
                        iconColor: Colors.pink,
                        title: 'Instagram',
                        subtitle: '@qurankalima',
                        onTap: () => _instagram()),
                  ]),
                  const SizedBox(height: 5),
                  _buildSyncCard(isDark, user),
                  const SizedBox(height: 5),
                  _buildSection(isDark, title: 'Account', items: [
                    _buildTile(isDark,
                        icon: Icons.lock,
                        iconColor: Colors.grey,
                        title: 'Change Password',
                        subtitle: 'Update your password',
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
    return _card(
      isDark,
      title: 'Preview',
      titleIcon: Icons.visibility,
      child: Center(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D1B12) : const Color(0xFFFDF8F0),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: _gold.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
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
                  fontFamily: 'JameelNoori',
                  fontSize: display.urduFontSize,
                  color: isDark ? Colors.white70 : _teal,
                  height: 1.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _arabicStyle(DisplayProvider display) {
    switch (display.arabicFont) {
      case 'indopak':
        return TextStyle(
          fontFamily: 'IndoPak',
          fontSize: display.arabicFontSize,
          height: 1.8,
        );
      case 'noorehuda':
        return TextStyle(
          fontFamily: 'NoorehudaFont',
          fontSize: display.arabicFontSize,
          height: 1.8,
        );
      default:
        return GoogleFonts.amiriQuran(
          fontSize: display.arabicFontSize,
          height: 1.8,
        );
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
            const Divider(),
            const Text('Word-by-Word Language',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: WordGlossaryService.langNotifier,
              builder: (_, lang, __) => Wrap(
                spacing: 8,
                children: [
                  _wbwChip('Urdu', 'ur', lang),
                  _wbwChip('English', 'en', lang),
                  _wbwChip('Hindi', 'hi', lang),
                ],
              ),
            ),
            const Divider(height: 24),
            const Text('Ayah Translation Language',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: TranslationLangService.langNotifier,
              builder: (_, scholar, __) => Wrap(
                spacing: 8,
                children: [
                  _translationChip('Urdu', 'ur.bayanulquran', scholar),
                  _translationChip('English', 'en.sahihintl', scholar),
                  _translationChip('Hindi', 'hi.azizulhaque', scholar),
                ],
              ),
            ),
          ],
        ));
  }

  Widget _translationChip(String label, String key, String selected) {
    final sel = selected == key;
    return GestureDetector(
      onTap: () => TranslationLangService.setLang(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _teal : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? _teal : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : Colors.grey,
                fontSize: 12,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
      ),
    );
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

  Widget _wbwChip(String label, String key, String selected) {
    final sel = selected == key;
    return GestureDetector(
      onTap: () async {
        await WordGlossaryService.setLanguage(key);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _green : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? _green : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : Colors.grey,
                fontSize: 12,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
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
          style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87),
          decoration: InputDecoration(
            hintText: label,
            hintStyle: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white38
                    : Colors.grey),
          ),
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
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _wtnHeading('🕌', 'Purpose'),
                _wtnPara(
                    'Quran Kalima is designed to help you read the Quran with understanding. '
                    'It combines Quran reading with Arabic vocabulary learning so you can '
                    'gradually recognize and remember the words you encounter in the Book of Allah.'),
                const SizedBox(height: 14),

                _wtnHeading('📖', 'The Best Way to Use This App'),
                _wtnItem('Open any Surah and read naturally — you will see Arabic words with Urdu, English, or Hindi meanings below each word.'),
                _wtnItem('Tap any unfamiliar word to see its meaning, root, and grammatical information in detail.'),
                _wtnItem('Long press a word to mark it as "Known" — known words fade so you can focus on new ones.'),
                _wtnItem('Visit the Vocabulary screen to explore all Quranic words, sorted by frequency or alphabet.'),
                _wtnItem('Use Flash Cards daily to actively recall meanings instead of only passively reading them.'),
                _wtnItem('Complete your Daily Goal in Settings — even a small number of words every day builds lasting knowledge.'),
                const SizedBox(height: 14),

                _wtnHeading('📚', 'Quran Reader & Word-by-Word Meaning'),
                _wtnPara(
                    'Every Surah is displayed with word-by-word translation. '
                    'You can switch between Urdu, English, and Hindi meanings using the language selector. '
                    'Each word carries its own color based on its grammatical type — red for verbs, '
                    'blue for nouns, green for prepositions, and more — helping you visually distinguish word types as you read.'),
                const SizedBox(height: 10),
                _wtnItem('Tap a word → see its full meaning, root letters, and grammar segments.'),
                _wtnItem('Long press a word → toggle Known / Unknown instantly.'),
                _wtnItem('Bookmark any Ayah for quick return later.'),
                const SizedBox(height: 14),

                _wtnHeading('🔍', 'Explore Every Word'),
                _wtnPara(
                    'When you tap a word, you see its meaning, root letters, and grammatical segments. '
                    'Tap "Learn More About This Word" to explore deeper — find other words that share the same root, '
                    'see how the word appears across the entire Quran, and understand its morphology (prefixes, suffixes, verb form).'),
                const SizedBox(height: 10),
                _wtnItem('Root letters reveal the family of related words in the Quran.'),
                _wtnItem('Grammar segments show prefixes, suffixes, and part of speech with color coding.'),
                _wtnItem('Word occurrences show every place the same root appears in the Quran.'),
                const SizedBox(height: 14),

                _wtnHeading('🃏', 'Flash Cards — Active Recall'),
                _wtnPara(
                    'Reading a meaning is recognition. Trying to remember the meaning before you flip the card is active recall — '
                    'and active recall is how words stick in your long-term memory.'),
                const SizedBox(height: 10),
                _wtnItem('Look at the Arabic word first. Try to remember its meaning before tapping to flip.'),
                _wtnItem('Swipe right (or tap Known) when you remembered it confidently.'),
                _wtnItem('Swipe left (or tap Unknown) when you could not recall it.'),
                _wtnItem('After finishing a session, tap "Review More Cards" to continue without leaving the Flash Card screen.'),
                const SizedBox(height: 14),

                _wtnHeading('🔄', 'Spaced Repetition — Smart Review'),
                _wtnPara(
                    'The app does not show words randomly. Words you remember well appear less often. '
                    'Words you find difficult appear more frequently. This is called Spaced Repetition — '
                    'a scientifically proven method that helps you retain vocabulary over the long term.'),
                const SizedBox(height: 10),
                _wtnItem('Review cards (overdue or failed) are shown first before new vocabulary.'),
                _wtnItem('New cards fill the remaining slots in your Daily Goal.'),
                _wtnItem('The goal is lasting retention, not just seeing many words once.'),
                const SizedBox(height: 14),

                _wtnHeading('✅', 'Known vs Unknown — Be Honest'),
                _wtnPara(
                    'Marking "Known" only when you genuinely remembered the word helps the review system work correctly. '
                    'If you guess correctly but did not truly know the word, the app will show it to you again soon — '
                    'and that is a good thing. It means you are learning.'),
                const SizedBox(height: 10),
                _wtnItem('Known = You recalled the meaning confidently without looking.'),
                _wtnItem('Unknown = You did not know it, or had to guess.'),
                const SizedBox(height: 14),

                _wtnHeading('📊', 'Your Progress'),
                _wtnPara(
                    'The Progress screen shows your learning journey at a glance — how many words you have learned, '
                    'your current streak, your longest streak, and a heatmap of your activity over the past 12 weeks. '
                    'Points are earned each time you complete a Flash Card session.'),
                const SizedBox(height: 10),
                _wtnItem('Known Words — total words you have marked as learned.'),
                _wtnItem('Streak — consecutive days you have reviewed.'),
                _wtnItem('Heatmap — visual pattern of your daily activity.'),
                _wtnItem('Points — earned through consistent Flash Card practice.'),
                const SizedBox(height: 14),

                _wtnHeading('🔑', 'Key Features'),
                _wtnItem('Quran Reader — 114 Surahs with word-by-word translation.'),
                _wtnItem('Three Languages — Urdu, English, and Hindi meanings.'),
                _wtnItem('Morphology & Roots — explore word origins and grammar for every word.'),
                _wtnItem('Vocabulary Screen — browse all Quranic words with frequency and status.'),
                _wtnItem('Flash Cards — spaced repetition with Known / Unknown tracking.'),
                _wtnItem('Bookmarks — save your favourite Ayahs for quick access.'),
                _wtnItem('Reading Progress — the app remembers where you left off in each Surah.'),
                _wtnItem('Search — find Surahs or words quickly.'),
                _wtnItem('Font Customisation — choose IndoPak, Noorehuda, or Amiri Quran script.'),
                _wtnItem('Dark & Light Theme — easy on the eyes day and night.'),
                _wtnItem('Cloud Sync — your progress follows you across devices when you sign in.'),
                const SizedBox(height: 14),

                _wtnHeading('🌟', 'A Simple Daily Routine'),
                _wtnPara('Here is a practical way to use Quran Kalima every day:'),
                _wtnItem('Open the Quran Reader and read a few Ayahs of any Surah.'),
                _wtnItem('Tap any word you do not know to read its meaning and root.'),
                _wtnItem('Go to Flash Cards and complete your Daily Goal — review first, then learn new words.'),
                _wtnItem('If a word feels difficult, mark it Unknown — the app will bring it back sooner.'),
                _wtnItem('Check your Progress screen to see your streak and consistency.'),
                const SizedBox(height: 14),

                _wtnHeading('💡', 'A Note on Consistency'),
                _wtnPara(
                    'Learning 5 words a day with honest review is far more powerful than rushing through 50 words and forgetting them all. '
                    'The app is built for steady, consistent progress. Set a Daily Goal you can actually keep — '
                    'even a small number — and trust the spaced repetition system to help those words stay with you for life.'),
                const SizedBox(height: 8),
                Text(
                  'بارک اللہ فیک — May Allah bless your efforts.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.amiriQuran(
                      fontSize: 16, color: _gold, height: 1.6),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _wtnHeading(String emoji, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _green),
          ),
        ],
      ),
    );
  }

  Widget _wtnPara(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5, height: 1.6, color: Colors.black87),
      ),
    );
  }

  Widget _wtnItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ',
              style: TextStyle(fontSize: 14, color: Colors.black87)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, height: 1.5, color: Colors.black87),
            ),
          ),
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
            child: const Text('Got it', style: TextStyle(color: Colors.white)),
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
    final Uri url = Uri.parse('https://www.instagram.com/qurankalima/');
    final bool launched = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Instagram')),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. PROFILE IMAGE UPLOAD — with cropping
  // ═══════════════════════════════════════════════════════════════════════════

  /// Opens source picker, then crops, then uploads.
  /// Copies the picked image to a temp file first so image_cropper can
  /// access it reliably on Android 10+ (scoped storage).
  Future<void> _pickAndUploadPhoto() async {
    if (_isUploadingPhoto) return;

    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose Photo'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: const Row(
              children: [Icon(Icons.camera_alt, color: Colors.blue), SizedBox(width: 12), Text('Camera')],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const Row(
              children: [Icon(Icons.photo_library, color: Colors.green), SizedBox(width: 12), Text('Gallery')],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    // User cancelled the source dialog
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 90,
    );
    // User cancelled the image picker
    if (picked == null) return;

    // Copy to a temp file so image_cropper can read it on Android 10+
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/profile_pic_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(picked.path).copy(tempFile.path);
    final sourcePath = tempFile.path;

    // ── Crop step (with timeout fallback) ──────────────────────────────────
    late String cropPath;
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Profile Photo',
            toolbarColor: _green,
            toolbarWidgetColor: Colors.white,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.original,
            ],
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'Crop Profile Photo',
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.original,
            ],
          ),
        ],
      ).timeout(const Duration(seconds: 30));
      if (cropped != null) {
        cropPath = cropped.path;
      } else {
        // User cancelled crop — fall back to the copied temp file
        cropPath = sourcePath;
      }
    } on TimeoutException {
      // Crop activity hung (known on some Android 13+ devices) — use original
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Crop timed out — uploading original photo'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      cropPath = sourcePath;
    } catch (e) {
      // Crop failed for any reason — fall back to original image
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open crop editor: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      cropPath = sourcePath;
    }

    // ── Upload ─────────────────────────────────────────────────────────────
    await _uploadCroppedImage(cropPath);
  }

  /// Uploads a cropped image file to Firebase Storage and updates profile.
  Future<void> _uploadCroppedImage(String filePath) async {
    // Re-check mounted before starting async work
    if (!mounted) return;
    setState(() => _isUploadingPhoto = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) _showError('Not logged in');
        return;
      }

      final ext = filePath.split('.').last.toLowerCase();
      // Correct MIME types — 'image/jpg' is not valid; use 'image/jpeg'
      final mimeType = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      final safeExt = ext == 'jpeg' ? 'jpg' : ext;
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child('$uid.$safeExt');

      final task = ref.putFile(
        File(filePath),
        SettableMetadata(contentType: mimeType),
      );
      // Show upload progress in a snackbar
      task.snapshotEvents.listen((event) {
        if (!mounted) return;
        final bytes = event.bytesTransferred;
        final total = event.totalBytes;
        if (total > 0) {
          final pct = (bytes / total * 100).toStringAsFixed(0);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Uploading… $pct%'),
              duration: const Duration(seconds: 1),
              backgroundColor: _green,
            ),
          );
        }
      });
      await task;
      final downloadUrl = await ref.getDownloadURL();

      // Update Firebase Auth profile photoURL
      await FirebaseAuth.instance.currentUser?.updatePhotoURL(downloadUrl);

      // Update Firestore profile document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'photoUrl': downloadUrl}, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.contains('storage/not-allowed') ||
            msg.contains('permission_denied')) {
          msg = 'Storage permission denied. Check Firebase Console rules.';
        } else if (msg.contains('network') || msg.contains('connection')) {
          msg = 'Network error. Please check your connection and try again.';
        }
        _showError(msg);
      }
    } finally {
      // Always clear loading state — use mounted guard to avoid setState after dispose
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. DONATE — shows donation info dialog (report in comments below)
  // ═══════════════════════════════════════════════════════════════════════════

  void _showDonateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const _DonateDialog(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. APP TOUR — lightweight multi-step overlay
  // ═══════════════════════════════════════════════════════════════════════════

  void _startAppTour() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _AppTourDialog(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. CHANGE PASSWORD — re-auth + update flow
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _changePassword() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showError('You are not logged in.');
      return;
    }
    // Email-only accounts need re-authentication to change password
    final isEmailAuth = currentUser.providerData
        .any((p) => p.providerId == 'password');
    if (!isEmailAuth) {
      _showError('Password change is only available for email accounts.');
      return;
    }

    final currentPw = TextEditingController();
    final newPw = TextEditingController();
    final confirmPw = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Current password
                TextField(
                  controller: currentPw,
                  obscureText: obscureCurrent,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    suffixIcon: IconButton(
                      icon: Icon(obscureCurrent
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setDlg(
                          () => obscureCurrent = !obscureCurrent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // New password
                TextField(
                  controller: newPw,
                  obscureText: obscureNew,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    helperText: 'At least 6 characters',
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setDlg(
                          () => obscureNew = !obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Confirm new password
                TextField(
                  controller: confirmPw,
                  obscureText: obscureConfirm,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    errorText: _pwMatchError(
                        newPw.text, confirmPw.text, setDlg),
                    suffixIcon: IconButton(
                      icon: Icon(obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setDlg(
                          () => obscureConfirm = !obscureConfirm),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _green),
              onPressed: () async {
                // ── Validate inputs ──────────────────────────────────────
                final current = currentPw.text.trim();
                final newPass = newPw.text;
                final confirm = confirmPw.text;

                if (current.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Enter your current password')));
                  return;
                }
                if (newPass.length < 6) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('New password must be at least 6 characters')));
                  return;
                }
                if (newPass != confirm) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Passwords do not match')));
                  return;
                }
                if (newPass == current) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('New password must differ from current')));
                  return;
                }

                // ── Re-authenticate ───────────────────────────────────────
                try {
                  final credential = EmailAuthProvider.credential(
                    email: currentUser.email!,
                    password: current,
                  );
                  await currentUser.reauthenticateWithCredential(credential);

                  // ── Update password ─────────────────────────────────────
                  await currentUser.updatePassword(newPass);

                  if (mounted) {
                    Navigator.pop(context); // close dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Password updated successfully'),
                        backgroundColor: Colors.green,
                      ));
                  }
                } on FirebaseAuthException catch (e) {
                  String msg;
                  switch (e.code) {
                    case 'wrong-password':
                    case 'invalid-credential':
                      msg = 'Incorrect current password.';
                      break;
                    case 'weak-password':
                      msg = 'New password is too weak. Use at least 6 characters.';
                      break;
                    case 'requires-recent-login':
                      msg = 'Please log in again and try once more.';
                      break;
                    default:
                      msg = e.message ?? 'Failed to update password.';
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700));
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade700));
                  }
                }
              },
              child: const Text('Update', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  String? _pwMatchError(String newPw, String confirm, Function(void Function()) setDlg) {
    if (confirm.isNotEmpty && confirm != newPw) return 'Passwords do not match';
    return null;
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

// ═════════════════════════════════════════════════════════════════════════════
// Donate Dialog — shows bank / UPI details for manual transfer
// ═════════════════════════════════════════════════════════════════════════════
class _DonateDialog extends StatefulWidget {
  const _DonateDialog();
  @override
  State<_DonateDialog> createState() => _DonateDialogState();
}

class _DonateDialogState extends State<_DonateDialog> {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);

  // TODO: Replace these placeholder values with actual donation details
  //       stored in a config file or Firebase Remote Config (not hard-coded).
  static const _accountHolder = 'QR Code Donor';
  static const _bankName = 'Bank Name';
  static const _accountNumber = '0000-0000000000-0';
  static const _ifsc = 'BBBB0000000';
  static const _upiId = 'qurankalima@upi';


  void _copyToClipboard(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.volunteer_activism, color: Colors.red),
          SizedBox(width: 8),
          Text('Support Quran Kalima'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your generous support helps keep this app free and growing. '
              'You can donate via bank transfer or UPI below.',
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.grey.shade700,
                  height: 1.5),
            ),
            const SizedBox(height: 16),
            _infoRow('Account Holder', _accountHolder),
            _infoRow('Bank Name', _bankName),
            _infoRow('Account Number', _accountNumber),
            _infoRow('IFSC Code', _ifsc),
            _infoRow('UPI ID', _upiId),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A2E1F) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.qr_code, size: 48, color: Colors.grey),
                  const SizedBox(height: 4),
                  Text(
                    'QR code will be added here',
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Note: Please add a note with your email after donating '
              'so we can acknowledge your contribution. JazakAllah!',
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.grey.shade500,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () => _copyToClipboard(value, label),
            tooltip: 'Copy $label',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// App Tour — lightweight multi-step overlay with skip/next
// ═════════════════════════════════════════════════════════════════════════════
class _AppTourDialog extends StatefulWidget {
  const _AppTourDialog();
  @override
  State<_AppTourDialog> createState() => _AppTourDialogState();
}

class _AppTourDialogState extends State<_AppTourDialog> {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);

  int _step = 0;
  final List<Map<String, String>> _steps = [
    {
      'emoji': '🕌',
      'title': 'Welcome to the Tour!',
      'body': 'Let\'s take a quick look at the key features of Quran Kalima.',
    },
    {
      'emoji': '📖',
      'title': 'Surah Reader',
      'body':
          'Read the Quran with word-by-word translation, audio, and morphology breakdown on long press.',
    },
    {
      'emoji': '🃏',
      'title': 'Flashcards',
      'body':
          'Learn vocabulary using Spaced Repetition (SRS). Swipe right for Known, left for Unknown.',
    },
    {
      'emoji': '📊',
      'title': 'Progress',
      'body': 'Track your daily streak, words learned, and consistency with a heatmap.',
    },
    {
      'emoji': '⚙️',
      'title': 'Settings',
      'body':
          'Customize fonts, themes, daily goals, and sync your progress to the cloud.',
    },
  ];

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _skip() => _finish();

  void _finish() {
    // Persist that the in-app tour has been shown
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('app_tour_seen', true);
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final step = _steps[_step];

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _gold.withValues(alpha: 0.4), width: 2),
          boxShadow: [
            BoxShadow(
                color: _green.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 8))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(step['emoji']!, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(step['title']!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : _green)),
            const SizedBox(height: 8),
            Text(step['body']!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                    height: 1.5)),
            const SizedBox(height: 16),
            // Progress dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_steps.length, (i) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _step ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _step
                        ? _gold
                        : (isDark ? Colors.white24 : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (_step > 0)
                  TextButton(
                    onPressed: () => setState(() => _step--),
                    child: const Text('Back'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _skip,
                  child: Text(_step == _steps.length - 1
                      ? 'Finish'
                      : 'Skip'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _green),
                  onPressed: _next,
                  child: Text(
                    _step == _steps.length - 1 ? 'Start' : 'Next',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
