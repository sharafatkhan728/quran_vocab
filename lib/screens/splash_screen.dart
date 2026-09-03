import 'package:flutter/material.dart';
import '../database/database_importer.dart';
import '../database/database_manager.dart';
import '../database/migration_manager.dart';
import 'package:provider/provider.dart';
import '../providers/learning_state_provider.dart';
import '../services/crashlytics_service.dart';
import '../services/sync_service.dart';
import 'onboarding_screen.dart';


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
  bool _hasError = false;
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await MigrationManager.migrateIfNeeded();

      final needs = await DatabaseImporter.needsImport();
      if (!needs) {
        if (mounted) setState(() => _done = true);
        return;
      }

      await for (final p in DatabaseImporter.runImport()) {
        if (!mounted) return;
        if (p.step == ImportStep.error) {
          setState(() {
            _label = p.label;
            _progress = 0;
            _hasError = true;
          });
          // Wait so user can read the error, then continue with old data
          await Future.delayed(const Duration(seconds: 4));
          break;
        }
        setState(() {
          _label = p.label;
          _progress = p.fraction;
        });
        if (p.step == ImportStep.done) break;
      }
    } catch (e, stack) {
      if (mounted) {
        setState(() {
          _label = 'Startup error: $e';
          _progress = 0;
          _hasError = true;
        });
        await Future.delayed(const Duration(seconds: 4));
      }
      // Report even if the widget was disposed (e.g. user navigated away)
      if (!mounted) CrashlyticsService.recordError(e, stack,
          context: 'SplashScreen._run');
    }

    if (mounted) {
      // Defer LearningStateProvider.init() to MainNavigation so the splash
      // screen doesn't block on a full vocab_words table scan on every launch.
      // The vocab screen already has its own _initLoad() guard that calls it
      // eagerly, and other screens safely treat !isLoaded as "unknown".
      SyncService.onSyncDownComplete = () async {
        final learning = context.read<LearningStateProvider>();
        learning.reload();
      };

      // Diagnostic: check word_translations after import
      try {
        final db = await DatabaseManager.db;
        final wordCountRow = await db.rawQuery(
            'SELECT COUNT(*) as cnt FROM word_translations');
        final wtCount = (wordCountRow.first['cnt'] as int?) ?? 0;
        final ayahWordCountRow = await db.rawQuery(
            'SELECT COUNT(*) as cnt FROM ayah_words');
        final awCount = (ayahWordCountRow.first['cnt'] as int?) ?? 0;
        debugPrint(
            'SPLASH_DIAG: word_translations=$wtCount ayah_words=$awCount');
        if (mounted) {
          setState(() {
            _label = 'Data: $wtCount words / $awCount ayah_words';
          });
        }
      } catch (_) {}

      final needsOnboarding = await OnboardingScreen.shouldShow();
      setState(() {
        _showOnboarding = needsOnboarding;
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      if (_showOnboarding) {
        return OnboardingScreen(child: widget.child);
      }
      return widget.child;
    }

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
                  valueColor: AlwaysStoppedAnimation(
                      _hasError ? Colors.red : const Color(0xFFD4AF37)),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _hasError ? Colors.red.shade300 : Colors.white70,
                    fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
