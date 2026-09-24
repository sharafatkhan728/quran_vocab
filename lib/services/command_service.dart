import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../database/database_importer.dart';
import '../database/database_manager.dart';
import '../services/sync_service.dart';
import '../services/srs_service.dart';

/// Listens to users/{uid}/commands for admin-issued instructions you create
/// by hand in the Firebase Console when helping a specific user. Only a
/// FIXED, whitelisted set of command types can ever run — there is no path
/// for arbitrary remote code execution. Clients cannot create commands
/// themselves (enforced by Firestore rules); they can only read and mark
/// them done/failed.
class CommandService {
  CommandService._();

  static StreamSubscription? _sub;

  static void start() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('commands')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(_onCommands, onError: (e) {
      debugPrint('CommandService listen error: $e');
    });
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
  }

  static Future<void> _onCommands(QuerySnapshot<Map<String, dynamic>> snap) async {
    for (final doc in snap.docs) {
      await _execute(doc);
    }
  }

  static Future<void> _execute(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final type = data['type'] as String? ?? '';
    final expiresAt = data['expiresAt'] as Timestamp?;

    if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
      await doc.reference.update({'status': 'expired'});
      return;
    }

    await doc.reference.update({'status': 'executing'});

    String result = '';
    bool success = true;
    try {
      switch (type) {
        case 'reimport_content':
          final db = await DatabaseManager.db;
          await db.delete('db_meta', where: 'key = ?', whereArgs: ['content_version']);
          // Actual re-import runs on next app start (SplashScreen calls
          // DatabaseImporter.needsImport()/runImport() already) — clearing
          // this key is what triggers it, matching existing app behavior
          // rather than duplicating import logic here.
          result = 'content_version cleared — will reimport on next launch';
          break;

        case 'force_syncdown':
          final restoreResult = await SyncService.syncDown();
          result = 'syncDown result: ${restoreResult.name}';
          break;

        case 'reset_srs_cache':
          SrsService.clearVocabCache();
          result = 'SRS vocab cache cleared';
          break;

        case 'clear_disk_cache':
          final dir = await getApplicationDocumentsDirectory();
          final cacheDir = Directory(
              '${dir.path}/surah_word_cache_v${DatabaseImporter.contentCacheVersion}');
          if (await cacheDir.exists()) {
            await cacheDir.delete(recursive: true);
          }
          result = 'Disk word cache cleared';
          break;

        default:
          success = false;
          result = 'Unknown command type: $type';
      }
    } catch (e) {
      success = false;
      result = 'Error: $e';
    }

    await doc.reference.update({
      'status': success ? 'done' : 'failed',
      'result': result,
      'executedAt': FieldValue.serverTimestamp(),
    });
  }
}