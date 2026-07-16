// ignore_for_file: unnecessary_string_interpolations, curly_braces_in_flow_control_structures

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:quran/quran.dart' as quran;
import '../models/word.dart';
import 'word_glossary_service.dart';
import 'package:flutter/foundation.dart';

/// Morphology service using mustafa0x/quran-morphology corpus
/// Source: corpus.quran.com (Kais Dukes, University of Leeds) — GNU GPL
/// 77,430 words, manually verified morphological tags
class MorphologyService {
  static final Map<String, List<WordSegment>> _wordSegments = {};
  static final Map<String, String> _terms = {};
  static bool _loaded = false;

  static Future<void> initialize() async {
      if (_loaded) return;
      try {
        await Future.wait([_loadCorpus(), _loadTerms()]);
      } catch (e) {
        debugPrint('>>> MorphologyService init error: $e');
      }
      _loaded = true;
    }


  /// Find root for a normalized Arabic word by scanning segments
  static String? getAllKeysForWord(String normalizedArabic, int surahId) {
    // Scan all cached segments for this surah
    for (final entry in _wordSegments.entries) {
      if (!entry.key.startsWith('$surahId:')) continue;
      for (final seg in entry.value) {
        if (seg.type == SegType.stem && seg.root.isNotEmpty) {
          // Check if this segment's lemma matches our word
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

          final loc =
              cols[0].replaceAll('(', '').replaceAll(')', '').trim();
          final arabic = cols[1].trim();
          final pos = cols[2].trim();
          final tag = cols[3].trim();

          final parts = loc.split(':');
          if (parts.length < 4) continue;

          final wordKey = '${parts[0]}:${parts[1]}:${parts[2]}';

          final seg = WordSegment.parse(
            arabic,
            tag,
            int.tryParse(parts[3]) ?? 1,
            pos,
          );

          _wordSegments.putIfAbsent(wordKey, () => []).add(seg);
        }
        
    

        debugPrint('>>> Corpus loaded: ${_wordSegments.length} words');
      } catch (e) {
        debugPrint('>>> CORPUS LOAD FAILED: $e');
        // Don't rethrow — app continues without morphology
      }
    }


  

  static Future<void> _loadTerms() async {
    try {
      final raw =
          await rootBundle.loadString('assets/data/morphology_terms.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _terms.addAll(decoded.map((k, v) => MapEntry(k, v.toString())));
    } catch (_) {}
  }

  /// Get all segments for a word (surah:ayah:position)
  static List<WordSegment>? getSegments(int surah, int ayah, int pos) =>
      _wordSegments['$surah:$ayah:$pos'];

  /// Get all words with same root (for Tab 2)
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

  /// Get all word keys that share the same root, grouped by lemma
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
      // POS
      'N': 'Noun', 'PN': 'Proper Noun', 'V': 'Verb', 'ADJ': 'Adjective',
      'PRON': 'Pronoun', 'DEM': 'Demonstrative', 'REL': 'Relative Pronoun',
      'T': 'Time', 'LOC': 'Location', 'P': 'Preposition',
      'CONJ': 'Conjunction', 'SUB': 'Subordinating', 'ACC': 'Particle',
      'CERT': 'Certainty', 'FUT': 'Future', 'VOC': 'Vocative',
      'NEG': 'Negative', 'PREV': 'Preventive', 'VN': 'Verbal Noun',
      'INTG': 'Interrogative', 'NV': 'Nominal Verb',
      // Tense
      'PERF': 'Perfect (ماضي)', 'IMPF': 'Imperfect (مضارع)',
      'IMPV': 'Imperative (أمر)', 'ACT PCPL': 'Active Participle',
      'PASS PCPL': 'Passive Participle',
      // Person
      '1': '1st person (متكلم)', '2': '2nd person (مخاطب)',
      '3': '3rd person (غائب)',
      // Gender
      'M': 'Masculine (مذكر)', 'F': 'Feminine (مؤنث)',
      // Number
      'SG': 'Singular (مفرد)', 'DU': 'Dual (مثنى)', 'PL': 'Plural (جمع)',
      // Case
      'NOM': 'Nominative (مرفوع)', 'ACCu': 'Accusative (منصوب)',
      'GEN': 'Genitive (مجرور)',
      // Voice
      'ACT': 'Active (معلوم)', 'PASS': 'Passive (مجهول)',
      // State
      'DEF': 'Definite (معرفة)', 'INDEF': 'Indefinite (نكرة)',
    };
    return m[code] ?? code;
  }

