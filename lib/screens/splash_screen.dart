import 'package:flutter/material.dart';
import '../database/database_importer.dart';
import '../database/migration_manager.dart';

class SplashScreen extends StatefulWidget {
  final Widget child;
  const SplashScreen({super.key, required this.child});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _label = 'Starting...';
  double _progress = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await MigrationManager.migrateIfNeeded();

      final needs = await DatabaseImporter.needsImport();
      if (needs) {
        await for (final p in DatabaseImporter.runImport()) {
          if (mounted) {
            setState(() {
              _label = p.label;
              _progress = p.fraction;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _label = 'Setup error: $e';
          _progress = 0;
        });
        // Wait 3 seconds so user can see the error, then continue anyway
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;

    return Scaffold(
      backgroundColor: const Color(0xFF1B4332),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('﷽',
                  style: TextStyle(fontSize: 42, color: Color(0xFFD4AF37))),
              const SizedBox(height: 32),
              const Text('Quran Kalima',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const Text('کلمۂ قرآن',
                  style: TextStyle(fontSize: 16, color: Color(0xFFD4AF37))),
              const SizedBox(height: 48),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation(Color(0xFFD4AF37)),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              Text(_label,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}