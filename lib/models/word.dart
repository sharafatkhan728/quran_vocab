import '../services/morphology_service.dart';

class QuranWord {
  final String id;         // "surah:ayah:wordPos"
  final String arabic;     // full word text with harkat
  final String urduMeaning;
  final String transliteration;
  final bool isKnown;
  final List<WordSegment> segments; // morphology segments

  const QuranWord({
    required this.id,
    required this.arabic,
    this.urduMeaning = '',
    this.transliteration = '',
    this.isKnown = false,
    this.segments = const [],
  });

  /// Stem segment (main word, determines color/POS)
  WordSegment? get stem =>
      segments.where((s) => s.type == SegType.stem).firstOrNull;

  String get root => stem?.root ?? '';
  String get lemma => stem?.lemma ?? '';
  String get pos => stem?.pos ?? '';

  QuranWord copyWith({
    bool? isKnown,
    String? urduMeaning,
    
    List<WordSegment>? segments,
  }) => QuranWord(
    id: id,
    arabic: arabic,
    urduMeaning: urduMeaning ?? this.urduMeaning,
    transliteration: transliteration,
    isKnown: isKnown ?? this.isKnown,
    segments: segments ?? this.segments,
  );
}