  /// Build Sarf derivation chain for a word
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

    // Step 1: Root
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

    // Step 2: Lemma (if different from arabicWord and root)
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

    // Step 3: Inflected form (if verb with tense/number changes)
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

    // Step 4: Final form with prefixes/suffixes
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

  // ── Explanation generators ─────────────────────────────────────────────────

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
    if (s.pos == 'V')
      return 'Past tense, 3rd person singular masculine — the dictionary/citation form of the verb.';
    if (s.pos == 'N')
      return 'Singular, indefinite form — the dictionary entry form.';
    return 'The base dictionary form of this word.';
  }

  static String _lemmaExplanationUrdu(WordSegment s) {
    if (s.pos == 'V')
      return 'ماضی، واحد، غائب، مذکر — فعل کی بنیادی اور لغوی شکل۔';
    if (s.pos == 'N') return 'واحد، نکرہ — اسم کی بنیادی لغوی شکل۔';
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
    if (s.person.isNotEmpty) parts.add('${expand(s.person)}');
    if (s.gender.isNotEmpty) parts.add(expand(s.gender));
    if (s.number.isNotEmpty) parts.add(expand(s.number));
    return parts.isEmpty ? 'Inflected Form' : parts.join(', ');
  }

  static String _inflectionTitleUrdu(WordSegment s) {
    final parts = <String>[];
    const urduTense = {'PERF': 'ماضی', 'IMPF': 'مضارع', 'IMPV': 'امر'};
    const urduNumber = {'SG': 'واحد', 'DU': 'تثنیہ', 'PL': 'جمع'};
    const urduGender = {'M': 'مذکر', 'F': 'مؤنث'};
    const urduPerson = {'1': 'متکلم', '2': 'مخاطب', '3': 'غائب'};
    if (s.tense.isNotEmpty) parts.add(urduTense[s.tense] ?? s.tense);
    if (s.person.isNotEmpty) parts.add(urduPerson[s.person] ?? s.person);
    if (s.gender.isNotEmpty) parts.add(urduGender[s.gender] ?? s.gender);
    if (s.number.isNotEmpty) parts.add(urduNumber[s.number] ?? s.number);
    return parts.join('، ');
  }

  static String _inflectionExplanation(WordSegment s, String word) {
    final changes = <String>[];
    if (s.tense == 'IMPF') {
      changes.add(
          'Added ي، ت، أ، or ن as a prefix to indicate present/future tense (مضارع pattern)');
    }
    if (s.tense == 'IMPV') {
      changes.add('Imperative form: direct command address (فعل أمر)');
    }
    if (s.number == 'DU') {
      changes.add('Added ان or ين suffix for dual — referring to exactly two');
    }
    if (s.number == 'PL') {
      changes.add(
          'Added ون/ين (masculine) or ات (feminine) suffix for plural — three or more');
    }
    if (s.voice == 'PASS') {
      changes.add(
          'Passive voice: subject receives the action, pattern changes to u-ِ vowels');
    }
    if (s.gender == 'F' && s.pos == 'V') {
      changes.add('Added ت prefix or suffix to mark feminine subject');
    }
    if (s.grammaticalCase == 'NOM') {
      changes
          .add('Nominative case (مرفوع): subject of sentence, marked with ضمة');
    }
    if (s.grammaticalCase == 'GEN') {
      changes
          .add('Genitive case (مجرور): follows preposition, marked with كسرة');
    }
    return changes.isEmpty
        ? 'Morphological changes applied to match grammatical context.'
        : changes.join('. ');
  }

  static String _inflectionExplanationUrdu(WordSegment s, String word) {
    final changes = <String>[];
    if (s.tense == 'IMPF')
      changes.add('مضارع بنانے کے لیے شروع میں ی/ت/أ/ن لگایا گیا');
    if (s.tense == 'IMPV') changes.add('امر کی صیغہ: براہ راست حکم کے لیے');
    if (s.number == 'DU')
      changes.add('تثنیہ کے لیے آخر میں ان/ین کا اضافہ — دو کے لیے');
    if (s.number == 'PL')
      changes.add('جمع کے لیے ون/ین یا ات کا اضافہ — تین یا زیادہ کے لیے');
    if (s.voice == 'PASS') changes.add('مجہول: فاعل معلوم نہیں، صیغہ بدل گیا');
    return changes.isEmpty
        ? 'صرفی تبدیلیاں نحوی سیاق کے مطابق۔'
        : changes.join('۔ ');
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
    final p =
        prefixes.map((s) => '${expand(s.pos)} prefix (${s.pos})').join(', ');
    final s =
        suffixes.map((s) => '${expand(s.pos)} suffix (${s.pos})').join(', ');
    final parts = <String>[];
    if (p.isNotEmpty) parts.add('Prefixed with: $p');
    if (s.isNotEmpty) parts.add('Suffixed with: $s');
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
    if (prefixes.isNotEmpty && suffixes.isNotEmpty)
      return '↓ Prefix + suffix attached';
    if (prefixes.isNotEmpty) return '↓ Prefix attached';
    if (suffixes.isNotEmpty) return '↓ Suffix attached';
    return '';
  }

  /// Build all words for a surah:ayah from morphology + quran package
  /// Returns list of QuranWord with segments attached
  // static List<QuranWord> buildAyahWords(
  //     int surah, int ayah, Set<String> knownWords,
  //     {Map<String, String>? urduLookup}) {
    
  //   // Get full ayah text from quran package
  //   String ayahText = '';
  //   try {
  //     ayahText = quran.getVerse(surah, ayah);
  //     // quran package prepends Bismillah to ayah 1 for all surahs except 1 and 9
  //     // Strip it so Bismillah only shows as visual header
  //     if (ayah == 1 && surah != 1 && surah != 9) {
  //       const bismillah = 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ';
  //       if (ayahText.startsWith(bismillah)) {
  //         ayahText = ayahText.substring(bismillah.length).trim();
  //       }
  //       // Also try normalized version in case harkat differs
  //       final normText = ayahText
  //           .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED]'), '');
  //       const normBism = 'بسم الله الرحمن الرحيم';
  //       if (normText.startsWith(normBism)) {
  //         // Count words in bismillah to skip them
  //         final bismWords = normBism.split(' ').length;
  //         final allWords = ayahText.split(' ');
  //         ayahText = allWords.skip(bismWords).join(' ').trim();
  //       }
  //     }
  //   } catch (_) {}

  //   // Get Urdu word meanings from quran package
  //   try {
  //     quran.getVerseTranslation(
  //       surah, ayah, translation: quran.Translation.urdu);
  //   } catch (_) {}

  //   // Split ayah into words (same way morphology does)
  //   final arabicWords = ayahText.split(' ')
  //       .where((w) => w.trim().isNotEmpty).toList();

  //   // If morphology has more words than text split, use morphology count
  //   // If text split has more, pad with empty segments
  //   _wordSegments.keys
  //       .where((k) => k.startsWith('$surah:$ayah:'))
  //       .map((k) => int.tryParse(k.split(':')[2]) ?? 0)
  //       .fold(0, (max, v) => v > max ? v : max);


  //   final result = <QuranWord>[];

  //   for (int pos = 1; pos <= arabicWords.length; pos++) {
  //     final arabic = arabicWords[pos - 1]; 
  //     final segs = getSegments(surah, ayah, pos) ?? [];
  //     final normalized = arabic
  //         .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '').trim();

  //     // Get urdu meaning from saved word data
  //     final urdu = urduLookup?[normalized] ?? '';
  //     final word = QuranWord(
  //       id: '$surah:$ayah:$pos',
  //       arabic: arabic,
  //       urduMeaning: urdu,
  //       segments: segs,
  //       isKnown: knownWords.contains(normalized),
  //     );
  //     result.add(word);
  //   }
  //   return result;
  // }

  static List<QuranWord> buildAyahWords(
      int surah, int ayah, Set<String> knownWords,
      {Map<String, String>? urduLookup,
       Map<String, String>? glossaryLookup}) {
    
    String ayahText = '';
    try {
      ayahText = quran.getVerse(surah, ayah);
      // Strip Bismillah from ayah 1 (except surah 1 and 9)
      if (ayah == 1 && surah != 1 && surah != 9) {
        final parts = ayahText.split(' ');
        if (parts.length > 4) ayahText = parts.skip(4).join(' ');
      }
    } catch (_) {}

    // Waqf signs and Quran symbols to skip
    final waqfPattern = RegExp(
        r'^[\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED'
        r'\u0610-\u061A\u064B-\u065F\u0670\u0671'
        r'\u06D4\u06D5\u06D6\u06D7\u06D8\u06D9\u06DA\u06DB\u06DC'
        r'\u06DD\u06DE\u06DF\u06E0\u06E1\u06E2\u06E3\u06E4'
        r'\u06E5\u06E6\u06E7\u06E8\u06E9\u06EA\u06EB\u06EC\u06ED'
        r'\uFD3E\uFD3F\u0600-\u0605]+$');

    final arabicWords = ayahText.split(' ')
        .where((w) {
          final trimmed = w.trim();
          if (trimmed.isEmpty) return false;
          // Skip pure waqf/symbol tokens
          final stripped = trimmed
              .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640'
                  r'\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED]'), '')
              .trim();
          return stripped.isNotEmpty;
        })
        .toList();


        // .where((w) => w.trim().isNotEmpty).toList();
    final result = <QuranWord>[];

    for (int pos = 1; pos <= arabicWords.length; pos++) {
      final arabic = arabicWords[pos - 1];
      final segs = getSegments(surah, ayah, pos) ?? [];
      final normalized = arabic
          .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '').trim();


      // Only use urduLookup fallback when language is Urdu
      final lang = WordGlossaryService.selectedLang;
      final glKey = '$ayah:$pos';

      String urdu = glossaryLookup?[glKey] ?? '';

      // Only fall back to stored Urdu meanings when Urdu is selected
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

  /// Build all ayahs for a surah
  static Map<int, List<QuranWord>> buildSurahWords(
      int surahId, Set<String> knownWords) {
    final result = <int, List<QuranWord>>{};
    int verseCount = 0;
    try {
      verseCount = quran.getVerseCount(surahId);
    } catch (_) { return result; }

    for (int ayah = 1; ayah <= verseCount; ayah++) {
      result[ayah] = buildAyahWords(surahId, ayah, knownWords);
    }
    return result;
  }
  
  //<<<<<<<<<<<<<< below all static
  static String getWordType(int surah, int ayah, int pos) {
    final segs = getSegments(surah, ayah, pos);

    if (segs == null || segs.isEmpty) {
      return '';
    }



    // Verb highest priority
    for (final seg in segs) {
      if (seg.type == SegType.stem) {
        if (seg.pos == 'V') return 'V';

        if ([
          'N',
          'PN',
          'PRON',
          'DEM',
          'REL',
          'T',
          'LOC'
        ].contains(seg.pos)) {
          return 'N';
        }

        return 'P';
      }
    }
    // Everything else = particle
    return 'P';                       
  }


  /// Extract segment texts from a full Arabic word using character proportions
  /// This is approximate — morphology doesn't store segment char boundaries
  static List<SegmentText> extractSegmentTexts(
      String fullWord, List<WordSegment> segments) {
    
    if (segments.isEmpty) return [SegmentText(text: fullWord, seg: null)];
    if (segments.length == 1) {
      return [SegmentText(text: fullWord, seg: segments.first)];
    }

    // Strategy: prefixes are usually 1-2 chars, suffixes are 1-3 chars
    // stem gets the rest
    final result = <SegmentText>[];
    final prefixes = segments.where((s) => s.type == SegType.prefix).toList();
    final stem = segments.where((s) => s.type == SegType.stem).firstOrNull;
    final suffixes = segments.where((s) => s.type == SegType.suffix).toList();

    // RTL: prefixes are at the START of the word (right side visually)
    // In string terms: بِسْمِ = بِ (prefix P) + سْمِ (stem N)
    // Prefix chars: typically 1 Arabic letter + possible harkat
    
    String remaining = fullWord;
    
    // Extract prefix chars (1 base char each + diacritics)
    for (final pre in prefixes) {
      // Take first "letter cluster" (1 base char + following diacritics)
      final match = RegExp(r'^\p{L}[\p{M}]*', unicode: true).firstMatch(remaining);
      if (match != null) {
        result.add(SegmentText(text: match.group(0)!, seg: pre));
        remaining = remaining.substring(match.end);
      }
    }

    // Extract suffix chars from end
    final suffixTexts = <SegmentText>[];
    for (final suf in suffixes.reversed) {
      final match = RegExp(r'\p{L}[\p{M}]*$', unicode: true).firstMatch(remaining);
      if (match != null) {
        suffixTexts.insert(0, SegmentText(text: match.group(0)!, seg: suf));
        remaining = remaining.substring(0, match.start);
      }
    }

    // Stem gets everything remaining
    if (stem != null && remaining.isNotEmpty) {
      result.add(SegmentText(text: remaining, seg: stem));
    }
    result.addAll(suffixTexts);

    return result.isEmpty
        ? [SegmentText(text: fullWord, seg: stem)]
        : result;
  }
}

