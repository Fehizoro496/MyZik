import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../sync/sync_store.dart';
import 'app_database_provider.dart';
import 'sync_providers.dart';

/// The liked songs, as a set of [Song.songKey]s persisted to
/// [SharedPreferences] so likes survive an app restart. Keys rather than full
/// [Song]s, so a like outlives a library rescan, works for streamed tracks and
/// means the same recording on every device. Likes saved by older versions
/// under [Song.id]s are moved here by [SongKeyMigration].
class LikedNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.read(appDatabaseProvider).likedKeys;

  bool isLiked(Song song) => state.contains(song.songKey);

  void toggle(Song song) {
    final key = song.songKey;
    final next = Set<String>.from(state);
    final liked = next.add(key);
    if (!liked) next.remove(key);
    _save(next);
    ref.read(syncStoreProvider).touch(SyncIds.forLike(key), deleted: !liked);
  }

  /// Applies a like or unlike made on another device.
  void setFromSync(String songKey, {required bool liked}) {
    final next = Set<String>.from(state);
    if (liked ? next.add(songKey) : next.remove(songKey)) _save(next);
  }

  void _save(Set<String> keys) {
    state = keys;
    ref.read(appDatabaseProvider).replaceLikes(keys);
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
