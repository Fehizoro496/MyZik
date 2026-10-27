import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lyrics_repository.dart';
import '../models.dart';

final lyricsRepositoryProvider = Provider<LyricsRepository>(
  (ref) => LyricsRepository(),
);

/// Lyrics for one track: cache, then LRCLIB, then a web search through Groq.
/// Null when none could be found.
class LyricsNotifier extends AutoDisposeFamilyAsyncNotifier<Lyrics?, Song> {
  @override
  Future<Lyrics?> build(Song song) =>
      ref.read(lyricsRepositoryProvider).find(song);

  /// Searches again (LRCLIB, then the web), ignoring a cached "not found" or
  /// a previous error.
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(lyricsRepositoryProvider).find(arg, refresh: true),
    );
  }

  /// Stores timestamps manually matched to the current playback position.
  /// Throws on failure and keeps the current lyrics, so a failed save never
  /// hides them behind an error.
  Future<void> saveSynchronization(List<LyricLine> lines) async {
    final lyrics = state.asData?.value;
    if (lyrics == null) return;
    state = AsyncData(
      await ref
          .read(lyricsRepositoryProvider)
          .saveSynchronization(arg, lyrics, lines),
    );
  }

  /// Replaces the lyrics with a version edited (or written) by hand: text,
  /// timings or both. Throws on failure and keeps the current lyrics.
  Future<void> saveEdited(Lyrics lyrics) async {
    state = AsyncData(
      await ref.read(lyricsRepositoryProvider).saveLyrics(arg, lyrics),
    );
  }
}

final lyricsProvider = AsyncNotifierProvider.autoDispose
    .family<LyricsNotifier, Lyrics?, Song>(LyricsNotifier.new);