class SegmentText {
  final String text;
  final WordSegment? seg;
  SegmentText({required this.text, required this.seg});
}
  


// ── Data models ────────────────────────────────────────────────────────────────

enum SegType { prefix, stem, suffix }

class WordSegment {
  final int segNum;
  final SegType type;
  final String pos;
  final String root;
  final String lemma;
  final String tense;
  final String person;
  final String gender;
  final String number;
  final String grammaticalCase;
  final String voice;
  final String state;
  final String verbForm;
  final String arabic;

  WordSegment({
    required this.segNum,
    required this.type,
    required this.pos,
    required this.root,
    required this.lemma,
    required this.tense,
    required this.person,
    required this.gender,
    required this.number,
    required this.grammaticalCase,
    required this.voice,
    required this.state,
    required this.verbForm,
    required this.arabic,
  });


  

  // factory WordSegment.parse(String tag, int segNum) {
  factory WordSegment.parse(
    String arabic,
    String tag,
    int segNum,
    String posCode,
  ) {
    SegType type = SegType.stem;
    String pos = posCode, root = '', lemma = '', tense = '', person = '';
    String gender = '', number = '', gcase = '', voice = '', state = '';
    String verbForm = '';

    for (final token in tag.split('|')) {
      final t = token.trim();
      if (t == 'PREF') {
        type = SegType.prefix;
        continue;
      }

      if (t == 'SUFF') {
        type = SegType.suffix;
        continue;
      }

      if (t.startsWith('POS:')) {
        pos = t.substring(4);
        continue;
      }
      if (t.startsWith('ROOT:')) {
        root = t.substring(5);
        continue;
      }
      if (t.startsWith('LEM:')) {
        lemma = t.substring(4);
        continue;
      }

      switch (t) {
        case 'PERF':
          tense = 'PERF';
          break;
        case 'IMPF':
          tense = 'IMPF';
          break;
        case 'IMPV':
          tense = 'IMPV';
          break;
        case '1':
          person = '1';
          break;
        case '2':
          person = '2';
          break;
        case '3':
          person = '3';
          break;
        case 'M':
          gender = 'M';
          break;
        case 'F':
          gender = 'F';
          break;
        case 'SG':
          number = 'SG';
          break;
        case 'DU':
          number = 'DU';
          break;
        case 'PL':
          number = 'PL';
          break;
        case 'NOM':
          gcase = 'NOM';
          break;
        case 'ACC':
          gcase = 'ACC';
          break;
        case 'GEN':
          gcase = 'GEN';
          break;
        case 'ACT':
          voice = 'ACT';
          break;
        case 'PASS':
          voice = 'PASS';
          break;
        case 'DEF':
          state = 'DEF';
          break;
        case 'INDEF':
          state = 'INDEF';
          break;
      }

      // Verb form: II, III, IV... X
      if (RegExp(r'^[IVX]+$').hasMatch(t)) verbForm = t;
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
}



class SarfChain {
  final String root;
  final String lemma;
  final String pos;
  final String tense;
  final String person;
  final String gender;
  final String number;
  final String grammaticalCase;
  final String voice;
  final String state;
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
  final String arabic;
  final String arabicUrdu;
  final String title;
  final String titleUrdu;
  final String explanation;
  final String explanationUrdu;
  final String change;
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





