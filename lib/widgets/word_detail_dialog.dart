import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../database/database_manager.dart';
import '../models/word.dart';
import '../providers/display_provider.dart';
import '../providers/theme_provider.dart';
import '../repositories/vocabulary_repository.dart';
import '../services/word_progress_service.dart';
import '../screens/morphology_sheet.dart';
import '../providers/learning_state_provider.dart';

class WordDetailDialog extends StatefulWidget {
  final QuranWord word;
  final int surahId;
  final int ayahId;
  final bool isKnown;
  final List<QuranWord> ayahWords;
  final Function(bool) onKnownToggled;

  const WordDetailDialog({
    super.key,
    required this.word,
    required this.surahId,
    required this.ayahId,
    required this.isKnown,
    required this.ayahWords,
    required this.onKnownToggled,
  });

  @override
  State<WordDetailDialog> createState() => _WordDetailDialogState();
}

class _WordDetailDialogState extends State<WordDetailDialog> {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);
  static const _teal = Color(0xFF2D6A4F);

  late bool _isKnown;
  VocabWordRow? _vocab;
  int? _rootCount;
  bool _audioPlaying = false;
  final AudioPlayer _audio = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _isKnown = widget.isKnown;
    _loadExtra();
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  Future<void> _loadExtra() async {
    final normalized = WordProgressService.normalizeArabic(widget.word.arabic);
    final vocab = await VocabularyRepository.getByArabicClean(normalized);
    if (!mounted) return;
    setState(() => _vocab = vocab);

    // Count root occurrences in Quran
    if (vocab != null && vocab.root.isNotEmpty) {
      try {
        final db = await DatabaseManager.db;
        final rows = await db.rawQuery('''
          SELECT COUNT(*) as cnt FROM morphology_segments ms
          JOIN roots r ON r.id = ms.root_id
          WHERE r.arabic = ?
        ''', [vocab.root]);
        final cnt = (rows.first['cnt'] as int?) ?? 0;
        if (mounted) setState(() => _rootCount = cnt);
      } catch (_) {}
    }
  }

  Future<void> _playAudio() async {
    final vocab = _vocab;
    if (vocab == null || vocab.firstSurahId == 0) return;
    HapticFeedback.lightImpact();
    try {
      setState(() => _audioPlaying = true);
      final s = vocab.firstSurahId.toString().padLeft(3, '0');
      final a = vocab.firstAyahNumber.toString().padLeft(3, '0');
      final w = vocab.firstWordPosition.toString().padLeft(3, '0');
      final url = 'https://audio.qurancdn.com/wbw/${s}_${a}_$w.mp3';
      await _audio.setUrl(url);
      await _audio.play();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _audioPlaying = false);
    }
  }

  void _copyArabic() {
    Clipboard.setData(ClipboardData(text: widget.word.arabic));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Arabic text copied'),
      duration: Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    final normalized = WordProgressService.normalizeArabic(widget.word.arabic);
    final learning = context.read<LearningStateProvider>();
    final nowKnown = await learning.toggleByClean(normalized);
    if (mounted) {
      setState(() => _isKnown = nowKnown);
      widget.onKnownToggled(nowKnown);
    }
  }

  void _openMorphology() {
    Navigator.pop(context);
    final parts = widget.word.id.split(':');
    final wordPos = parts.length >= 3 ? int.tryParse(parts[2]) ?? 1 : 1;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MorphologySheet(
        word: widget.word,
        surahId: widget.surahId,
        ayahId: widget.ayahId,
        wordPos: wordPos,
        ayahWords: widget.ayahWords,
        isKnown: _isKnown,
        onKnownToggled: widget.onKnownToggled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final display = context.watch<DisplayProvider>();
    final theme = context.watch<ThemeProvider>();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D1B12) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _gold.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(isDark, theme),
            _buildBody(isDark, display, theme),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  // Layout (RTL): Arabic word | audio | known | copy | word× | root×
  Widget _buildHeader(bool isDark, ThemeProvider theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A2E1F), const Color(0xFF0D1B12)]
              : [const Color(0xFFF0F7F0), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          bottom: BorderSide(color: _gold.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          // Arabic word — right side (RTL first child)
          Expanded(
            child: Text(
              widget.word.arabic,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: _arabicStyle(theme, isDark, 38),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),

          // Action buttons (left side in RTL = rendered right-to-left after arabic)
          // Audio
          _headerBtn(
            onTap: _playAudio,
            icon: _audioPlaying ? Icons.volume_up : Icons.play_arrow,
            color: _gold,
            bg: _gold.withValues(alpha: _audioPlaying ? 0.25 : 0.1),
            border: _gold.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 5),

          // Known toggle
          GestureDetector(
            onTap: _toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isKnown ? Colors.green : Colors.grey.withValues(alpha: 0.2),
                border: Border.all(
                  color: _isKnown ? Colors.green : Colors.grey.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Icon(
                _isKnown ? Icons.check : Icons.add,
                color: _isKnown ? Colors.white : Colors.grey,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 5),

          // Copy
          _headerBtn(
            onTap: _copyArabic,
            icon: Icons.copy_rounded,
            color: isDark ? Colors.white54 : Colors.grey.shade600,
            bg: Colors.grey.withValues(alpha: 0.1),
            border: Colors.grey.withValues(alpha: 0.3),
            size: 15,
          ),
          const SizedBox(width: 5),

          // Word occurrence count
          if ((_vocab?.frequency ?? 0) > 0)
            _countChip(
              icon: Icons.repeat,
              label: '${_vocab!.frequency}×',
              tooltip: 'Word occurrences',
              isDark: isDark,
              color: _gold,
            ),
          const SizedBox(width: 5),

          // Root occurrence count
          if (_rootCount != null && _rootCount! > 0)
            _countChip(
              icon: Icons.account_tree_outlined,
              label: '$_rootCount×',
              tooltip: 'Root occurrences',
              isDark: isDark,
              color: isDark ? Colors.purple.shade300 : Colors.purple.shade600,
            ),

          // Close — leftmost in header (LTR: far right)
          const SizedBox(width: 5),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.close, color: Colors.red, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerBtn({
    required VoidCallback onTap,
    required IconData icon,
    required Color color,
    required Color bg,
    required Color border,
    double size = 17,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg,
          border: Border.all(color: border, width: 1.5),
        ),
        child: Icon(icon, color: color, size: size),
      ),
    );
  }

  Widget _countChip({
    required IconData icon,
    required String label,
    required String tooltip,
    required bool isDark,
    required Color color,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody(bool isDark, DisplayProvider display, ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Meanings table ─────────────────────────────────────────────
          _buildMeaningsTable(isDark, display, theme),

          const SizedBox(height: 14),

          // ── Root chip ──────────────────────────────────────────────────
          if (widget.word.root.isNotEmpty) _buildRootChip(isDark, theme),

          const SizedBox(height: 14),

          // ── Known / Unknown label ──────────────────────────────────────
          Center(
            child: Text(
              _isKnown ? '✓ یاد ہے' : 'نہیں جانتا',
              style: TextStyle(
                fontFamily: 'JameelNoori',
                fontSize: 14,
                color: _isKnown ? Colors.green.shade600 : Colors.grey.shade500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ── Learn More button ──────────────────────────────────────────
          GestureDetector(
            onTap: _openMorphology,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_green, _teal],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _gold.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: _green.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.school_outlined, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Learn More About This Word',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Meanings table: 3 rows ─────────────────────────────────────────────────
  // Row 1: Urdu | English | Hindi
  // Row 2: Transliteration (full width)
  // Row 3: Grammar / POS segments (full width)
  Widget _buildMeaningsTable(
      bool isDark, DisplayProvider display, ThemeProvider theme) {
    final borderColor =
        isDark ? Colors.white12 : Colors.grey.shade200;
    final headerBg =
        isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50;
    final cellBg = isDark ? const Color(0xFF0F1F14) : Colors.white;

    // Always the true Urdu meaning from vocab_words — not widget.word.urduMeaning,
    // which is whatever language is currently selected for word-by-word
    // display in the Surah reader (could be Hindi/English), and would
    // otherwise leak into this fixed "اردو" column.
    final urdu = _vocab?.meaningUr ?? '';
    final english = _vocab?.meaningEn ?? '';
    final hindi = _vocab?.meaningHi ?? '';
    final translit = widget.word.transliteration;
    final showTranslit = translit.isNotEmpty && translit != widget.word.arabicClean;
    final hasSegments = widget.word.segments.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Row 1: Meanings ────────────────────────────────────────────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Urdu
                Expanded(
                  child: _tableCell(
                    label: 'اردو',
                    labelRtl: true,
                    value: urdu.isNotEmpty ? urdu : '—',
                    valueRtl: true,
                    valueFontFamily: 'JameelNoori',
                    fontSize: display.urduFontSize + 2,
                    valueColor: isDark ? const Color(0xFF7EC8A0) : _teal,
                    bg: cellBg,
                    headerBg: headerBg,
                    borderColor: borderColor,
                    showRightBorder: true,
                    isDark: isDark,
                  ),
                ),
                // English
                Expanded(
                  child: _tableCell(
                    label: 'EN',
                    value: english.isNotEmpty ? english : '—',
                    fontSize: 13,
                    valueColor:
                        isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                    bg: cellBg,
                    headerBg: headerBg,
                    borderColor: borderColor,
                    showRightBorder: true,
                    isDark: isDark,
                  ),
                ),
                // Hindi
                Expanded(
                  child: _tableCell(
                    label: 'हिंदी',
                    value: hindi.isNotEmpty ? hindi : '—',
                    fontSize: 13,
                    valueColor: isDark
                        ? Colors.orange.shade300
                        : Colors.orange.shade800,
                    bg: cellBg,
                    headerBg: headerBg,
                    borderColor: borderColor,
                    showRightBorder: false,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),

          // ── Row 2: Transliteration ─────────────────────────────────────
          if (showTranslit) ...[
            Container(height: 1, color: borderColor),
            Container(
              width: double.infinity,
              color: cellBg,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Transliteration',
                      style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? Colors.white38
                              : Colors.grey.shade500,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    translit,
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 0.4,
                      color:
                          isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Row 3: Grammar / POS segments ─────────────────────────────
          if (hasSegments) ...[
            Container(height: 1, color: borderColor),
            Container(
              width: double.infinity,
              color: cellBg,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Grammar',
                      style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? Colors.white38
                              : Colors.grey.shade500,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  _buildSegmentsRow(isDark, display),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tableCell({
    required String label,
    required String value,
    required double fontSize,
    required Color valueColor,
    required Color bg,
    required Color headerBg,
    required Color borderColor,
    required bool showRightBorder,
    required bool isDark,
    bool labelRtl = false,
    bool valueRtl = false,
    String? valueFontFamily,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: showRightBorder
            ? Border(right: BorderSide(color: borderColor))
            : null,
      ),
      child: Column(
        children: [
          // Header label
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: headerBg,
            child: Text(
              label,
              textAlign: labelRtl ? TextAlign.right : TextAlign.center,
              textDirection:
                  labelRtl ? TextDirection.rtl : TextDirection.ltr,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color:
                    isDark ? Colors.white54 : Colors.grey.shade600,
              ),
            ),
          ),
          // Value
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: bg,
            child: Text(
              value,
              textAlign: valueRtl ? TextAlign.right : TextAlign.center,
              textDirection:
                  valueRtl ? TextDirection.rtl : TextDirection.ltr,
              style: TextStyle(
                fontFamily: valueFontFamily,
                fontSize: fontSize,
                color: valueColor,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentsRow(bool isDark, DisplayProvider display) {
    final segments =
        widget.word.segments.where((s) => s.pos.isNotEmpty).toList();
    if (segments.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: segments.map((seg) {
        Color color;
        try {
          if (seg.colorHex.isNotEmpty && seg.colorHex != '#888888') {
            color = Color(int.parse(seg.colorHex.replaceFirst('#', '0xFF')));
          } else {
            color = _posToColor(seg.pos);
          }
        } catch (_) {
          color = _posToColor(seg.pos);
        }

        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 5),
              Text(
                _segTypeLabel(seg),
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRootChip(bool isDark, ThemeProvider theme) {
    final rootLabel = widget.word.root.characters.join('  ');
    return Center(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _gold.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Root: ',
              style: TextStyle(
                  fontSize: 12,
                  color:
                      isDark ? Colors.white54 : Colors.grey.shade600),
            ),
            Text(
              rootLabel,
              textDirection: TextDirection.rtl,
              style:
                  _arabicStyle(theme, isDark, 20).copyWith(color: _gold),
            ),
          ],
        ),
      ),
    );
  }

  String _segTypeLabel(WordSegment seg) {
    return seg.type == SegType.prefix
        ? 'Prefix'
        : seg.type == SegType.suffix
            ? 'Suffix'
            : seg.pos;
  }

  Color _posToColor(String pos) {
    switch (pos) {
      case 'V':
        return Colors.red.shade400;
      case 'N':
        return Colors.blue.shade400;
      case 'PN':
        return Colors.blue.shade600;
      case 'P':
        return Colors.green.shade500;
      case 'CONJ':
        return Colors.green.shade400;
      case 'PRON':
        return Colors.orange.shade400;
      case 'DEM':
        return Colors.orange.shade300;
      case 'REL':
        return Colors.purple.shade400;
      default:
        return Colors.grey.shade500;
    }
  }

  TextStyle _arabicStyle(ThemeProvider theme, bool isDark, double size) {
    final color = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final display = context.read<DisplayProvider>();
    switch (display.arabicFont) {
      case 'indopak':
        return TextStyle(
            fontFamily: 'IndoPak',
            fontSize: size,
            color: color,
            height: 1.6);
      case 'noorehuda':
        return TextStyle(
            fontFamily: 'NoorehudaFont',
            fontSize: size,
            color: color,
            height: 1.6);
      default:
        return GoogleFonts.amiri(fontSize: size, color: color, height: 1.6);
    }
  }
}
