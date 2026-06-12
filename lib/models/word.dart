class QuranWord {
  final String id;
  final String arabic;
  final String urduMeaning;
  final String transliteration;
  bool isKnown;

  QuranWord({
    required this.id,
    required this.arabic,
    required this.urduMeaning,
    this.transliteration = '',
    this.isKnown = false,
  });
}