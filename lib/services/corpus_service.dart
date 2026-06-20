import 'dart:convert';
import 'package:http/http.dart' as http;

/// Full Quran Corpus Service
/// Uses api.qurancdn.com (corpus.quran.com maintained by Quran.com team)
class CorpusService {
  static const _base = 'https://api.qurancdn.com/api/qdc';
  static const _audioBase = 'https://audio.qurancdn.com/wbw';

  // Cache to avoid redundant API calls
  static final Map<String, CorpusWordData> _cache = {};

  /// Main entry point — fetches ALL data for a word
  static Future<CorpusWordData> fetchWordData({
    required int surahId,
    required int ayahId,
    required int wordPosition,
    required String arabicText,
    required String urduMeaning,
    required String transliteration,
  }) async {
    final cacheKey = '$surahId:$ayahId:$wordPosition';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    // Build audio URL (always available, no API call needed)
    final s = surahId.toString().padLeft(3, '0');
    final a = ayahId.toString().padLeft(3, '0');
    final w = wordPosition.toString().padLeft(3, '0');
    final audioUrl = '$_audioBase/${s}_${a}_$w.mp3';

    // Fetch morphology from corpus endpoint
    CorpusMorphology? morphology;
    try {
      morphology = await _fetchMorphology(surahId, ayahId, wordPosition);
    } catch (_) {}

    final data = CorpusWordData(
      surahId: surahId,
      ayahId: ayahId,
      wordPosition: wordPosition,
      arabic: arabicText,
      urdu: urduMeaning,
      transliteration: transliteration,
      audioUrl: audioUrl,
      morphology: morphology,
      wordKey: '$surahId:$ayahId:$wordPosition',
      corpusUrl:
          'https://corpus.quran.com/wordbyword.jsp?chapter=$surahId&verse=$ayahId',
    );

    _cache[cacheKey] = data;
    return data;
  }

  static Future<CorpusMorphology> _fetchMorphology(
      int surahId, int ayahId, int wordPosition) async {
    // Quran.com corpus morphology endpoint
    final url = Uri.parse(
        '$_base/corpus/morphology?verse_key=$surahId:$ayahId&word_position=$wordPosition');

    final response = await http.get(url).timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return CorpusMorphology.fromJson(data);
    }

    // Fallback: parse from word data in verse endpoint
    return await _fetchMorphologyFromVerse(surahId, ayahId, wordPosition);
  }

  static Future<CorpusMorphology> _fetchMorphologyFromVerse(
      int surahId, int ayahId, int wordPosition) async {
    final url = Uri.parse('$_base/verses/by_key/$surahId:$ayahId'
        '?words=true'
        '&word_fields=text_uthmani,translation,transliteration,'
        'location,verse_id,chapter_id'
        '&word_translation_language=ur');

    final response = await http.get(url).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception('API error');

    final data = json.decode(response.body);
    final words = data['verse']['words'] as List;

    final word = words.firstWhere(
      (w) => w['position'] == wordPosition,
      orElse: () => words.isNotEmpty ? words[0] : {},
    );

    // Parse char_type for basic part of speech
    final charType = word['char_type_name'] ?? '';
    final pos = _charTypeToPos(charType);

    return CorpusMorphology(
      root: '',
      lemma: word['text_uthmani'] ?? '',
      partOfSpeech: pos,
      grammaticalCase: '',
      number: '',
      gender: '',
      person: '',
      state: '',
      voice: '',
      verbForm: '',
      derivation: '',
      morphParts: [],
      rawFeatures: {},
    );
  }

  static String _charTypeToPos(String charType) {
    switch (charType) {
      case 'word':
        return 'Word';
      case 'end':
        return 'Verse marker';
      default:
        return charType;
    }
  }

  /// Fetch word frequency across whole Quran
  static Future<int> fetchWordFrequency(String arabicText) async {
    try {
      final normalized =
          arabicText.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
      final url = Uri.parse('$_base/search?q=${Uri.encodeComponent(normalized)}'
          '&size=1&page=1');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['search']?['total_count'] ?? 0;
      }
    } catch (_) {}
    return 0;
  }
}

// ── Data Models ────────────────────────────────────────────────────────────────

class CorpusWordData {
  final int surahId;
  final int ayahId;
  final int wordPosition;
  final String arabic;
  final String urdu;
  final String transliteration;
  final String audioUrl;
  final CorpusMorphology? morphology;
  final String wordKey;
  final String corpusUrl;

  CorpusWordData({
    required this.surahId,
    required this.ayahId,
    required this.wordPosition,
    required this.arabic,
    required this.urdu,
    required this.transliteration,
    required this.audioUrl,
    required this.morphology,
    required this.wordKey,
    required this.corpusUrl,
  });
}

class CorpusMorphology {
  final String root;
  final String lemma;
  final String partOfSpeech;
  final String grammaticalCase;
  final String number; // singular/dual/plural
  final String gender; // masculine/feminine
  final String person; // 1st/2nd/3rd
  final String state; // definite/indefinite
  final String voice; // active/passive (for verbs)
  final String verbForm; // perfect/imperfect/imperative
  final String derivation; // form I, form II, etc.
  final List<MorphPart> morphParts;
  final Map<String, dynamic> rawFeatures;

  CorpusMorphology({
    required this.root,
    required this.lemma,
    required this.partOfSpeech,
    required this.grammaticalCase,
    required this.number,
    required this.gender,
    required this.person,
    required this.state,
    required this.voice,
    required this.verbForm,
    required this.derivation,
    required this.morphParts,
    required this.rawFeatures,
  });

  factory CorpusMorphology.fromJson(Map<String, dynamic> json) {
    // Parse morphology_parts if available
    final partsJson = json['morphology_parts'] as List? ?? [];
    final parts = partsJson.map((p) => MorphPart.fromJson(p)).toList();

    // Try multiple field name patterns (API version differences)
    String get(List<String> keys) {
      for (final k in keys) {
        if (json[k] != null) return json[k].toString();
      }
      return '';
    }

    return CorpusMorphology(
      root: get(['root', 'root_arabic', 'word_root']),
      lemma: get(['lemma', 'lemma_arabic', 'word_lemma']),
      partOfSpeech: get(['part_of_speech', 'pos', 'part_of_speach']),
      grammaticalCase: get(['case', 'grammatical_case', 'irab']),
      number: get(['number', 'num']),
      gender: get(['gender', 'gen']),
      person: get(['person', 'per']),
      state: get(['state', 'definiteness']),
      voice: get(['voice']),
      verbForm: get(['form', 'verb_form', 'derived_form']),
      derivation: get(['derivation', 'type']),
      morphParts: parts,
      rawFeatures: json,
    );
  }

  bool get hasData =>
      root.isNotEmpty ||
      lemma.isNotEmpty ||
      partOfSpeech.isNotEmpty ||
      morphParts.isNotEmpty;
}

class MorphPart {
  final String arabic;
  final String type; // prefix/stem/suffix
  final String pos; // part of speech
  final String root;
  final String lemma;
  final Map<String, String> features;

  MorphPart({
    required this.arabic,
    required this.type,
    required this.pos,
    required this.root,
    required this.lemma,
    required this.features,
  });

  factory MorphPart.fromJson(Map<String, dynamic> json) {
    return MorphPart(
      arabic: json['text'] ?? json['arabic'] ?? '',
      type: json['type'] ?? json['part_type'] ?? '',
      pos: json['part_of_speech'] ?? json['pos'] ?? '',
      root: json['root'] ?? '',
      lemma: json['lemma'] ?? '',
      features: Map<String, String>.from((json['features'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          {}),
    );
  }
}
