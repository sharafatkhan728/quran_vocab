// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);

  NotifSettings? _settings;
  bool _loading = true;
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await NotificationService.getSettings();
    final granted = await NotificationService.requestPermission();
    if (mounted) {
      setState(() {
        _settings = settings;
        _permissionGranted = granted;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    await NotificationService.saveSettings(_settings!);
    NotificationService.lastScheduleError = null;
    if (mounted) {
      final error = NotificationService.lastScheduleError;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Notification settings saved ✓'),
          backgroundColor: Color(0xFF1B4332),
          duration: Duration(seconds: 2),
        ));
      }
    }
  }

  Future<void> _pickTime() async {
    final s = _settings!;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.hour, minute: s.minute),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _green),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _settings = s.copyWith(hour: picked.hour, minute: picked.minute);
      });
    }
  }

  Future<void> _pickQuietStart() async {
    final s = _settings!;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.quietStart, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _green),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _settings = s.copyWith(quietStart: picked.hour);
      });
    }
  }

  Future<void> _pickQuietEnd() async {
    final s = _settings!;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.quietEnd, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _green),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _settings = s.copyWith(quietEnd: picked.hour);
      });
    }
  }

  String _fmt(int hour, int minute) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F0E8),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('Save',
                style: TextStyle(
                    color: _gold, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _green))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Permission warning
                if (!_permissionGranted)
                  _warningCard(isDark),
                const SizedBox(height: 8),

                // Master toggle
                _card(isDark,
                    title: 'Notifications',
                    icon: Icons.notifications,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Enable Notifications',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87)),
                      subtitle: Text(
                          _settings!.enabled
                              ? 'Notifications are active'
                              : 'All notifications disabled',
                          style: TextStyle(
                              color:
                                  isDark ? Colors.white54 : Colors.grey)),
                      value: _settings!.enabled,
                      onChanged: (v) =>
                          setState(() => _settings = _settings!.copyWith(enabled: v)),
                      activeThumbColor: _green,
                    )),
                const SizedBox(height: 16),

                // Notification types
                if (_settings!.enabled) ...[
                  _card(isDark,
                      title: 'Notification Types',
                      icon: Icons.tune,
                      child: Column(children: [
                        _notifTile(
                          isDark,
                          icon: Icons.style,
                          iconColor: Colors.blue,
                          title: 'Vocabulary Review',
                          subtitle: 'When SRS cards are due for review',
                          value: _settings!.review,
                          onChanged: (v) => setState(
                              () => _settings = _settings!.copyWith(review: v)),
                        ),
                        _divider(),
                        _notifTile(
                          isDark,
                          icon: Icons.menu_book,
                          iconColor: _green,
                          title: 'Daily Quran Reminder',
                          subtitle: 'If you have not read today',
                          value: _settings!.dailyQuran,
                          onChanged: (v) => setState(() =>
                              _settings = _settings!.copyWith(dailyQuran: v)),
                        ),
                        _divider(),
                        _notifTile(
                          isDark,
                          icon: Icons.school,
                          iconColor: Colors.purple,
                          title: 'New Vocabulary Goal',
                          subtitle: 'Daily learning target reminder',
                          value: _settings!.newVocab,
                          onChanged: (v) => setState(
                              () => _settings = _settings!.copyWith(newVocab: v)),
                        ),
                        _divider(),
                        _notifTile(
                          isDark,
                          icon: Icons.local_fire_department,
                          iconColor: Colors.orange,
                          title: 'Streak Reminder',
                          subtitle: 'When your streak is at risk',
                          value: _settings!.streak,
                          onChanged: (v) => setState(
                              () => _settings = _settings!.copyWith(streak: v)),
                        ),
                        _divider(),
                        _notifTile(
                          isDark,
                          icon: Icons.bar_chart,
                          iconColor: Colors.teal,
                          title: 'Weekly Progress',
                          subtitle: 'Sunday summary of your week',
                          value: _settings!.weekly,
                          onChanged: (v) => setState(
                              () => _settings = _settings!.copyWith(weekly: v)),
                        ),
                      ])),
                  const SizedBox(height: 16),

                  // Reminder time
                  _card(isDark,
                      title: 'Reminder Time',
                      icon: Icons.access_time,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Daily reminder at',
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87)),
                        subtitle: Text(
                            _fmt(_settings!.hour, _settings!.minute),
                            style: const TextStyle(
                                color: _gold,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                        trailing: TextButton(
                          onPressed: _pickTime,
                          child: const Text('Change',
                              style: TextStyle(color: _green)),
                        ),
                      )),
                  const SizedBox(height: 16),

                  // Quiet hours
                  _card(isDark,
                      title: 'Quiet Hours',
                      icon: Icons.bedtime,
                      child: Column(children: [
                        const Text(
                          'No notifications will be sent during quiet hours.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Start',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: _pickQuietStart,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _green.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: _green.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      _fmt(_settings!.quietStart, 0),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: _green),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(Icons.arrow_forward,
                                color: Colors.grey, size: 20),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('End',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: _pickQuietEnd,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _green.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: _green.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      _fmt(_settings!.quietEnd, 0),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: _green),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]),
                      ])),
                  const SizedBox(height: 16),

                  // Frequency
                  _card(
                    isDark,
                    title: 'Notification Frequency',
                    icon: Icons.speed,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _buildFrequencyOptions(isDark),
                    ),
                  ),


                  const SizedBox(height: 16),

                  // Test button
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await NotificationService.rescheduleAll();
                        if (mounted) {
                          final error = NotificationService.lastScheduleError;
                          if (error != null) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(error),
                              backgroundColor: Colors.orange,
                              duration: const Duration(seconds: 4),
                            ));
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Notifications rescheduled ✓'),
                              backgroundColor: _green,
                            ));
                          }
                        }
                      },
                      icon: const Icon(Icons.refresh, color: _green),
                      label: const Text('Reschedule Now',
                          style: TextStyle(color: _green)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _green),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ],
            ),
    );
  }


    List<Widget> _buildFrequencyOptions(bool isDark) {
    final options = {
      'minimal': 'Only critical reminders',
      'normal': 'Balanced — recommended',
      'frequent': 'All reminders, multiple times',
    };
    return options.entries.map((entry) {
      final f = entry.key;
      final desc = entry.value;
      final sel = _settings!.frequency == f;
      return GestureDetector(
        onTap: () => setState(
            () => _settings = _settings!.copyWith(frequency: f)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: sel ? _green : Colors.transparent,
                  border: Border.all(
                    color: sel ? _green : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: sel
                    ? const Icon(Icons.check,
                        size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f[0].toUpperCase() + f.substring(1),
                      style: TextStyle(
                          color:
                              isDark ? Colors.white : Colors.black87),
                    ),
                    Text(
                      desc,
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _warningCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Notification permission not granted. '
              'Please allow notifications in system settings.',
              style: TextStyle(fontSize: 13, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(bool isDark,
      {required String title,
      required IconData icon,
      required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Icon(icon, color: _gold, size: 16),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark ? Colors.white : _green)),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(16), child: Material(
            color: Colors.transparent,
            child: child,
          )),
        ],
      ),
    );
  }

  Widget _notifTile(bool isDark,
      {required IconData icon,
      required Color iconColor,
      required String title,
      required String subtitle,
      required bool value,
      required Function(bool) onChanged}) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: iconColor.withValues(alpha: 0.15),
        ),
        child: Icon(icon, color: iconColor, size: 16),
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white54 : Colors.grey)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: _green,
    );
  }

  Widget _divider() =>
      const Divider(height: 1, indent: 50, endIndent: 0);
}