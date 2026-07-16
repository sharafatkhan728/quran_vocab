// ignore_for_file: unused_local_variable, curly_braces_in_flow_control_structures, unnecessary_brace_in_string_interps

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../models/word.dart';
import '../providers/display_provider.dart';
import '../services/morphology_service.dart';
import '../services/word_progress_service.dart';
import 'package:quran/quran.dart' as quran;
import 'dart:async';

StreamSubscription<PlayerState>? _audioSub;

class MorphologySheet extends StatefulWidget {
  final QuranWord word;
  final int surahId;
  final int ayahId;
  final int wordPos;
  final List<QuranWord> ayahWords;
  final bool isKnown;
  final Function(bool) onKnownToggled;

  const MorphologySheet({
    super.key,
    required this.word,
    required this.surahId,
    required this.ayahId,
    required this.wordPos,
    required this.ayahWords,
    required this.isKnown,
    required this.onKnownToggled,
  });

  @override
  State<MorphologySheet> createState() => _MorphologySheetState();
}

class _MorphologySheetState extends State<MorphologySheet>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);
  static const _teal = Color(0xFF2D6A4F);

  late TabController _tabs;

  // Currently selected word in ayah (can change by tapping)
  late QuranWord _selectedWord;
  SarfChain? _sarfChain;

  // Root forms for Tab 2
  Map<String, List<String>>? _rootForms;
  String? _expandedLemma;
  Map<String, List<Map<String, dynamic>>> _lemmaAyahs = {};
  bool _loadingAyahs = false;

  // Grammar explanation language
  bool _showUrdu = false;

  // Audio
  final AudioPlayer _audio = AudioPlayer();
  String? _playingKey;



  @override
  void initState() {
    super.initState();

    _tabs = TabController(length: 2, vsync: this);
    _selectedWord = widget.word;
    _loadForWord(widget.word, widget.wordPos);

    _audioSub = _audio.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (mounted) {
          setState(() => _playingKey = null);
        }
      }
    });
  }

  @override
    void dispose() {
      _tabs.dispose();
      _audioSub?.cancel();
      _audio.dispose();
      super.dispose();
    }

  void _loadForWord(QuranWord word, int pos) {
    setState(() {
      _selectedWord = word;
      _sarfChain = MorphologyService.buildSarfChain(
          widget.surahId, widget.ayahId, pos, word.arabic);
      _rootForms = _sarfChain?.root.isNotEmpty == true
          ? MorphologyService.getRootForms(_sarfChain!.root)
          : null;
      _expandedLemma = null;
      _lemmaAyahs = {};
    });
  }


  Future<void> _loadLemmaAyahs(String lemma, List<String> wordKeys) async {
    if (_lemmaAyahs.containsKey(lemma)) return;
    setState(() => _loadingAyahs = true);
    final ayahs = <Map<String, dynamic>>[];
    final sample = wordKeys.take(10).toList();

    for (final key in sample) {
      final parts = key.split(':');
      if (parts.length < 3) continue;
      final surahId = int.tryParse(parts[0]) ?? 0;
      final ayahId = int.tryParse(parts[1]) ?? 0;
      final wordPos = int.tryParse(parts[2]) ?? 1;
      try {
        // Use local quran package instead of API
        final verseWords = quran.getVerse(surahId, ayahId).split(' ')
            .where((w) => w.trim().isNotEmpty).toList();
        final wordsList = verseWords.asMap().entries.map((e) => {
          'text_uthmani': e.value,
          'position': e.key + 1,
          'char_type_name': 'word',
        }).toList();
        ayahs.add({
          'surah': surahId,
          'ayah': ayahId,
          'targetPos': wordPos,
          'words': wordsList,
          'key': '$surahId:$ayahId',
        });
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _lemmaAyahs[lemma] = ayahs;
        _loadingAyahs = false;
      });
    }
  }


  Future<void> _playWordAudio(int surah, int ayah, int pos) async {
  final key = '$surah:$ayah:$pos';

  if (_playingKey == key) {
    await _audio.stop();
    if (mounted) {
      setState(() => _playingKey = null);
    }
    return;
  }

  final s = surah.toString().padLeft(3, '0');
  final a = ayah.toString().padLeft(3, '0');
  final w = pos.toString().padLeft(3, '0');

  try {
    await _audio.setUrl(
      'https://audio.qurancdn.com/wbw/${s}_${a}_${w}.mp3',
    );

    await _audio.play();

    if (mounted) {
      setState(() => _playingKey = key);
    }

    // No listener here anymore.
  } catch (_) {}
}


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final display = context.watch<DisplayProvider>();
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.75,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1B12) : const Color(0xFFFDF9F0),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: _gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // ── Handle ────────────────────────────────────────────────────
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header: word + tabs ───────────────────────────────────────
          _buildHeader(display, isDark),

          // ── Tabs ──────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabs,
              indicator: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: _green.withValues(alpha: 0.3), blurRadius: 6)
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? Colors.white54 : Colors.grey,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              dividerColor: Colors.transparent,
              tabs: const [Tab(text: 'Details'), Tab(text: 'Usages')],
            ),
          ),

          // ── Tab content ───────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildDetailsTab(display, isDark),
                _buildUsagesTab(display, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(DisplayProvider display, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _gold.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          // Arabic word (selected)
          Text(
            _selectedWord.arabic,
            textDirection: TextDirection.rtl,
            style: _arabicStyle(display, isDark, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedWord.urduMeaning,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? const Color(0xFF7EC8A0) : _teal,
                      fontWeight: FontWeight.w600),
                ),
                if (_sarfChain?.root.isNotEmpty == true)
                  Text(
                    'Root: ${_sarfChain!.root}',
                    style: const TextStyle(fontSize: 11, color: _gold),
                  ),
              ],
            ),
          ),
          // Language toggle
          GestureDetector(
            onTap: () => setState(() => _showUrdu = !_showUrdu),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _showUrdu ? _green : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _showUrdu
                        ? _green
                        : Colors.grey.withValues(alpha: 0.3)),
              ),
              child: Text(
                _showUrdu ? 'اردو' : 'EN',
                style: TextStyle(
                    fontSize: 11,
                    color: _showUrdu ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Details ─────────────────────────────────────────────────────────
  Widget _buildDetailsTab(DisplayProvider display, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ayah with clickable words
          _buildClickableAyah(display, isDark),
          const SizedBox(height: 16),

          // Linguistic explanation
          _buildLinguisticExplanation(isDark),
          const SizedBox(height: 16),

          // Sarf breakdown
          _buildSarfBreakdown(display, isDark),
        ],
      ),
    );
  }

  Widget _buildClickableAyah(DisplayProvider display, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Surah:Ayah badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tap any word to analyze it',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${widget.surahId}:${widget.ayahId}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Words as clickable chips
          Wrap(
            alignment: WrapAlignment.end,
            textDirection: TextDirection.rtl,
            spacing: 4,
            runSpacing: 4,
            children: widget.ayahWords.asMap().entries.map((e) {
              final idx = e.key;
              final w = e.value;
              final wParts = w.id.split(':');
              final wPos = wParts.length >= 3
                  ? int.tryParse(wParts[2]) ?? (idx + 1)
                  : (idx + 1);
              final isSelected = w.id == _selectedWord.id;

              return GestureDetector(
                onTap: () => _loadForWord(w, wPos),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _gold.withValues(alpha: 0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? _gold : Colors.transparent,
                      width: isSelected ? 1.5 : 0,
                    ),
                  ),
                  child: Text(
                    w.arabic,
                    textDirection: TextDirection.rtl,
                    style: _arabicStyle(display, isDark,
                        size: isSelected
                            ? display.arabicFontSize + 2
                            : display.arabicFontSize),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Selected word meaning
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _selectedWord.urduMeaning.isNotEmpty
                  ? _selectedWord.urduMeaning
                  : '—',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFF7EC8A0) : _teal,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinguisticExplanation(bool isDark) {
    if (_sarfChain == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📖', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                'Linguistic Explanation',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : _green),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Grammar summary in natural language (like the screenshot)
          Text(
            _buildNaturalExplanation(isDark),
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.grey.shade700,
                height: 1.6),
          ),
          const SizedBox(height: 10),
          // Grammar chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _buildGrammarChips(isDark),
          ),
        ],
      ),
    );
  }

  String _buildNaturalExplanation(bool isDark) {
    if (_sarfChain == null) return '';
    final s = _sarfChain!;
    final parts = <String>[];

    if (_showUrdu) {
      if (s.root.isNotEmpty) {
        parts.add('لفظ "${_selectedWord.arabic}" کا جذر "${s.root}" ہے۔');
      }
      if (s.pos == 'V') {
        final tense =
            {'PERF': 'ماضی', 'IMPF': 'مضارع', 'IMPV': 'امر'}[s.tense] ?? '';
        if (tense.isNotEmpty) parts.add('یہ فعل $tense ہے۔');
        if (s.person.isNotEmpty) {
          final p = {'1': 'متکلم', '2': 'مخاطب', '3': 'غائب'}[s.person] ?? '';
          final g = {'M': 'مذکر', 'F': 'مؤنث'}[s.gender] ?? '';
          final n = {'SG': 'واحد', 'DU': 'تثنیہ', 'PL': 'جمع'}[s.number] ?? '';
          if (p.isNotEmpty) parts.add('$p، $g، $n۔');
        }
      }
      if (s.pos == 'N') {
        final state = {'DEF': 'معرفہ', 'INDEF': 'نکرہ'}[s.state] ?? '';
        final gcase = {
              'NOM': 'مرفوع',
              'ACC': 'منصوب',
              'GEN': 'مجرور'
            }[s.grammaticalCase] ??
            '';
        if (state.isNotEmpty) parts.add('یہ اسم $state ہے۔');
        if (gcase.isNotEmpty) parts.add('اعراب: $gcase۔');
      }
    } else {
      if (s.root.isNotEmpty) {
        parts.add(
            'The word "${_selectedWord.arabic}" derives from the root ${s.root}.');
      }
      if (s.pos == 'V') {
        final tense = MorphologyService.expand(s.tense);
        if (s.tense.isNotEmpty)
          parts.add('This is a ${tense.toLowerCase()} verb.');
        if (s.person.isNotEmpty) {
          final desc = [
            if (s.person.isNotEmpty)
              '${MorphologyService.expand(s.person)} person',
            if (s.gender.isNotEmpty)
              MorphologyService.expand(s.gender).toLowerCase(),
            if (s.number.isNotEmpty)
              MorphologyService.expand(s.number).toLowerCase(),
          ].join(', ');
          if (desc.isNotEmpty) parts.add('Subject: $desc.');
        }
        if (s.voice == 'PASS')
          parts.add('Voice: passive — the subject receives the action.');
      }
      if (s.pos == 'N') {
        final state = {'DEF': 'definite', 'INDEF': 'indefinite'}[s.state] ?? '';
        final gcase = {
              'NOM': 'nominative (مرفوع)',
              'ACCu': 'accusative (منصوب)',
              'GEN': 'genitive (مجرور)'
            }[s.grammaticalCase] ??
            '';
        if (state.isNotEmpty) parts.add('This noun is $state.');
        if (gcase.isNotEmpty) parts.add('Grammatical case: $gcase.');
      }
    }

    return parts.isEmpty
        ? (_showUrdu
            ? 'اس لفظ کا صرفی تجزیہ دستیاب ہے۔'
            : 'Morphological data available for this word.')
        : parts.join(' ');
  }

  List<Widget> _buildGrammarChips(bool isDark) {
    if (_sarfChain == null) return [];
    final s = _sarfChain!;
    final chips = <Widget>[];

    void addChip(String label, Color color) {
      chips.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ));
    }

    if (s.pos.isNotEmpty) addChip(MorphologyService.expand(s.pos), _green);
    if (s.tense.isNotEmpty)
      addChip(MorphologyService.expand(s.tense), Colors.blue);
    if (s.person.isNotEmpty) addChip('${s.person}P', Colors.teal);
    if (s.gender.isNotEmpty)
      addChip(MorphologyService.expand(s.gender), Colors.pink);
    if (s.number.isNotEmpty)
      addChip(MorphologyService.expand(s.number), Colors.orange);
    if (s.grammaticalCase.isNotEmpty)
      addChip(MorphologyService.expand(s.grammaticalCase), Colors.purple);
    if (s.voice.isNotEmpty)
      addChip(MorphologyService.expand(s.voice), Colors.indigo);
    if (s.state.isNotEmpty)
      addChip(MorphologyService.expand(s.state), Colors.brown);

    return chips;
  }

  Widget _buildSarfBreakdown(DisplayProvider display, bool isDark) {
    if (_sarfChain == null || _sarfChain!.steps.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.grey.shade50,
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Center(
          child: Text(
            _showUrdu
                ? 'اس لفظ کی صرفی زنجیر دستیاب نہیں'
                : 'No Sarf derivation chain available for this word type',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ),
      );
    }

    final steps = _sarfChain!.steps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                    color: _gold, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(
              _showUrdu
                  ? 'صرفی زنجیر (Sarf)'
                  : 'Morphological Derivation (Sarf)',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : _green),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...steps.asMap().entries.map((e) {
          final i = e.key;
          final step = e.value;
          final isLast = i == steps.length - 1;
          return Column(
            children: [
              _sarfStepCard(step, display, isDark),
              if (!isLast) _sarfArrow(step.change, isDark),
            ],
          );
        }),
      ],
    );
  }

  Widget _sarfStepCard(SarfStep step, DisplayProvider display, bool isDark) {
    Color color;
    IconData icon;
    switch (step.type) {
      case SarfType.root:
        color = _gold;
        icon = Icons.foundation;
        break;
      case SarfType.lemma:
        color = _teal;
        icon = Icons.book_outlined;
        break;
      case SarfType.inflected:
        color = Colors.blue;
        icon = Icons.transform;
        break;
      case SarfType.quranicForm:
        color = _green;
        icon = Icons.auto_stories;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: isDark ? 0.18 : 0.07),
            color.withValues(alpha: isDark ? 0.06 : 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _showUrdu ? step.titleUrdu : step.title,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                      letterSpacing: 0.3),
                ),
                const SizedBox(height: 4),
                Text(
                  step.arabic,
                  textDirection: TextDirection.rtl,
                  style: _arabicStyle(display, isDark,
                      size: step.type == SarfType.root ? 26 : 30),
                ),
                const SizedBox(height: 6),
                Text(
                  _showUrdu ? step.explanationUrdu : step.explanation,
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                      height: 1.5),
                ),
                // Show prefix/suffix details for quranicForm
                if (step.prefixes.isNotEmpty || step.suffixes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        ...step.prefixes.map((p) => _segBadge(
                            '${MorphologyService.expand(p.pos)} prefix',
                            Colors.orange)),
                        ...step.suffixes.map((s) => _segBadge(
                            '${MorphologyService.expand(s.pos)} suffix',
                            Colors.purple)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sarfArrow(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              Container(
                  width: 2, height: 8, color: _gold.withValues(alpha: 0.4)),
              Icon(Icons.arrow_downward,
                  color: _gold.withValues(alpha: 0.8), size: 18),
            ],
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 10, color: _gold, fontWeight: FontWeight.w500)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _segBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.w500)),
    );
  }

  // ── Tab 2: Usages ──────────────────────────────────────────────────────────
  Widget _buildUsagesTab(DisplayProvider display, bool isDark) {
    if (_sarfChain == null || _sarfChain!.root.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _showUrdu
                ? 'اس لفظ کے لیے جذر دستیاب نہیں'
                : 'Root data not available for this word',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ),
      );
    }

    final root = _sarfChain!.root;
    final forms = _rootForms ?? {};
    final totalOccurrences =
        forms.values.fold(0, (sum, list) => sum + list.length);
    final totalForms = forms.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Root summary header (like screenshot)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:
                  isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _gold.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      _showUrdu ? 'جذر: ' : 'Root: ',
                      style: TextStyle(
                          fontSize: 14,
                          color:
                              isDark ? Colors.white70 : Colors.grey.shade600),
                    ),
                    Text(
                      root,
                      textDirection: TextDirection.rtl,
                      style: GoogleFonts.amiriQuran(fontSize: 24, color: _gold),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$totalForms forms',
                        style: const TextStyle(
                            fontSize: 11,
                            color: _green,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87),
                    children: [
                      TextSpan(text: _showUrdu ? 'جذر ' : 'The root '),
                      TextSpan(
                        text: root,
                        style: TextStyle(
                            fontFamily: 'AmiriQuran',
                            fontSize: 18,
                            color: _gold),
                      ),
                      TextSpan(
                        text: _showUrdu
                            ? ' قرآن میں $totalOccurrences مرتبہ، $totalForms مختلف صیغوں میں آتا ہے:'
                            : ' occurs $totalOccurrences times in the Quran, in $totalForms derived forms:',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Forms list
          ...forms.entries.map((entry) {
            final lemma = entry.key;
            final wordKeys = entry.value;
            final isExpanded = _expandedLemma == lemma;
            final ayahs = _lemmaAyahs[lemma];

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  // Form header row (like screenshot)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _expandedLemma = isExpanded ? null : lemma;
                      });
                      if (!isExpanded && ayahs == null) {
                        _loadLemmaAyahs(lemma, wordKeys);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          // English meaning placeholder
                          Expanded(
                            child: Text(
                              _getLemmaTranslation(lemma),
                              style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey.shade600),
                            ),
                          ),
                          // Count
                          Text(
                            '${wordKeys.length} times',
                            style: const TextStyle(fontSize: 12, color: _gold),
                          ),
                          const SizedBox(width: 10),
                          // Arabic lemma
                          Text(
                            lemma,
                            textDirection: TextDirection.rtl,
                            style: GoogleFonts.amiriQuran(
                                fontSize: 20,
                                color: isDark ? Colors.white : _green),
                          ),
                          const SizedBox(width: 8),
                          // Expand arrow
                          Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.grey,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Expanded: ayahs list
                  if (isExpanded) ...[
                    Divider(
                        height: 1, color: Colors.grey.withValues(alpha: 0.15)),
                    if (_loadingAyahs)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: _gold, strokeWidth: 2)),
                      )
                    else if (ayahs != null)
                      ...ayahs.map((ayahData) =>
                          _buildAyahEntry(ayahData, display, isDark))
                    else
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Tap to load ayahs...'),
                      ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAyahEntry(
      Map<String, dynamic> ayahData, DisplayProvider display, bool isDark) {
    final surahId = ayahData['surah'] as int;
    final ayahId = ayahData['ayah'] as int;
    final targetPos = ayahData['targetPos'] as int;
    final wordsJson = ayahData['words'] as List;
    final normalized =
        WordProgressService.normalizeArabic(_selectedWord.arabic);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Surah:Ayah badge + audio
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Audio for whole ayah word
              GestureDetector(
                onTap: () => _playWordAudio(surahId, ayahId, targetPos),
                child: Icon(
                  _playingKey == '$surahId:$ayahId:$targetPos'
                      ? Icons.stop_circle
                      : Icons.volume_up,
                  color: Colors.blue.withValues(alpha: 0.7),
                  size: 18,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$surahId:$ayahId',
                    style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Ayah words with highlight
          Wrap(
            alignment: WrapAlignment.end,
            textDirection: TextDirection.rtl,
            spacing: 2,
            runSpacing: 2,
            children:
                wordsJson.where((w) => w['char_type_name'] != 'end').map((w) {
              final arabic = (w['text_uthmani'] ?? '') as String;
              final isMatch =
                  WordProgressService.normalizeArabic(arabic) == normalized;
              return isMatch
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _gold, width: 1),
                      ),
                      child: Text(arabic,
                          style: _arabicStyle(display, isDark,
                                  size: display.arabicFontSize - 4)
                              .copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : _green)),
                    )
                  : Text(arabic,
                      style: _arabicStyle(display, isDark,
                          size: display.arabicFontSize - 4));
            }).toList(),
          ),
          Divider(height: 16, color: Colors.grey.withValues(alpha: 0.1)),
        ],
      ),
    );
  }

  String _getLemmaTranslation(String lemma) {
    return lemma;
  }

  TextStyle _arabicStyle(DisplayProvider d, bool isDark, {double? size}) {
    final sz = size ?? d.arabicFontSize;
    final color = isDark ? Colors.white : const Color(0xFF1A1A1A);
    switch (d.arabicFont) {
      case 'indopak':
        return TextStyle(
            fontFamily: 'IndoPak',
            fontSize: sz,
            color: color,
            height: d.lineHeight);
      case 'noorehuda':
        return TextStyle(
            fontFamily: 'NoorehudaFont',
            fontSize: sz,
            color: color,
            height: d.lineHeight);
      default:
        return GoogleFonts.amiriQuran(
            fontSize: sz, color: color, height: d.lineHeight);
    }
  }
}
