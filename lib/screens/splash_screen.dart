import 'package:flutter/material.dart';
import '../database/database_importer.dart';
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

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  String _label = 'Starting...';
  double _progress = 0;
  bool _done = false;
  bool _hasError = false;
  bool _showOnboarding = false;

  // ── Logo animation ─────────────────────────────────────────────────────────
  late final AnimationController _logoCtrl;
  late final Animation<double> _entranceScale;
  late final Animation<double> _entranceFade;
  late final Animation<double> _idlePulse;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    );
    // First ~900ms: scale + fade the logo in with a soft overshoot.
    _entranceScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.6, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 82),
    ]).animate(_logoCtrl);
    _entranceFade = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 12,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 88),
    ]).animate(_logoCtrl);
    // A gentle continuous "breathing" glow/scale for the rest of the loading
    // wait, so the logo stays alive instead of freezing once it lands.
    _idlePulse = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 18),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.06)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 41,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.06, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 41,
      ),
    ]).animate(_logoCtrl);
    _logoCtrl.repeat();

    _run();
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _run() async {
    try {
      await MigrationManager.migrateIfNeeded();

      final needs = await DatabaseImporter.needsImport();
      if (needs) {
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
      if (!mounted) {
        CrashlyticsService.recordError(e, stack, context: 'SplashScreen._run');
      }
    }

    // These must run regardless of whether an import happened, so the
    // onboarding check and sync callback are never skipped on the fast
    // "no import needed" path.
    if (mounted) {
      SyncService.onSyncDownComplete = () async {
        final learning = context.read<LearningStateProvider>();
        learning.reload();
      };

      final needsOnboarding = await OnboardingScreen.shouldShow();
      if (mounted) {
        setState(() {
          _showOnboarding = needsOnboarding;
          _done = true;
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
              _buildAnimatedLogo(),
              const SizedBox(height: 24),
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

  Widget _buildAnimatedLogo() {
    return AnimatedBuilder(
      animation: _logoCtrl,
      builder: (_, child) {
        final scale = _entranceScale.value * _idlePulse.value;
        return Opacity(
          opacity: _entranceFade.value,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.6), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Center(
          child: Text('﷽',
              style: TextStyle(fontSize: 34, color: Color(0xFFD4AF37))),
        ),
      ),
    );
  }
}