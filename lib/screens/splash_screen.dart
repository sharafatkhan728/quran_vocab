import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  // ── Data loading state ────────────────────────────────────────────────────
  String _label = 'Starting...';
  double _progress = 0;
  bool _done = false;
  bool _hasError = false;
  bool _showOnboarding = false;

  // ── Intro video state ─────────────────────────────────────────────────────
  // _videoDone starts true (assume no video needed) and is only flipped to
  // false once we confirm the intro hasn't been seen yet. The final
  // transition to the app requires BOTH _done AND _videoDone — this is what
  // stops a fast database check from skipping the video entirely.
  bool _showIntroVideo = false;
  bool _videoDone = true;
  bool _videoInitialized = false;
  VideoPlayerController? _videoController;

  static const String _introVideoAsset = 'assets/video/Logo_quran_kalima.mp4';

  @override
  void initState() {
    super.initState();
    _checkIntroVideo();
    _run();
  }

  // ── Intro video ────────────────────────────────────────────────────────────

  Future<void> _checkIntroVideo() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenIntro = prefs.getBool('intro_video_seen') ?? false;
    if (hasSeenIntro || !mounted) return;

    setState(() {
      _showIntroVideo = true;
      _videoDone = false; // block the app transition until the video finishes
    });
    await _initVideo();
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.asset(_introVideoAsset);
    _videoController = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _videoInitialized = true);

      controller.addListener(_onVideoTick);
      await controller.play();

      // Safety net: if the completion listener never fires for some reason
      // (platform quirk, corrupt asset that still "initializes"), force the
      // splash to proceed once the known video duration has elapsed instead
      // of hanging forever.
      final duration = controller.value.duration;
      if (duration > Duration.zero) {
        Future.delayed(duration + const Duration(seconds: 1), () {
          if (mounted && !_videoDone) _finishIntroVideo();
        });
      }
    } catch (e, stack) {
      debugPrint('SplashScreen: intro video failed to load — $e');
      CrashlyticsService.recordError(e, stack,
          context: 'SplashScreen._initVideo');
      // Never let a broken video block the app from opening.
      await _finishIntroVideo();
    }
  }

  void _onVideoTick() {
    final value = _videoController?.value;
    if (value == null) return;
    if (value.isCompleted) {
      _finishIntroVideo();
    }
  }

  Future<void> _finishIntroVideo() async {
    if (_videoDone) return; // guard against double-invocation
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_video_seen', true);
    _videoController?.removeListener(_onVideoTick);
    if (mounted) {
      setState(() {
        _videoDone = true;
        _videoInitialized = false;
      });
    }
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

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
      if (!mounted) { CrashlyticsService.recordError(e, stack,
          context: 'SplashScreen._run'); }
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Only proceed to the app once BOTH the database is ready AND the intro
    // video (if any) has finished — this is the fix for the video being
    // skipped whenever data loading finished first.
    if (_done && _videoDone) {
      if (_showOnboarding) {
        return OnboardingScreen(child: widget.child);
      }
      return widget.child;
    }

    if (_showIntroVideo && !_videoDone) {
      return _buildVideoSplash();
    }

    return _buildProgressSplash();
  }

  Widget _buildVideoSplash() {
    final controller = _videoController;
    final ready = _videoInitialized && controller != null;
    final aspectRatio =
        ready && controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : 16 / 9;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ready
            ? AspectRatio(
                aspectRatio: aspectRatio,
                child: VideoPlayer(controller),
              )
            : const CircularProgressIndicator(color: Color(0xFFD4AF37)),
      ),
    );
  }

  Widget _buildProgressSplash() {
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