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
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoFinished = false;
  bool _showOnboarding = false;
  bool _appReady = false;

  static const String _introVideoAsset = 'assets/video/Logo_quran_kalima.mp4';

  @override
  void initState() {
    super.initState();
    _initVideo();
    _loadInBackground();
  }

  Future<void> _initVideo() async {
    _videoController = VideoPlayerController.asset(_introVideoAsset);
    try {
      await _videoController!.initialize();
      if (!mounted) return;
      setState(() => _videoInitialized = true);
      _videoController!.play();
      _videoController!.addListener(_onVideoTick);
    } catch (e, stack) {
      debugPrint('SplashScreen: video failed — $e');
      CrashlyticsService.recordError(e, stack, context: 'SplashScreen._initVideo');
      if (mounted) {
        setState(() {
          _videoFinished = true;
          _videoInitialized = false;
        });
      }
    }
  }

  void _onVideoTick() {
    if (_videoController?.value.isCompleted == true && !_videoFinished) {
      _finishVideo();
    }
  }

  Future<void> _finishVideo() async {
    if (_videoFinished) return;
    _videoController?.removeListener(_onVideoTick);
    if (mounted) {
      setState(() => _videoFinished = true);
    }
    // Start onboarding check after video finishes
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final needsOnboarding = await OnboardingScreen.shouldShow();
    if (mounted) {
      setState(() => _showOnboarding = needsOnboarding);
    }
  }

  void _loadInBackground() async {
    try {
      await MigrationManager.migrateIfNeeded();
      final needs = await DatabaseImporter.needsImport();
      if (!needs && mounted) {
        setState(() => _appReady = true);
        return;
      }
      await for (final p in DatabaseImporter.runImport()) {
        if (!mounted) return;
        if (p.step == ImportStep.error) {
          debugPrint('SplashScreen: import error ${p.label}');
          break;
        }
        if (p.step == ImportStep.done) break;
      }
    } catch (e) {
      debugPrint('SplashScreen: background load error — $e');
      CrashlyticsService.recordError(e, StackTrace.current, context: 'SplashScreen._loadInBackground');
    }
    if (mounted) {
      setState(() => _appReady = true);
      SyncService.onSyncDownComplete = () async {
        if (mounted) {
          final learning = context.read<LearningStateProvider>();
          learning.reload();
        }
      };
    }
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show video until it finishes, then show app
    if (_videoInitialized && !_videoFinished) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: VideoPlayer(_videoController!),
        ),
      );
    }
    // Video finished — show onboarding or app
    if (_showOnboarding) {
      return OnboardingScreen(child: widget.child);
    }
    return widget.child;
  }
}
