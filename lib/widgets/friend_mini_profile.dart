import 'package:flutter/material.dart';
import '../models/leaderboard_models.dart';

/// Tap on any leaderboard row → shows a quick profile card.
Future<void> showFriendMiniProfile(
    BuildContext context, LeaderboardEntry entry) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          CircleAvatar(
            radius: 36,
            backgroundColor: const Color(0xFFD4AF37).withValues(alpha: 0.15),
            child: Text(entry.avatarEmoji, style: const TextStyle(fontSize: 34)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(entry.displayName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (entry.badgeEmoji.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(entry.badgeEmoji, style: const TextStyle(fontSize: 18)),
              ],
            ],
          ),
          if (entry.country.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [entry.city, entry.country].where((s) => s.isNotEmpty).join(', '),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('📚', '${entry.knownWords}', 'Words'),
              _stat('⭐', '${entry.points}', 'Points'),
              _stat('🔥', '${entry.streak}', 'Streak'),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}

Widget _stat(String emoji, String value, String label) {
  return Column(
    children: [
      Text(emoji, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 4),
      Text(value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    ],
  );
}