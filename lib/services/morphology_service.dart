// ignore_for_file: unnecessary_string_interpolations, curly_braces_in_flow_control_structures
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:quran/quran.dart' as quran;
import '../models/word.dart';
import 'word_glossary_service.dart';

/// Morphology service — kept for MorphologySheet backward compatibility.
/// New screens use MorphologyRepository (SQLite) directly.
class MorphologyService {
  static final Map<String, List<WordSegment>> _wordSegments = {};
  static final Map<String, String> _terms = {};
  static bool _loaded = false;

  static Future<void> initialize() async {
    if (_loaded) return;
    await Future.wait([_loadCorpus(), _loadTerms()]);
    _loaded = true;
  }

  static bool get isLoaded => _loaded;

  static Future<void> _loadCorpus() async {
    try {
      final raw =
          await rootBundle.loadString('assets/data/quran_morphology.txt');
      for (final line in raw.split('\n')) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        final cols = t.split('\t');
        if (cols.length < 4) continue;
        final loc = cols[0].replaceAll('(', '').replaceAll(')', '').trim();
        final arabic = cols[1].trim();
        final pos = cols[2].trim();
        final tag = cols[3].trim();
        final parts = loc.split(':');
        if (parts.length < 4) continue;
        final wordKey = '${parts[0]}:${parts[1]}:${parts[2]}';
        final seg =
            _parseSegment(arabic, tag, int.tryParse(parts[3]) ?? 1, pos);
        _wordSegments.putIfAbsent(wordKey, () => []).add(seg);
      }
    } catch (_) {}
  }

  static WordSegment _parseSegment(
      String arabic, String tag, int segNum, String posCode) {
    SegType type = SegType.stem;
    String pos = posCode, root = '', lemma = '', tense = '', person = '';
    String gender = '', number = '', gcase = '', voice = '', state = '';
    String verbForm = '';
    for (final token in tag.split('|')) {
      final tok = token.trim();
      if (tok == 'PREF') {
        type = SegType.prefix;
      } else if (tok == 'SUFF') {
        type = SegType.suffix;
      } else if (tok.startsWith('POS:')) {
        pos = tok.substring(4);
      } else if (tok.startsWith('ROOT:')) {
        root = tok.substring(5);
      } else if (tok.startsWith('LEM:')) {
        lemma = tok.substring(4);
      } else if (tok == 'PERF') {
        tense = 'PERF';
      } else if (tok == 'IMPF') {
        tense = 'IMPF';
      } else if (tok == 'IMPV') {
        tense = 'IMPV';
      } else if (tok == '1') {
        person = '1';
      } else if (tok == '2') {
        person = '2';
      } else if (tok == '3') {
        person = '3';
      } else if (tok == 'M') {
        gender = 'M';
      } else if (tok == 'F') {
        gender = 'F';
      } else if (tok == 'SG') {
        number = 'SG';
      } else if (tok == 'DU') {
        number = 'DU';
      } else if (tok == 'PL') {
        number = 'PL';
      } else if (tok == 'NOM') {
        gcase = 'NOM';
      } else if (tok == 'ACC') {
        gcase = 'ACC';
      } else if (tok == 'GEN') {
        gcase = 'GEN';
      } else if (tok == 'ACT') {
        voice = 'ACT';
      } else if (tok == 'PASS') {
        voice = 'PASS';
      } else if (tok == 'DEF') {
        state = 'DEF';
      } else if (tok == 'INDEF') {
        state = 'INDEF';
      } else if (RegExp(r'^[IVX]+$').hasMatch(tok)) {
        verbForm = tok;
      }
    }
    return WordSegment(
      segNum: segNum,
      type: type,
      pos: pos,
      root: root,
      lemma: lemma,
      tense: tense,
      person: person,
      gender: gender,
      number: number,
      grammaticalCase: gcase,
      voice: voice,
      state: state,
      verbForm: verbForm,
      arabic: arabic,
    );
  }

  static Future<void> _loadTerms() async {
    try {
      final raw =
          await rootBundle.loadString('assets/data/morphology_terms.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _terms.addAll(decoded.map((k, v) => MapEntry(k, v.toString())));
    } catch (_) {}
  }

  static List<WordSegment>? getSegments(int surah, int ayah, int pos) =>
      _wordSegments['$surah:$ayah:$pos'];

  static Map<String, List<String>> getWordsByRoot(String root) {
    final result = <String, List<String>>{};
    for (final entry in _wordSegments.entries) {
      for (final seg in entry.value) {
        if (seg.root == root) {
          result.putIfAbsent(entry.key, () => []);
        }
      }
    }
    return result;
  }

  static Map<String, List<String>> getRootForms(String root) {
    final byLemma = <String, Set<String>>{};
    for (final entry in _wordSegments.entries) {
      for (final seg in entry.value) {
        if (seg.type == SegType.stem &&
            seg.root == root &&
            seg.lemma.isNotEmpty) {
          byLemma.putIfAbsent(seg.lemma, () => {}).add(entry.key);
        }
      }
    }
    return byLemma.map((k, v) => MapEntry(k, v.toList()));
  }

  static String expand(String code) => _terms[code] ?? _builtinExpand(code);

  static String _builtinExpand(String code) {
    const m = {
      'N': 'Noun',
      'PN': 'Proper Noun',
      'V': 'Verb',
      'ADJ': 'Adjective',
      'PRON': 'Pronoun',
      'DEM': 'Demonstrative',
      'REL': 'Relative Pronoun',
      'T': 'Time',
      'LOC': 'Location',
      'P': 'Preposition',
      'CONJ': 'Conjunction',
      'SUB': 'Subordinating',
      'ACC': 'Particle',
      'CERT': 'Certainty',
      'FUT': 'Future',
      'VOC': 'Vocative',
      'NEG': 'Negative',
      'PREV': 'Preventive',
      'VN': 'Verbal Noun',
      'INTG': 'Interrogative',
      'NV': 'Nominal Verb',
      'PERF': 'Perfect (ماضي)',
      'IMPF': 'Imperfect (مضارع)',
      'IMPV': 'Imperative (أمر)',
      'ACT PCPL': 'Active Participle',
      'PASS PCPL': 'Passive Participle',
      '1': '1st person (متكلم)',
      '2': '2nd person (مخاطب)',
      '3': '3rd person (غائب)',
      'M': 'Masculine (مذكر)',
      'F': 'Feminine (مؤنث)',
      'SG': 'Singular (مفرد)',
      'DU': 'Dual (مثنى)',
      'PL': 'Plural (جمع)',
      'NOM': 'Nominative (مرفوع)',
      'ACCu': 'Accusative (منصوب)',
      'GEN': 'Genitive (مجرور)',
      'ACT': 'Active (معلوم)',
      'PASS': 'Passive (مجهول)',
      'DEF': 'Definite (معرفة)',
      'INDEF': 'Indefinite (نكرة)',
    };
    return m[code] ?? code;
  }

  static String? getAllKeysForWord(String normalizedArabic, int surahId) {
    for (final entry in _wordSegments.entries) {
      if (!entry.key.startsWith('$surahId:')) continue;
      for (final seg in entry.value) {
        if (seg.type == SegType.stem && seg.root.isNotEmpty) {
          final normalizedLemma = seg.lemma
              .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
              .trim();
          if (normalizedLemma == normalizedArabic ||
              normalizedLemma.contains(normalizedArabic) ||
              normalizedArabic.contains(normalizedLemma)) {
            return seg.root;
          }
        }
      }
    }
    return null;
  }

  static String getWordType(int surah, int ayah, int pos) {
    final segs = getSegments(surah, ayah, pos);
    if (segs == null || segs.isEmpty) return '';
    for (final seg in segs) {
      if (seg.type == SegType.stem) {
        if (seg.pos == 'V') return 'V';
        if (['N', 'PN', 'PRON', 'DEM', 'REL', 'T', 'LOC'].contains(seg.pos)) {
          return 'N';
        }
        return 'P';
      }
    }
    return 'P';
  }

  static List<SegmentText> extractSegmentTexts(
      String fullWord, List<WordSegment> segments) {
    if (segments.isEmpty) {
      return [SegmentText(text: fullWord, seg: null)];
    }
    if (segments.length == 1) {
      return [SegmentText(text: fullWord, seg: segments.first)];
    }
    final result = <SegmentText>[];
    final prefixes = segments.where((s) => s.type == SegType.prefix).toList();
    final stem = segments.where((s) => s.type == SegType.stem).firstOrNull;
    final suffixes = segments.where((s) => s.type == SegType.suffix).toList();
    String remaining = fullWord;
    for (final pre in prefixes) {
      final match =
          RegExp(r'^\p{L}[\p{M}]*', unicode: true).firstMatch(remaining);
      if (match != null) {
        result.add(SegmentText(text: match.group(0)!, seg: pre));
        remaining = remaining.substring(match.end);
      }
    }
    final suffixTexts = <SegmentText>[];
    for (final suf in suffixes.reversed) {
      final match =
          RegExp(r'\p{L}[\p{M}]*$', unicode: true).firstMatch(remaining);
      if (match != null) {
        suffixTexts.insert(0, SegmentText(text: match.group(0)!, seg: suf));
        remaining = remaining.substring(0, match.start);
      }
    }
    if (stem != null && remaining.isNotEmpty) {
      result.add(SegmentText(text: remaining, seg: stem));
    }
    result.addAll(suffixTexts);
    return result.isEmpty ? [SegmentText(text: fullWord, seg: stem)] : result;
  }

  // ── Sarf chain from in-memory HashMap (original) ──────────────────────────

  static SarfChain? buildSarfChain(
      int surah, int ayah, int pos, String arabicWord) {
    final segs = getSegments(surah, ayah, pos);
    if (segs == null) return null;
    final stem = segs.firstWhere(
      (s) => s.type == SegType.stem,
      orElse: () => segs.first,
    );
    if (stem.root.isEmpty) return null;
    final steps = <SarfStep>[];
    steps.add(SarfStep(
      arabic: stem.root,
      arabicUrdu: stem.root,
      title: 'Root (جذر)',
      titleUrdu: 'اصل (جذر)',
      explanation: _rootExplanation(stem.root, stem.pos),
      explanationUrdu: _rootExplanationUrdu(stem.root, stem.pos),
      type: SarfType.root,
      change: '',
    ));
    if (stem.lemma.isNotEmpty && stem.lemma != arabicWord) {
      steps.add(SarfStep(
        arabic: stem.lemma,
        arabicUrdu: stem.lemma,
        title: _lemmaTitle(stem),
        titleUrdu: _lemmaTitleUrdu(stem),
        explanation: _lemmaExplanation(stem),
        explanationUrdu: _lemmaExplanationUrdu(stem),
        type: SarfType.lemma,
        change: _lemmaChange(stem),
      ));
    }
    if (_needsInflectionStep(stem) && stem.lemma != arabicWord) {
      steps.add(SarfStep(
        arabic: arabicWord,
        arabicUrdu: arabicWord,
        title: _inflectionTitle(stem),
        titleUrdu: _inflectionTitleUrdu(stem),
        explanation: _inflectionExplanation(stem, arabicWord),
        explanationUrdu: _inflectionExplanationUrdu(stem, arabicWord),
        type: SarfType.inflected,
        change: _inflectionChange(stem),
      ));
    }
    final prefixes = segs.where((s) => s.type == SegType.prefix).toList();
    final suffixes = segs.where((s) => s.type == SegType.suffix).toList();
    if (prefixes.isNotEmpty || suffixes.isNotEmpty) {
      steps.add(SarfStep(
        arabic: arabicWord,
        arabicUrdu: arabicWord,
        title: 'Quranic Form (صيغة قرآنية)',
        titleUrdu: 'قرآنی شکل',
        explanation: _affixExplanation(prefixes, suffixes),
        explanationUrdu: _affixExplanationUrdu(prefixes, suffixes),
        type: SarfType.quranicForm,
        change: _affixChange(prefixes, suffixes),
        prefixes: prefixes,
        suffixes: suffixes,
      ));
    }
    return SarfChain(
      root: stem.root,
      lemma: stem.lemma,
      pos: stem.pos,
      tense: stem.tense,
      person: stem.person,
      gender: stem.gender,
      number: stem.number,
      grammaticalCase: stem.grammaticalCase,
      voice: stem.voice,
      state: stem.state,
      steps: steps,
      segments: segs,
    );
  }

  // ── Explanation generators ────────────────────────────────────────────────

  static String _rootExplanation(String root, String pos) {
    final letters = root.replaceAll(' ', '-');
    switch (pos) {
      case 'V':
        return 'Trilateral root $letters. All verb conjugations derive from this pattern.';
      case 'N':
        return 'Root $letters. All derived nouns and adjectives share this core meaning.';
      default:
        return 'Root letters: $letters. The fundamental semantic unit.';
    }
  }

  static String _rootExplanationUrdu(String root, String pos) {
    switch (pos) {
      case 'V':
        return 'ثلاثی جذر $root۔ تمام فعلی صیغے اسی سے بنتے ہیں۔';
      case 'N':
        return 'جذر $root۔ تمام مشتق اسماء اسی معنی سے ہیں۔';
      default:
        return 'جذری حروف: $root';
    }
  }

  static String _lemmaTitle(WordSegment s) {
    if (s.pos == 'V') return 'Base Verb (فعل ماضي مفرد مذكر)';
    if (s.pos == 'N') return 'Base Noun (مفرد)';
    return 'Lemma (مصدر)';
  }

  static String _lemmaTitleUrdu(WordSegment s) {
    if (s.pos == 'V') return 'بنیادی فعل (ماضی - واحد مذکر)';
    if (s.pos == 'N') return 'بنیادی اسم (واحد)';
    return 'اصل شکل';
  }

  static String _lemmaExplanation(WordSegment s) {
    if (s.pos == 'V') {
      return 'Past tense, 3rd person singular masculine — the dictionary/citation form of the verb.';
    }
    if (s.pos == 'N') {
      return 'Singular, indefinite form — the dictionary entry form.';
    }
    return 'The base dictionary form of this word.';
  }

  static String _lemmaExplanationUrdu(WordSegment s) {
    if (s.pos == 'V') {
      return 'ماضی، واحد، غائب، مذکر — فعل کی بنیادی اور لغوی شکل۔';
    }
    if (s.pos == 'N') {
      return 'واحد، نکرہ — اسم کی بنیادی لغوی شکل۔';
    }
    return 'اس لفظ کی بنیادی لغوی شکل۔';
  }

  static String _lemmaChange(WordSegment s) {
    if (s.pos == 'V') return '↓ Base verb established';
    return '↓ Base form established';
  }

  static bool _needsInflectionStep(WordSegment s) =>
      s.tense.isNotEmpty ||
      s.number == 'DU' ||
      s.number == 'PL' ||
      s.voice == 'PASS';

  static String _inflectionTitle(WordSegment s) {
    final parts = <String>[];
    if (s.tense.isNotEmpty) parts.add(expand(s.tense));
    if (s.person.isNotEmpty) parts.add(expand(s.person));
    if (s.gender.isNotEmpty) parts.add(expand(s.gender));
    if (s.number.isNotEmpty) parts.add(expand(s.number));
    return parts.isEmpty ? 'Inflected Form' : parts.join(', ');
  }

  static String _inflectionTitleUrdu(WordSegment s) {
    const urduTense = {'PERF': 'ماضی', 'IMPF': 'مضارع', 'IMPV': 'امر'};
    const urduNumber = {'SG': 'واحد', 'DU': 'تثنیہ', 'PL': 'جمع'};
    const urduGender = {'M': 'مذکر', 'F': 'مؤنث'};
    const urduPerson = {'1': 'متکلم', '2': 'مخاطب', '3': 'غائب'};
    final parts = <String>[];
    if (s.tense.isNotEmpty) parts.add(urduTense[s.tense] ?? s.tense);
    if (s.person.isNotEmpty) parts.add(urduPerson[s.person] ?? s.person);
    if (s.gender.isNotEmpty) parts.add(urduGender[s.gender] ?? s.gender);
    if (s.number.isNotEmpty) parts.add(urduNumber[s.number] ?? s.number);
    return parts.join('، ');
  }

  static String _inflectionExplanation(WordSegment s, String word) {
    final changes = <String>[];
    if (s.tense == 'IMPF') {
      changes.add('Added ي، ت، أ، or ن as prefix for present/future tense.');
    }
    if (s.tense == 'IMPV') changes.add('Imperative form.');
    if (s.number == 'DU') changes.add('Dual suffix ان or ين added.');
    if (s.number == 'PL') changes.add('Plural suffix ون/ين or ات added.');
    if (s.voice == 'PASS') changes.add('Passive voice.');
    return changes.isEmpty
        ? 'Morphological changes applied.'
        : changes.join(' ');
  }

  static String _inflectionExplanationUrdu(WordSegment s, String word) {
    final changes = <String>[];
    if (s.tense == 'IMPF') changes.add('مضارع بنانے کے لیے سابقہ لگایا گیا');
    if (s.tense == 'IMPV') changes.add('امر کی صیغہ');
    if (s.number == 'DU') changes.add('تثنیہ کے لیے ان/ین کا اضافہ');
    if (s.number == 'PL') changes.add('جمع کے لیے ون/ین یا ات کا اضافہ');
    if (s.voice == 'PASS') changes.add('مجہول');
    return changes.isEmpty ? 'صرفی تبدیلیاں۔' : changes.join('۔ ');
  }

  static String _inflectionChange(WordSegment s) {
    if (s.tense == 'IMPF') return '↓ Present tense prefix added';
    if (s.tense == 'IMPV') return '↓ Imperative form';
    if (s.number == 'PL') return '↓ Plural suffix added';
    if (s.number == 'DU') return '↓ Dual suffix added';
    return '↓ Inflection applied';
  }

  static String _affixExplanation(
      List<WordSegment> prefixes, List<WordSegment> suffixes) {
    final p = prefixes.map((s) => '${expand(s.pos)} prefix').join(', ');
    final sf = suffixes.map((s) => '${expand(s.pos)} suffix').join(', ');
    final parts = <String>[];
    if (p.isNotEmpty) parts.add('Prefixed with: $p');
    if (sf.isNotEmpty) parts.add('Suffixed with: $sf');
    return parts.join('. ');
  }

  static String _affixExplanationUrdu(
      List<WordSegment> prefixes, List<WordSegment> suffixes) {
    final parts = <String>[];
    if (prefixes.isNotEmpty) {
      parts.add('سابقہ: ${prefixes.map((s) => expand(s.pos)).join("، ")}');
    }
    if (suffixes.isNotEmpty) {
      parts.add('لاحقہ: ${suffixes.map((s) => expand(s.pos)).join("، ")}');
    }
    return parts.join('۔ ');
  }

  static String _affixChange(
      List<WordSegment> prefixes, List<WordSegment> suffixes) {
    if (prefixes.isNotEmpty && suffixes.isNotEmpty) {
      return '↓ Prefix + suffix attached';
    }
    if (prefixes.isNotEmpty) return '↓ Prefix attached';
    if (suffixes.isNotEmpty) return '↓ Suffix attached';
    return '';
  }

  // ── Sarf chain from pre-loaded SQLite segments ────────────────────────────

  /// Build a SarfChain from pre-loaded [WordSegment] list fetched from SQLite.
  /// Called by MorphologySheet after fetching via MorphologyRepository.
  /// All private helpers are accessible here — same class.
  static SarfChain? buildSarfChainFromSegments(
      List<WordSegment> segs, String arabicWord) {
    if (segs.isEmpty) return null;
    final stem = segs.firstWhere(
      (s) => s.type == SegType.stem,
      orElse: () => segs.first,
    );
    if (stem.root.isEmpty) return null;
    final steps = <SarfStep>[];
    steps.add(SarfStep(
      arabic: stem.root,
      arabicUrdu: stem.root,
      title: 'Root (جذر)',
      titleUrdu: 'اصل (جذر)',
      explanation: _rootExplanation(stem.root, stem.pos),
      explanationUrdu: _rootExplanationUrdu(stem.root, stem.pos),
      type: SarfType.root,
      change: '',
    ));
    if (stem.lemma.isNotEmpty && stem.lemma != arabicWord) {
      steps.add(SarfStep(
        arabic: stem.lemma,
        arabicUrdu: stem.lemma,
        title: _lemmaTitle(stem),
        titleUrdu: _lemmaTitleUrdu(stem),
        explanation: _lemmaExplanation(stem),
        explanationUrdu: _lemmaExplanationUrdu(stem),
        type: SarfType.lemma,
        change: _lemmaChange(stem),
      ));
    }
    if (_needsInflectionStep(stem) && stem.lemma != arabicWord) {
      steps.add(SarfStep(
        arabic: arabicWord,
        arabicUrdu: arabicWord,
        title: _inflectionTitle(stem),
        titleUrdu: _inflectionTitleUrdu(stem),
        explanation: _inflectionExplanation(stem, arabicWord),
        explanationUrdu: _inflectionExplanationUrdu(stem, arabicWord),
        type: SarfType.inflected,
        change: _inflectionChange(stem),
      ));
    }
    final prefixes = segs.where((s) => s.type == SegType.prefix).toList();
    final suffixes = segs.where((s) => s.type == SegType.suffix).toList();
    if (prefixes.isNotEmpty || suffixes.isNotEmpty) {
      steps.add(SarfStep(
        arabic: arabicWord,
        arabicUrdu: arabicWord,
        title: 'Quranic Form (صيغة قرآنية)',
        titleUrdu: 'قرآنی شکل',
        explanation: _affixExplanation(prefixes, suffixes),
        explanationUrdu: _affixExplanationUrdu(prefixes, suffixes),
        type: SarfType.quranicForm,
        change: _affixChange(prefixes, suffixes),
        prefixes: prefixes,
        suffixes: suffixes,
      ));
    }
    return SarfChain(
      root: stem.root,
      lemma: stem.lemma,
      pos: stem.pos,
      tense: stem.tense,
      person: stem.person,
      gender: stem.gender,
      number: stem.number,
      grammaticalCase: stem.grammaticalCase,
      voice: stem.voice,
      state: stem.state,
      steps: steps,
      segments: segs,
    );
  }

  // ── Legacy helper — kept for word_tile.dart (extractSegmentTexts) ─────────

  static List<QuranWord> buildAyahWords(
      int surah, int ayah, Set<String> knownWords,
      {Map<String, String>? urduLookup, Map<String, String>? glossaryLookup}) {
    String ayahText = '';
    try {
      ayahText = quran.getVerse(surah, ayah);
      if (ayah == 1 && surah != 1 && surah != 9) {
        final parts = ayahText.split(' ');
        if (parts.length > 4) ayahText = parts.skip(4).join(' ');
      }
    } catch (_) {}
    final arabicWords = ayahText.split(' ').where((w) {
      final trimmed = w.trim();
      if (trimmed.isEmpty) return false;
      final stripped = trimmed
          .replaceAll(
              RegExp(
                  r'[\u064B-\u065F\u0670\u0640\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED]'),
              '')
          .trim();
      return stripped.isNotEmpty;
    }).toList();
    final result = <QuranWord>[];
    for (int pos = 1; pos <= arabicWords.length; pos++) {
      final arabic = arabicWords[pos - 1];
      final segs = getSegments(surah, ayah, pos) ?? [];
      final normalized =
          arabic.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '').trim();
      final lang = WordGlossaryService.selectedLang;
      final glKey = '$ayah:$pos';
      String urdu = glossaryLookup?[glKey] ?? '';
      if (urdu.isEmpty && lang == 'ur') {
        urdu = urduLookup?[normalized] ?? '';
      }
      result.add(QuranWord(
        id: '$surah:$ayah:$pos',
        arabic: arabic,
        urduMeaning: urdu,
        segments: segs,
        isKnown: knownWords.contains(normalized),
      ));
    }
    return result;
  }
}

