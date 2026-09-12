import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/announcement.dart';

const _green = Color(0xFF1B4332);
const _gold = Color(0xFFD4AF37);

(IconData, Color) _styleFor(AnnouncementType type) {
  switch (type) {
    case AnnouncementType.feature:
      return (Icons.auto_awesome, Colors.purple);
    case AnnouncementType.update:
      return (Icons.system_update, Colors.blue);
    case AnnouncementType.payment:
      return (Icons.payment, Colors.orange);
    case AnnouncementType.maintenance:
      return (Icons.build, Colors.red);
    case AnnouncementType.developer:
      return (Icons.campaign, _green);
    case AnnouncementType.general:
      return (Icons.info_outline, _gold);
  }
}

/// Shows a single announcement dialog and waits for the user to close it.
///
/// Returns `true` if the user checked "don't show this again" (only offered
/// when [Announcement.dismissible] is true) — AnnouncementService uses this
/// to decide whether to persist the dismissal. Returns `false` otherwise,
/// meaning it's allowed to show again on a future app open (this is the
/// normal behaviour for non-dismissible reminders like payment/maintenance
/// notices, which should keep appearing until they expire).
Future<bool> showAnnouncementDialog(
    BuildContext context, Announcement a) async {
  final (icon, color) = _styleFor(a.type);
  bool dontShowAgain = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: a.dismissible,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
                child: Text(a.title,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.body, style: const TextStyle(fontSize: 14, height: 1.5)),
              if (a.dismissible) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: dontShowAgain,
                      activeColor: _green,
                      onChanged: (v) =>
                          setState(() => dontShowAgain = v ?? false),
                    ),
                    const Text("Don't show this again",
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (a.actionLabel != null && a.actionUrl != null)
            TextButton(
              onPressed: () async {
                final uri = Uri.tryParse(a.actionUrl!);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(a.actionLabel!,
                  style:
                      const TextStyle(color: _gold, fontWeight: FontWeight.bold)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ),
  );

  return a.dismissible && dontShowAgain;
}