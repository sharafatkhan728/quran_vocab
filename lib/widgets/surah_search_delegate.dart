import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;

class SurahSearchDelegate extends SearchDelegate<String> {
  final Function(int surahId, int? ayahNumber) onSurahSelected;

  SurahSearchDelegate({required this.onSurahSelected});

  @override
  String get searchFieldLabel => 'Search surah or 2:255 for ayah...';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, ''),
      );

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults(context);

  Widget _buildSearchResults(BuildContext context) {
    // Check if user typed surah:ayah format e.g. "2:255"
    final colonFormat = RegExp(r'^(\d+):(\d+)$');
    final colonMatch = colonFormat.firstMatch(query.trim());

    if (colonMatch != null) {
      final surahId = int.parse(colonMatch.group(1)!);
      final ayahNum = int.parse(colonMatch.group(2)!);

      if (surahId >= 1 && surahId <= 114) {
        final verseCount = quran.getVerseCount(surahId);
        if (ayahNum >= 1 && ayahNum <= verseCount) {
          return ListTile(
            leading: const Icon(Icons.my_location),
            title: Text(
              'Jump to Surah $surahId, Ayah $ayahNum',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${quran.getSurahName(surahId)} • ${quran.getSurahNameArabic(surahId)}',
              textDirection: TextDirection.rtl,
            ),
            onTap: () {
              close(context, '');
              onSurahSelected(surahId, ayahNum);
            },
          );
        } else {
          return Center(
            child: Text(
              'Surah $surahId has only $verseCount ayahs',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
      }
    }

    // Normal surah name search
    final results = <int>[];
    final q = query.toLowerCase().trim();

    if (q.isEmpty) {
      // Show all 114
      results.addAll(List.generate(114, (i) => i + 1));
    } else {
      for (int i = 1; i <= 114; i++) {
        final english = quran.getSurahName(i).toLowerCase();
        final arabic = quran.getSurahNameArabic(i);
        final number = i.toString();
        if (english.contains(q) || arabic.contains(q) || number == q) {
          results.add(i);
        }
      }
    }

    if (results.isEmpty) {
      return const Center(child: Text('No surah found'));
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final id = results[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              '$id',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          title: Text(
            quran.getSurahNameArabic(id),
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontSize: 18),
          ),
          subtitle: Text(
            '${quran.getSurahName(id)} • ${quran.getVerseCount(id)} verses',
          ),
          onTap: () {
            close(context, '');
            onSurahSelected(id, null);
          },
        );
      },
    );
  }
}
