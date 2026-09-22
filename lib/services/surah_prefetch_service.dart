import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_importer.dart';
import '../models/word.dart';
import '../repositories/content_repository.dart';
import 'word_glossary_service.dart';

/// Silently builds and disk-caches every surah's word-by-word data in the
/// background after app launch, so opening any surah later is instant
/// instead of showing a loading spinner. Writes to the exact same disk
/// cache format/location that SurahReaderScreen itself reads from, so the
/// two never conflict — whichever gets there first "wins" and the other
/// just finds the cache already valid and skips it.
///
/// Runs with small pauses between surahs so it never competes with the UI
/// thread for long stretches — the user should never notice it running.
class SurahPrefetchService {
  SurahPrefetchService._();

  static bool _started = false;

  // If the user opens a surah manually while the background pass hasn't
  // reached it yet, this makes that surah get processed next instead of
  // waiting its turn in sequence — so nearby content becomes ready sooner
  // too, without making the user's own open feel slow (that open already
  // happens independently and instantly via SurahReaderScreen's own logic;
  // this only affects what the background pass does next).
  static int? _priorityHint;

  static void prioritize(int surahId) {
    _priorityHint = surahId;
  }

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  static Future<void> _run() async {
    try {
      final lang = WordGlossaryService.selectedLang;
      final prefs = await SharedPreferences.getInstance();
      const versionKey = 'surah_prefetch_version';
      final doneKey = 'surah_prefetch_done_$lang';
      final currentVersion = DatabaseImporter.contentCacheVersion;

      // Content data changed since the last prefetch pass (e.g. an app
      // update with new vocab/morphology) — old progress no longer valid.
      if (prefs.getString(versionKey) != currentVersion) {
        await prefs.setString(versionKey, currentVersion);
        await prefs.remove(doneKey);
      }

      final done = (prefs.getStringList(doneKey) ?? []).toSet();
      final remaining = [
        for (int i = 1; i <= 114; i++)
          if (!done.contains('$i')) i
      ];

      while (remaining.isNotEmpty) {
        int next;
        final hint = _priorityHint;
        if (hint != null && remaining.contains(hint)) {
          next = hint;
        } else {
          next = remaining.first;
        }
        _priorityHint = null;
        remaining.remove(next);

        await _buildAndCacheSurah(next, lang);
        done.add('$next');
        await prefs.setStringList(doneKey, done.toList());

        // Brief pause between surahs — keeps this truly low-priority so it
        // never noticeably competes with whatever the user is doing.
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      debugPrint('SurahPrefetchService: $e');
    }
  }

  static Future<void> _buildAndCacheSurah(int surahId, String lang) async {
    final ayahRows = await ContentRepository.getAyahsForSurah(surahId);
    if (ayahRows.isEmpty) return;

    final key = '${surahId}_${lang}_${DatabaseImporter.contentCacheVersion}';
    final file = await _cacheFile(key);

    // Already fully cached (e.g. the user opened this surah themselves and
    // SurahReaderScreen already wrote it) — nothing to do.
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded.length == ayahRows.length) return;
      } catch (_) {
        // Corrupt/partial file — fall through and rebuild it.
      }
    }

    final jsonMap = <String, dynamic>{};
    for (final ayah in ayahRows) {
      final words = await _buildWordsForAyah(ayah, lang);
      jsonMap['${ayah.ayahNumber}'] = words.map(_wordToJson).toList();
      // Yield to the event loop after every ayah so this never holds the
      // UI thread for long — each ayah is small, so this is cheap.
      await Future.delayed(Duration.zero);
    }

    try {
      await file.writeAsString(jsonEncode(jsonMap));
    } catch (_) {
      // Non-fatal — worst case this surah just builds normally when opened.
    }
  }

  static Future<List<QuranWord>> _buildWordsForAyah(
      AyahRow ayah, String lang) async {
    final wordRows = await ContentRepository.getWordsForAyah(ayah.id);
    final translations =
        await ContentRepository.getWordTranslationsForAyah(ayah.id, lang);
    final morphSegments = await ContentRepository.getSegmentsForAyah(ayah.id);

    final result = <QuranWord>[];
    for (final wr in wordRows) {
      final meaning = translations[wr.id]?[lang]?.text ?? '';
      final segRows = morphSegments[wr.id] ?? [];
      final segments = segRows.map(WordSegment.fromRow).toList();
      result.add(QuranWord(
        id: '${ayah.surahId}:${ayah.ayahNumber}:${wr.position}',
        arabic: wr.arabicText,
        urduMeaning: meaning,
        // Never read back from cache (see _wordFromJson in
        // surah_reader_screen.dart) — always recomputed live at render
        // time, so its value here doesn't matter.
        isKnown: false,
        isWaqf: wr.isWaqf == 1,
        segments: segments,
      ));
    }
    return result;
  }

  static Map<String, dynamic> _wordToJson(QuranWord w) => {
        'id': w.id,
        'arabic': w.arabic,
        'urduMeaning': w.urduMeaning,
        'isWaqf': w.isWaqf,
        'segments': w.segments
            .map((s) => {
                  'segNum': s.segNum,
                  'type': s.type.index,
                  'pos': s.pos,
                  'root': s.root,
                  'lemma': s.lemma,
                  'tense': s.tense,
                  'person': s.person,
                  'gender': s.gender,
                  'number': s.number,
                  'grammaticalCase': s.grammaticalCase,
                  'voice': s.voice,
                  'state': s.state,
                  'verbForm': s.verbForm,
                  'segArabic': s.arabic,
                  'colorHex': s.colorHex,
                })
            .toList(),
      };

  static Future<File> _cacheFile(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(
        '${dir.path}/surah_word_cache_v${DatabaseImporter.contentCacheVersion}');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/$key.json');
  }
}