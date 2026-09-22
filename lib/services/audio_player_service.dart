import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';

/// Centralized audio player service for word-by-word Quran audio.
///
/// Manages a single [AudioPlayer] instance shared across all screens.
/// Use [playWordAudio] to play an ayah word, [stop] to halt playback,
/// and [isPlaying] to track current state.
class AudioPlayerService {
  AudioPlayerService._();

  static final AudioPlayerService instance = AudioPlayerService._();

  final AudioPlayer _player = AudioPlayer();

  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);

  /// Plays word-by-word audio for the given surah, ayah, and word position.
  /// URL format: https://audio.qurancdn.com/wbw/{surah}_{ayah}_{word}.mp3
  Future<void> playWordAudio(int surah, int ayah, int wordPos) async {
    final s = surah.toString().padLeft(3, '0');
    final a = ayah.toString().padLeft(3, '0');
    final w = wordPos.toString().padLeft(3, '0');
    final url = 'https://audio.qurancdn.com/wbw/$s _$a _$w.mp3';
    try {
      isPlaying.value = true;
      await _player.setUrl(url);
      await _player.play();
    } catch (e) {
      debugPrint('AudioPlayerService.playWordAudio error: $e');
    } finally {
      isPlaying.value = false;
    }
  }

  /// Stops current playback.
  Future<void> stop() async {
    isPlaying.value = false;
    await _player.stop();
  }

  /// Disposes the underlying player. Call once at app shutdown.
  void dispose() {
    _player.dispose();
  }
}
