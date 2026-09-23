import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _done = false;

  // ── Import percentage tracking ────────────────────────────────────────────
  Map<ImportStep, double> _weights = {};
  final Set<ImportStep> _finished = {};
  ImportStep? _current;
  bool _importing = false;
  double _shown = 0; // % currently displayed (0..100)
  double _floor = 0; // % already guaranteed (finished stages)
  double _ceil = 0; // % the running stage may creep up to
  Timer? _creep;

  static const Map<ImportStep, String> _stageNames = {
    ImportStep.preparing: 'Loading assets',
    ImportStep.surahs: 'Importing Surahs',
    ImportStep.words: 'Building vocabulary',
    ImportStep.morphology: 'Analysing word roots & grammar',
    ImportStep.translations: 'Importing translations',
  };
  bool _hasError = false;
  bool _showOnboarding = false;

  // ── Logo animation (runs independently of data loading) ──────────────────
  late final AnimationController _logoCtrl;
  late final Animation<double> _bgReveal;      // 0-200ms: background square
  late final Animation<double> _ringReveal;    // 200-600ms: outer ring/border
  late final Animation<double> _bookReveal;    // 600-1000ms: book shape reveals
  late final Animation<double> _textReveal;    // 1000-1400ms: Arabic text appears
  late final Animation<double> _glowPass;      // 1400-1600ms: light passes across
  late final Animation<double> _glowFinal;     // 1600-1800ms: final subtle glow

  @override
  void initState() {
    super.initState();

    // One-shot animation: 1.8 seconds total
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // Phase 1: Background appears (0-200ms = 11% of timeline)
    _bgReveal = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 11,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 89),
    ]).animate(_logoCtrl);

    // Phase 2: Outer ring/border draws in (200-600ms = 22% of timeline)
    _ringReveal = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 11),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 22,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 67),
    ]).animate(_logoCtrl);

    // Phase 3: Book shape reveals (600-1000ms = 22% of timeline)
    _bookReveal = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 33),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 22,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 45),
    ]).animate(_logoCtrl);

    // Phase 4: Arabic text appears (1000-1400ms = 22% of timeline)
    _textReveal = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 56),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 22,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 22),
    ]).animate(_logoCtrl);

    // Phase 5: Light passes across (1400-1600ms = 11% of timeline)
    _glowPass = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 78),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 11,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 11),
    ]).animate(_logoCtrl);

    // Phase 6: Final subtle glow (1600-1800ms = 11% of timeline)
    _glowFinal = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 89),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 11,
      ),
    ]).animate(_logoCtrl);

    // Play once (non-repeating)
    _logoCtrl.forward();

    _run();
  }

  @override
  void dispose() {
    _creep?.cancel();
    _logoCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _run() async {
    try {
      await MigrationManager.migrateIfNeeded();

      final needs = await DatabaseImporter.needsImport();
      if (needs) {
        bool importFailed = false;
        _weights = await DatabaseImporter.plannedWeights();
        if (mounted) setState(() => _importing = true);
        _creep = Timer.periodic(
            const Duration(milliseconds: 100), (_) => _tick());
        await for (final p in DatabaseImporter.runImport()) {
          if (!mounted) return;
          if (p.step == ImportStep.error) {
            _creep?.cancel();
            setState(() {
              _label = p.label;
              _hasError = true;
            });
            importFailed = true;
            break;
          }
          setState(() => _onImportEvent(p));
          if (p.step == ImportStep.done) break;
        }
        _creep?.cancel();
        if (!importFailed && mounted) {
          setState(() {
            _shown = 100;
            _label = 'Setup complete ✓';
          });
          await Future.delayed(const Duration(milliseconds: 350));
        }
        // If import failed, show error and wait for user to retry or dismiss
        // Do NOT silently continue with old data
        if (importFailed && mounted) {
          await Future.delayed(const Duration(seconds: 5));
          if (mounted) {
            _showErrorDialog(
              'Database Import Failed',
              'Unable to import essential app data. Please restart the app to retry.',
            );
            return;
          }
        }
      }
    } catch (e, stack) {
      if (mounted) {
        setState(() {
          _creep?.cancel();
          _label = 'Startup error: $e';
          _hasError = true;
        });
      }
      CrashlyticsService.recordError(e, stack, context: 'SplashScreen._run');
      if (mounted) {
        await Future.delayed(const Duration(seconds: 2));
        _showErrorDialog(
          'Startup Error',
          'An error occurred during app startup: $e\n\nPlease restart the app.',
        );
        return;
      }
    }

    // Only proceed if no errors occurred
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

  // ── Percentage helpers ────────────────────────────────────────────────────

  double _stageStart(ImportStep s) {
    double sum = 0;
    for (final e in _weights.entries) {
      if (e.key == s) break;
      sum += e.value;
    }
    return sum;
  }

  void _onImportEvent(ImportProgress p) {
    _label = p.label;
    final w = _weights[p.step];
    if (w == null ||
        p.step == ImportStep.done ||
        p.step == ImportStep.error) {
      return;
    }
    // e.g. the later "Restoring progress..." event reuses ImportStep.preparing
    if (_finished.contains(p.step)) return;

    final start = _stageStart(p.step);
    final end = start + w;
    _current = p.step;
    if (p.total > 0 && p.done >= p.total) {
      _finished.add(p.step);
      _floor = end;
      _ceil = end;
    } else {
      _floor = start;
      _ceil = (end - 1.0) < start ? start : end - 1.0;
    }
  }

  void _tick() {
    if (!mounted || _done) return;
    double next = _shown;
    if (next < _floor) {
      // a stage just finished — catch up quickly
      next += ((_floor - next) * 0.3).clamp(0.3, 100.0);
      if (next > _floor) next = _floor;
    } else if (next < _ceil) {
      // stage is running — creep forward, never claiming it is finished
      next += (_ceil - next) * 0.02;
    }
    next = next.clamp(0.0, 99.0);
    if (next != _shown) setState(() => _shown = next);
  }

  Widget _stageRow(ImportStep s) {
    final finished = _finished.contains(s);
    final active = _current == s && !finished;
    const gold = Color(0xFFD4AF37);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: finished
                ? const Icon(Icons.check_circle, size: 18, color: gold)
                : active
                    ? const CircularProgressIndicator(
                        strokeWidth: 2, color: gold)
                    : const Icon(Icons.radio_button_unchecked,
                        size: 18, color: Colors.white24),
          ),
          const SizedBox(width: 10),
          Text(
            _stageNames[s] ?? '',
            style: TextStyle(
                fontSize: 13,
                color: (finished || active) ? Colors.white : Colors.white38),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Exit app or retry
              SystemNavigator.pop();
            },
            child: const Text('Exit App'),
          ),
        ],
      ),
    );
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
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
              if (_importing) ...[
                Text('${_shown.floor()}%',
                    style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD4AF37))),
                Text('${(100 - _shown).ceil()}% remaining',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white54)),
                const SizedBox(height: 12),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _importing ? _shown / 100 : null,
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
              if (_importing) ...[
                const SizedBox(height: 20),
                ..._weights.keys.map(_stageRow),
                const SizedBox(height: 16),
                const Text(
                  'First-time setup — happens only once.\n'
                  'Please keep the app open.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedLogo() {
    return AnimatedBuilder(
      animation: _logoCtrl,
      builder: (context, _) {
        return CustomPaint(
          painter: LogoPainter(
            bgReveal: _bgReveal.value,
            ringReveal: _ringReveal.value,
            bookReveal: _bookReveal.value,
            textReveal: _textReveal.value,
            glowPass: _glowPass.value,
            glowFinal: _glowFinal.value,
            isDark: Theme.of(context).brightness == Brightness.dark,
          ),
          size: const Size(140, 140),
        );
      },
    );
  }
}

