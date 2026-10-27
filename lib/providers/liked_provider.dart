import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/song_key.dart';
import '../models.dart';
import 'shared_preferences_provider.dart';

/// The liked songs, as a set of [Song.songKey]s persisted to
/// [SharedPreferences] so likes survive an app restart. Keys rather than full
/// [Song]s, so a like outlives a library rescan, works for streamed tracks and
/// means the same recording on every device. Likes saved by older versions
/// under [Song.id]s are moved here by [SongKeyMigration].
class LikedNotifier extends Notifier<Set<String>> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Set<String> build() => {
    ...?_prefs.getStringList(SongKeyMigration.likedKeysPreference),
  };

  bool isLiked(Song song) => state.contains(song.songKey);

  void toggle(Song song) {
    final next = Set<String>.from(state);
    if (!next.add(song.songKey)) next.remove(song.songKey);
    state = next;
    _prefs.setStringList(SongKeyMigration.likedKeysPreference, next.toList());
  }
}

final likedProvider = NotifierProvider<LikedNotifier, Set<String>>(
  LikedNotifier.new,
);

/// Whether the song with this [Song.songKey] is liked. Rebuilds only when
/// *that* key's membership changes, so a heart on one row doesn't rebuild
/// every other.
final isLikedProvider = Provider.family<bool, String>((ref, songKey) {
  return ref.watch(likedProvider.select((keys) => keys.contains(songKey)));
});