// ── SegmentText helper (used only by word_tile.dart via extractSegmentTexts) ──
class SegmentText {
  final String text;
  final WordSegment? seg;
  SegmentText({required this.text, required this.seg});
}

// ── SarfChain models (used only by MorphologySheet) ───────────────────────────
class SarfChain {
  final String root, lemma, pos, tense, person, gender, number;
  final String grammaticalCase, voice, state;
  final List<SarfStep> steps;
  final List<WordSegment> segments;
  SarfChain({
    required this.root,
    required this.lemma,
    required this.pos,
    required this.tense,
    required this.person,
    required this.gender,
    required this.number,
    required this.grammaticalCase,
    required this.voice,
    required this.state,
    required this.steps,
    required this.segments,
  });
}

class SarfStep {
  final String arabic, arabicUrdu, title, titleUrdu;
  final String explanation, explanationUrdu, change;
  final SarfType type;
  final List<WordSegment> prefixes;
  final List<WordSegment> suffixes;
  SarfStep({
    required this.arabic,
    required this.arabicUrdu,
    required this.title,
    required this.titleUrdu,
    required this.explanation,
    required this.explanationUrdu,
    required this.change,
    required this.type,
    this.prefixes = const [],
    this.suffixes = const [],
  });
}

enum SarfType { root, lemma, inflected, quranicForm }