// ── Custom Logo Painter ─────────────────────────────────────────────────────
class LogoPainter extends CustomPainter {
  final double bgReveal;
  final double ringReveal;
  final double bookReveal;
  final double textReveal;
  final double glowPass;
  final double glowFinal;
  final bool isDark;

  LogoPainter({
    required this.bgReveal,
    required this.ringReveal,
    required this.bookReveal,
    required this.textReveal,
    required this.glowPass,
    required this.glowFinal,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const goldColor = Color(0xFFD4AF37);
    const darkGreen = Color(0xFF1B4332);
    final bgColor = isDark ? darkGreen : const Color(0xFFE8F5E9);

    // ── Phase 1: Background square appears ──
    if (bgReveal > 0) {
      final bgSize = 120.0 * bgReveal;
      final bgPaint = Paint()
        ..color = bgColor.withValues(alpha: 0.9 * bgReveal)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: bgSize,
            height: bgSize,
          ),
          const Radius.circular(8),
        ),
        bgPaint,
      );
    }

    // ── Phase 2: Outer ring/border draws in ──
    if (ringReveal > 0) {
      final ringPaint = Paint()
        ..color = goldColor.withValues(alpha: 0.8 * ringReveal)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: 120.0,
            height: 120.0,
          ),
          const Radius.circular(8),
        ),
        ringPaint,
      );
    }

    // ── Phase 3: Book shape reveals (Quran book silhouette) ──
    if (bookReveal > 0) {
      final bookPaint = Paint()
        ..color = goldColor.withValues(alpha: 0.9 * bookReveal)
        ..style = PaintingStyle.fill;

      // Draw simplified book shape (two pages meeting at spine)
      final path = Path();
      path.moveTo(center.dx - 20 * bookReveal, center.dy - 25 * bookReveal);
      path.lineTo(center.dx - 5 * bookReveal, center.dy - 25 * bookReveal);
      path.lineTo(center.dx - 2 * bookReveal, center.dy - 5 * bookReveal);
      path.lineTo(center.dx - 20 * bookReveal, center.dy + 5 * bookReveal);
      path.close();

      // Right page
      path.moveTo(center.dx + 5 * bookReveal, center.dy - 25 * bookReveal);
      path.lineTo(center.dx + 20 * bookReveal, center.dy - 25 * bookReveal);
      path.lineTo(center.dx + 20 * bookReveal, center.dy + 5 * bookReveal);
      path.lineTo(center.dx + 2 * bookReveal, center.dy - 5 * bookReveal);
      path.close();

      canvas.drawPath(path, bookPaint);

      // Spine line
      final spinePaint = Paint()
        ..color = goldColor.withValues(alpha: 0.6 * bookReveal)
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(center.dx - 2 * bookReveal, center.dy - 25 * bookReveal),
        Offset(center.dx + 2 * bookReveal, center.dy + 5 * bookReveal),
        spinePaint,
      );
    }

    // ── Phase 4: Arabic text appears (decorative symbol) ──
    if (textReveal > 0) {
      final textPaint = Paint()
        ..color = goldColor.withValues(alpha: 0.85 * textReveal)
        ..style = PaintingStyle.fill;

      // Draw decorative Islamic pattern (simplified)
      final decorSize = 8.0 * textReveal;
      canvas.drawCircle(
        Offset(center.dx, center.dy + 18),
        decorSize,
        textPaint,
      );

      // Flanking dots
      canvas.drawCircle(
        Offset(center.dx - 12, center.dy + 18),
        decorSize * 0.6,
        textPaint..color = textPaint.color.withValues(alpha: 0.6 * textReveal),
      );
      canvas.drawCircle(
        Offset(center.dx + 12, center.dy + 18),
        decorSize * 0.6,
        textPaint..color = textPaint.color.withValues(alpha: 0.6 * textReveal),
      );
    }

    // ── Phase 5: Light passes across (shimmer effect) ──
    if (glowPass > 0) {
      final glowPaint = Paint()
        ..color = goldColor.withValues(alpha: 0.4 * (1 - (glowPass - 0.5).abs() * 2))
        ..style = PaintingStyle.fill;

      // Sweeping light from left to right
      final lightX = center.dx - 70 + glowPass * 140;
      canvas.drawCircle(
        Offset(lightX, center.dy),
        15 * glowPass,
        glowPaint,
      );
    }

    // ── Phase 6: Final subtle glow ──
    if (glowFinal > 0) {
      final finalGlowPaint = Paint()
        ..color = goldColor.withValues(alpha: 0.25 * glowFinal)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: 125.0,
            height: 125.0,
          ),
          const Radius.circular(10),
        ),
        finalGlowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(LogoPainter oldDelegate) {
    return oldDelegate.bgReveal != bgReveal ||
        oldDelegate.ringReveal != ringReveal ||
        oldDelegate.bookReveal != bookReveal ||
        oldDelegate.textReveal != textReveal ||
        oldDelegate.glowPass != glowPass ||
        oldDelegate.glowFinal != glowFinal;
  }
}