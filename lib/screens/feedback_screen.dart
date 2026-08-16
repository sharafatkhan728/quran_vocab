// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);
  static const _supportEmail = 'sharafatkhan728@gmail.com';

  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _category = 'feedback';
  final List<String> _attachments = [];
  bool _sending = false;
  String _appVersion = '';
  String _deviceInfo = '';

  final _categories = {
    'feedback':   ('💬', 'Feedback',    'Share your thoughts'),
    'bug':        ('🐛', 'Bug Report',  'Something is not working'),
    'feature':    ('✨', 'Feature Request', 'Suggest an improvement'),
    'compliment': ('❤️', 'Compliment',  'Share something you love'),
  };

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceInfo() async {
    final info = await PackageInfo.fromPlatform();
    _appVersion = 'v${info.version} (${info.buildNumber})';
    if (Platform.isAndroid) {
      final di = DeviceInfoPlugin();
      final android = await di.androidInfo;
      _deviceInfo = '${android.manufacturer} ${android.model} '
          '• Android ${android.version.release}';
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final result = await showModalBottomSheet<XFile?>(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt, color: _green),
            title: const Text('Take Screenshot'),
            onTap: () async {
              Navigator.pop(context,
                  await picker.pickImage(source: ImageSource.camera));
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: _green),
            title: const Text('Choose from Gallery'),
            onTap: () async {
              Navigator.pop(context,
                  await picker.pickImage(source: ImageSource.gallery));
            },
          ),
        ],
      ),
    );
    if (result != null && _attachments.length < 3) {
      setState(() => _attachments.add(result.path));
    }
  }

  Future<void> _send() async {
    if (_messageCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please write your message first'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _sending = true);

    final catLabel = _categories[_category]!.$2;
    final subject = _subjectCtrl.text.trim().isEmpty
        ? '[$catLabel] Quran Kalima App'
        : '[$catLabel] ${_subjectCtrl.text.trim()}';

    final body = '''
${_messageCtrl.text.trim()}

---
App: Quran Kalima $_appVersion
Device: $_deviceInfo
Category: $catLabel
''';

    try {
      final email = Email(
        recipients: [_supportEmail],
        subject: subject,
        body: body,
        attachmentPaths: _attachments,
        isHTML: false,
      );
      await FlutterEmailSender.send(email);
      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        // Fallback — copy to clipboard if mail app not installed
        await Clipboard.setData(ClipboardData(
            text: 'To: $_supportEmail\nSubject: $subject\n\n$body'));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Mail app not found. Email copied to clipboard — paste it manually.'),
          duration: Duration(seconds: 5),
          backgroundColor: Colors.orange,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('✅', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('Thank you!',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _green)),
            const SizedBox(height: 8),
            const Text(
              'Your message has been sent. We will review it and respond to you.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _gold.withValues(alpha: 0.3)),
              ),
              child: Text(
                _supportEmail,
                style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close feedback screen
            },
            child: const Text('Done',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F0E8),
      appBar: AppBar(
        title: const Column(
          children: [
            Text('Feedback & Support'),
            Text('We read every message',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        centerTitle: true,
        backgroundColor: _green,
        foregroundColor: Colors.white,
        actions: [
          _sending
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)),
                )
              : TextButton(
                  onPressed: _send,
                  child: const Text('Send',
                      style: TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category selector
            _card(isDark,
                title: 'Category',
                icon: Icons.category,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories.entries.map((e) {
                    final sel = _category == e.key;
                    return GestureDetector(
                      onTap: () => setState(() => _category = e.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? _green : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: sel ? _green : Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(e.value.$1,
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text(e.value.$2,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: sel ? Colors.white : Colors.grey,
                                    fontWeight: sel
                                        ? FontWeight.bold
                                        : FontWeight.normal)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                )),
            const SizedBox(height: 16),

            // Subject
            _card(isDark,
                title: 'Subject (optional)',
                icon: Icons.title,
                child: TextField(
                  controller: _subjectCtrl,
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'e.g. Font not loading correctly',
                    hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey),
                    border: InputBorder.none,
                  ),
                )),
            const SizedBox(height: 16),

            // Message
            _card(isDark,
                title: 'Message',
                icon: Icons.message,
                child: TextField(
                  controller: _messageCtrl,
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87),
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText:
                        'Describe your ${_categories[_category]!.$3.toLowerCase()}...',
                    hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey),
                    border: InputBorder.none,
                  ),
                )),
            const SizedBox(height: 16),

            // Attachments
            _card(isDark,
                title: 'Screenshots (optional)',
                icon: Icons.attach_file,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Attachment previews
                    if (_attachments.isNotEmpty) ...[
                      SizedBox(
                        height: 90,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _attachments.length,
                          itemBuilder: (_, i) => Stack(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  image: DecorationImage(
                                    image: FileImage(File(_attachments[i])),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 10,
                                child: GestureDetector(
                                  onTap: () => setState(
                                      () => _attachments.removeAt(i)),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.close,
                                        size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    // Add button
                    if (_attachments.length < 3)
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _green.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_photo_alternate,
                                  color: _green, size: 18),
                              SizedBox(width: 8),
                              Text('Add Screenshot',
                                  style: TextStyle(
                                      color: _green,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text('Up to 3 screenshots',
                        style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.white38
                                : Colors.grey.shade500)),
                  ],
                )),
            const SizedBox(height: 16),

            // Info card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: _gold.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: _gold, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sent to $_supportEmail\n'
                      'App: Quran Kalima $_appVersion',
                      style: const TextStyle(
                          fontSize: 11, color: _gold, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _card(bool isDark,
      {required String title,
      required IconData icon,
      required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Icon(icon, color: _gold, size: 15),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark ? Colors.white : _green)),
            ]),
          ),
          Padding(
              padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }
}