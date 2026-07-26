import 'package:flutter/material.dart';
import '../database/database_manager.dart';

class DbDebugScreen extends StatefulWidget {
  const DbDebugScreen({super.key});
  @override
  State<DbDebugScreen> createState() => _DbDebugScreenState();
}

class _DbDebugScreenState extends State<DbDebugScreen> {
  Map<String, int> _counts = {};
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await DatabaseManager.db;
      final tables = [
        'surahs',
        'ayahs',
        'ayah_words',
        'vocab_words',
        'word_translations',
        'ayah_translations',
        'morphology_segments',
        'roots',
        'parts_of_speech',
        'known_words',
        'srs_cards',
        'db_meta',
      ];
      final counts = <String, int>{};
      for (final t in tables) {
        try {
          final r = await db.rawQuery('SELECT COUNT(*) as c FROM $t');
          counts[t] = r.first['c'] as int? ?? 0;
        } catch (e) {
          counts[t] = -1;
        }
      }
      // Check db_meta
      final meta = await db.query('db_meta');
      for (final r in meta) {
        counts['meta:${r['key']}'] = 1;
      }
      if (mounted) {
        setState(() {
          _counts = counts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _resetAndReimport() async {
    setState(() => _loading = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DB Debug'),
        backgroundColor: const Color(0xFF1B4332),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetAndReimport,
            tooltip: 'Reset & Re-import',
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_counts.isEmpty)
                      const Text('No data found — database may be empty'),
                    ..._counts.entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key,
                                  style:
                                      const TextStyle(fontFamily: 'monospace')),
                              Text(
                                e.value == -1
                                    ? 'TABLE MISSING'
                                    : '${e.value} rows',
                                style: TextStyle(
                                  color: e.value == 0
                                      ? Colors.red
                                      : e.value == -1
                                          ? Colors.orange
                                          : Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
    );
  }
}
