import '../repositories/content_repository.dart';

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
  final String colorHex;

  const WordSegment({
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
    this.colorHex = '#888888',
  });

  factory WordSegment.fromRow(MorphSegmentRow r) {
    SegType type;
    switch (r.segmentType) {
      case 'prefix':
        type = SegType.prefix;
        break;
      case 'suffix':
        type = SegType.suffix;
        break;
      default:
        type = SegType.stem;
    }
    return WordSegment(
      segNum: r.segmentNumber,
      type: type,
      pos: r.posCode,
      root: r.root,
      lemma: r.lemma,
      tense: r.tense,
      person: r.person,
      gender: r.gender,
      number: r.number,
      grammaticalCase: r.grammaticalCase,
      voice: r.voice,
      state: r.state,
      verbForm: r.verbForm,
      arabic: r.arabicText,
      colorHex: r.posColorHex,
    );
  }
}

class QuranWord {
  final String id;
  final String arabic;
  final String urduMeaning;
  final String transliteration;
  final bool isKnown;
  final bool isWaqf;
  final List<WordSegment> segments;

  const QuranWord({
    required this.id,
    required this.arabic,
    this.urduMeaning = '',
    this.transliteration = '',
    this.isKnown = false,
    this.isWaqf = false,
    this.segments = const [],
  });

  WordSegment? get stem =>
      segments.where((s) => s.type == SegType.stem).firstOrNull;
  String get root => stem?.root ?? '';
  String get lemma => stem?.lemma ?? '';
  String get pos => stem?.pos ?? '';
  String get colorHex => stem?.colorHex ?? '#888888';

  String get arabicClean =>
      arabic.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '').trim();

  QuranWord copyWith({
    bool? isKnown,
    String? urduMeaning,
    String? transliteration,
    List<WordSegment>? segments,
  }) =>
      QuranWord(
        id: id,
        arabic: arabic,
        urduMeaning: urduMeaning ?? this.urduMeaning,
        transliteration: transliteration ?? this.transliteration,
        isKnown: isKnown ?? this.isKnown,
        isWaqf: isWaqf,
        segments: segments ?? this.segments,
      );
}