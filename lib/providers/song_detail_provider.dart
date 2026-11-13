import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'library_provider.dart';

/// The song currently shown in `SongDetailScreen`. Set right before navigating
/// to [AppScreen.songDetail]. Holds the full [Song] (not just an id) so it works
/// for tracks from any source — library, search results, a playlist.
final selectedSongProvider = StateProvider<Song?>((ref) => null);

/// [selectedSongProvider] as the library now shows it: its tags and cover
/// may have been edited since it was selected.
final shownSongProvider = Provider<Song?>((ref) {
  final selected = ref.watch(selectedSongProvider);
  if (selected == null || !selected.hasStableKey) return selected;
  return ref.watch(
        libraryProvider.select(
          (s) => s.songs
              .where((song) => song.songKey == selected.songKey)
              .firstOrNull,
        ),
      ) ??
      selected;
});
