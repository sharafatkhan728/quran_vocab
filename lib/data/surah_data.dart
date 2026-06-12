import 'package:quran/quran.dart' as quran;
import '../models/surah.dart';

List<Surah> buildSurahList() {
  return List.generate(114, (i) {
    final id = i + 1;
    return Surah(
      id: id,
      englishName: quran.getSurahName(id),
      arabicName: quran.getSurahNameArabic(id),
      urduName: quran.getSurahName(id),
      verseCount: quran.getVerseCount(id),
    );
  });
}