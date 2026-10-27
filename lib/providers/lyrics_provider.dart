import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lyrics_repository.dart';
import '../models.dart';
import '../sync/sync_store.dart';
import 'sync_providers.dart';

final lyricsRepositoryProvider = Provider<LyricsRepository>(
  (ref) => LyricsRepository(
    // Lyrics follow the track to the listener's other devices, timings
    // included; what the listener made outranks what was found online.
    onStored: (songKey, {required found}) => ref
        .read(syncStoreProvider)
        .touch(SyncIds.forLyrics(songKey), found: found),
  ),
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
