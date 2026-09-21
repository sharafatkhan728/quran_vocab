import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F0E8),
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        centerTitle: true,
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Quran Kalima — Privacy Policy', isDark, big: true),
            _lastUpdated(),
            const SizedBox(height: 16),
            _paragraph(
              'Quran Kalima ("the App") is a Quran vocabulary learning app. '
              'This policy explains what information the App collects, how '
              'it is used, and the choices available to you.',
              isDark,
            ),
            _sectionTitle('Information We Collect', isDark),
            _bullet('Account information: if you sign in, we store your '
                'name, email address, and profile photo (if provided) via '
                'Firebase Authentication.', isDark),
            _bullet('Learning progress: which words you have marked known, '
                'your flashcard review history, reading position, '
                'bookmarks, and daily learning statistics. This data is '
                'stored on your device and, if signed in, synced to our '
                'cloud database (Firebase Firestore) so it is available '
                'across your devices.', isDark),
            _bullet('Crash and diagnostic data: if the App crashes or '
                'encounters an error, technical details (device type, app '
                'version, error stack trace) are sent to Firebase '
                'Crashlytics to help us fix bugs.', isDark),
            _bullet('Usage analytics: we collect anonymous, aggregated '
                'information about which screens and features are used '
                '(e.g. number of flashcard sessions started) via Firebase '
                'Analytics, to help us improve the App.', isDark),
            _sectionTitle('Information We Do NOT Collect', isDark),
            _bullet('We do not collect or sell your personal data to '
                'third parties for advertising.', isDark),
            _bullet('We do not access your contacts, photos, or files '
                'beyond what you explicitly choose to upload as a profile '
                'picture.', isDark),
            _sectionTitle('How Your Information Is Used', isDark),
            _paragraph(
              'Your learning data is used solely to provide the App\'s '
              'core features: tracking your vocabulary progress, showing '
              'your reading position, scheduling review reminders, and '
              'syncing your progress across devices you sign into.',
              isDark,
            ),
            _sectionTitle('Data Storage & Security', isDark),
            _paragraph(
              'Most of your data is stored locally on your device. If you '
              'sign in, a copy is also stored in Firebase Firestore, '
              'protected by Google\'s standard security infrastructure and '
              'access rules that restrict your data to your own account.',
              isDark,
            ),
            _sectionTitle('Notifications', isDark),
            _paragraph(
              'The App may send local reminder notifications (e.g. for '
              'due flashcard reviews or daily reading goals). These are '
              'generated on your device based on your own usage data and '
              'are not sent from a remote server. You can disable them '
              'anytime from your device\'s notification settings.',
              isDark,
            ),
            _sectionTitle('Third-Party Services', isDark),
            _paragraph(
              'The App uses the following third-party services, each '
              'governed by its own privacy policy:',
              isDark,
            ),
            _bullet('Firebase (Authentication, Firestore, Crashlytics, '
                'Analytics, App Check, Storage) — Google LLC', isDark),
            _bullet('Google Sign-In — Google LLC', isDark),
            _sectionTitle('Your Choices', isDark),
            _bullet('You can use most App features without signing in — '
                'in that case, your data stays only on your device.',
                isDark),
            _bullet('You can request deletion of your cloud-synced data '
                'by deleting your account from the Profile screen, or by '
                'contacting us at the email below.', isDark),
            _sectionTitle('Children\'s Privacy', isDark),
            _paragraph(
              'The App is suitable for general audiences including '
              'children, and does not knowingly collect personal '
              'information from children beyond what is described above '
              'for any user.',
              isDark,
            ),
            _sectionTitle('Changes to This Policy', isDark),
            _paragraph(
              'We may update this policy from time to time. Continued use '
              'of the App after changes constitutes acceptance of the '
              'updated policy.',
              isDark,
            ),
            _sectionTitle('Contact Us', isDark),
            _paragraph(
              'If you have questions about this privacy policy, contact '
              'us at: sharafatkhan728@gmail.com',
              isDark,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _lastUpdated() => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          'Last updated: ${DateTime.now().year}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      );

  Widget _sectionTitle(String text, bool isDark, {bool big = false}) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: big ? 20 : 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : _green,
          ),
        ),
      );

  Widget _paragraph(String text, bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: isDark ? Colors.white70 : Colors.grey.shade800,
          ),
        ),
      );

  Widget _bullet(String text, bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: _gold,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: isDark ? Colors.white70 : Colors.grey.shade800,
                ),
              ),
            ),
          ],
        ),
      );
}