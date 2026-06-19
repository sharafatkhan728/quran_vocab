import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import '../models/word.dart';
import '../services/word_progress_service.dart';
import '../screens/morphology_sheet.dart';
import '../providers/display_provider.dart';
import 'package:provider/provider.dart';

class WordDetailDialog extends StatefulWidget {
  final QuranWord word;
  final int surahId;
  final int ayahId;
  final bool isKnown;
  final Function(bool) onKnownToggled;
  final List<QuranWord> ayahWords; // full ayah for context

  const WordDetailDialog({
    super.key,
    required this.word,
    required this.surahId,
    required this.ayahId,
    required this.isKnown,
    required this.onKnownToggled,
    required this.ayahWords,
  });

  @override
  State<WordDetailDialog> createState() => _WordDetailDialogState();
}

class _WordDetailDialogState extends State<WordDetailDialog>
    with TickerProviderStateMixin {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);

  late AnimationController _entryCtrl;
  late AnimationController _shimmerCtrl;
  late Animation<double> _scaleFade;
  late Animation<double> _shimmer;

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isKnown = false;
  int _wordPos = 1;
  StreamSubscription? _audioSub;

  @override
  void initState() {
    super.initState();
    _isKnown = widget.isKnown;
    final parts = widget.word.id.split(':');
    if (parts.length >= 3) _wordPos = int.tryParse(parts[2]) ?? 1;

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _shimmerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();

    _scaleFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutBack);
    _shimmer = _shimmerCtrl;

    _entryCtrl.forward();

    _audioSub = _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _audioSub?.cancel();
    _player.dispose();
    _entryCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _playAudio() async {
    if (_isPlaying) {
      await _player.stop();
      return;
    }
    final s = widget.surahId.toString().padLeft(3, '0');
    final a = widget.ayahId.toString().padLeft(3, '0');
    final w = _wordPos.toString().padLeft(3, '0');
    try {
      await _player.setUrl('https://audio.qurancdn.com/wbw/${s}_${a}_${w}.mp3');
      await _player.play();
    } catch (_) {}
  }

  Future<void> _toggleKnown() async {
    HapticFeedback.mediumImpact();
    final nowKnown = await WordProgressService.toggleWord(widget.word.arabic);
    setState(() => _isKnown = nowKnown);
    widget.onKnownToggled(nowKnown);
  }

  void _copy() {
    Clipboard.setData(ClipboardData(
        text: '${widget.word.arabic}\n${widget.word.urduMeaning}'));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('✓ Copied'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating),
    );
  }

  void _share() {
    SharePlus.instance.share(
      ShareParams(
        text: '${widget.word.arabic}\n${widget.word.urduMeaning}\n'
            '— Quran ${widget.surahId}:${widget.ayahId}\n'
            'Quran Kalima App',
      ),
    );
  }

  void _close() {
    _entryCtrl.reverse().then((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  //'''''''''''''''''''''''''''''''''''''

  void _openMorphology() {
    final capturedContext = context;
    Navigator.pop(capturedContext);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      showModalBottomSheet(
        context: capturedContext,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => MorphologySheet(
          word: widget.word,
          surahId: widget.surahId,
          ayahId: widget.ayahId,
          wordPos: _wordPos,
          ayahWords: widget.ayahWords,
          isKnown: _isKnown,
          onKnownToggled: widget.onKnownToggled,
        ),
      );
    });
  }
//''''''''''''''''''''''''''''''''''''''

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final display = context.watch<DisplayProvider>();

    return FadeTransition(
      opacity: _scaleFade,
      child: ScaleTransition(
        scale: _scaleFade,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
              border:
                  Border.all(color: _gold.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 30,
                    spreadRadius: 4),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header: ID only ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: _gold.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${widget.surahId}:${widget.ayahId}:$_wordPos',
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : _green,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      GestureDetector(
                        onTap: _close,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey.withValues(alpha: 0.15)),
                          child: Icon(Icons.close,
                              size: 15,
                              color: isDark ? Colors.white54 : Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Arabic word ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    widget.word.arabic,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                    style: _arabicStyle(display, isDark, size: 52),
                  ),
                ),

                // ── Transliteration ───────────────────────────────────────
                if (widget.word.transliteration.isNotEmpty)
                  Text(
                    widget.word.transliteration,
                    style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white54 : Colors.grey.shade500),
                  ),

                const SizedBox(height: 10),

                // ── Translation ───────────────────────────────────────────
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D6A4F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF2D6A4F).withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    widget.word.urduMeaning,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: display.urduFontSize + 4,
                      color: isDark
                          ? const Color(0xFF7EC8A0)
                          : const Color(0xFF2D6A4F),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── 4 Action buttons ──────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _actionBtn(
                      icon: _isPlaying
                          ? Icons.stop_circle
                          : Icons.volume_up_rounded,
                      label: _isPlaying ? 'Stop' : 'Listen',
                      color: Colors.blue,
                      onTap: _playAudio,
                    ),
                    _actionBtn(
                      icon: _isKnown
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      label: _isKnown ? 'Known ✓' : 'Mark Known',
                      color: _isKnown ? Colors.green : Colors.grey,
                      onTap: _toggleKnown,
                    ),
                    _actionBtn(
                      icon: Icons.copy_rounded,
                      label: 'Copy',
                      color: Colors.orange,
                      onTap: _copy,
                    ),
                    _actionBtn(
                      icon: Icons.share_rounded,
                      label: 'Share',
                      color: Colors.purple,
                      onTap: _share,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Golden animated morphology button ─────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: AnimatedBuilder(
                    animation: _shimmer,
                    builder: (_, child) => Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: SweepGradient(
                          center: Alignment.center,
                          startAngle: 0,
                          endAngle: 3.14 * 2,
                          transform:
                              GradientRotation(_shimmer.value * 3.14 * 2),
                          colors: const [
                            Color(0xFFD4AF37),
                            Color(0xFFFFF0A0),
                            Color(0xFFD4AF37),
                            Color(0xFFB8860B),
                            Color(0xFFD4AF37),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _gold.withValues(alpha: 0.4),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(2),
                      child: child,
                    ),
                    child: GestureDetector(
                      onTap: _openMorphology,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color:
                              isDark ? const Color(0xFF1A2E1F) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('✦',
                                style: TextStyle(color: _gold, fontSize: 16)),
                            const SizedBox(width: 10),
                            Text(
                              'Grammar & Morphology Breakdown',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                foreground: Paint()
                                  ..shader = const LinearGradient(
                                    colors: [
                                      Color(0xFFD4AF37),
                                      Color(0xFFB8860B),
                                    ],
                                  ).createShader(
                                      const Rect.fromLTWH(0, 0, 300, 30)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text('✦',
                                style: TextStyle(color: _gold, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _arabicStyle(DisplayProvider d, bool isDark, {double? size}) {
    final sz = size ?? d.arabicFontSize;
    final color = isDark ? Colors.white : const Color(0xFF1A1A1A);
    switch (d.arabicFont) {
      case 'indopak':
        return TextStyle(
            fontFamily: 'IndoPak', fontSize: sz, color: color, height: 1.4);
      case 'noorehuda':
        return TextStyle(
            fontFamily: 'NoorehudaFont',
            fontSize: sz,
            color: color,
            height: 1.4);
      default:
        return GoogleFonts.amiriQuran(fontSize: sz, color: color, height: 1.4);
    }
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
