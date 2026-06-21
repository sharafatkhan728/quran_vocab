class QuranWord {
  final String id;
  final String arabic;
  final String urduMeaning;
  final String transliteration;
  final String wordType;
  final List<WordPart> parts;

  bool isKnown;

  QuranWord({
    required this.id,
    required this.arabic,
    required this.urduMeaning,
    this.transliteration = '',
    this.wordType = '',
    this.parts = const [],
    this.isKnown = false,
  });
}

class WordPart {
  final String text;
  final String pos;

  const WordPart({
    required this.text,
    required this.pos,
  });
}