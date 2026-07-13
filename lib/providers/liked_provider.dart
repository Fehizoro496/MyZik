import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_provider.dart';

const _kLikedIds = 'liked.songIds';

/// The set of liked song ids, persisted to [SharedPreferences] so likes
/// survive an app restart. Stored as a list of stringified [Song.id]s (the
/// prefs API has no int-list setter). Kept as ids rather than full [Song]s so a
/// like outlives a library rescan and never duplicates track data.
class LikedNotifier extends Notifier<Set<int>> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Set<int> build() {
    final stored = _prefs.getStringList(_kLikedIds) ?? const [];
    return stored.map(int.tryParse).whereType<int>().toSet();
  }

  bool isLiked(int songId) => state.contains(songId);

  void toggle(int songId) {
    final next = Set<int>.from(state);
    if (!next.add(songId)) next.remove(songId);
    state = next;
    _prefs.setStringList(_kLikedIds, next.map((id) => id.toString()).toList());
  }
}

final likedProvider = NotifierProvider<LikedNotifier, Set<int>>(
  LikedNotifier.new,
);

/// Whether a specific song id is currently liked. Rebuilds only when *that*
/// id's membership changes, so a heart on one row doesn't rebuild every other.
final isLikedProvider = Provider.family<bool, int>((ref, songId) {
  return ref.watch(likedProvider.select((ids) => ids.contains(songId)));
});
