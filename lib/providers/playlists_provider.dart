import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/song_key.dart';
import '../models.dart';
import 'library_provider.dart';
import 'shared_preferences_provider.dart';

const _kPlaylists = SongKeyMigration.playlistsPreference;

/// The user's playlists, persisted to [SharedPreferences] as a JSON array so
/// they survive an app restart. Like liked songs, tracks are stored as
/// [Song.songKey]s rather than full [Song]s, so a playlist outlives a library
/// rescan and means the same tracks on every device.
class PlaylistsNotifier extends Notifier<List<Playlist>> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  List<Playlist> build() {
    final raw = _prefs.getString(_kPlaylists);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return [
        for (final e in decoded) Playlist.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      // Corrupt or outdated payload — start clean rather than crash.
      return const [];
    }
  }

  /// Creates an empty playlist named [name] and returns it (so the caller can
  /// navigate straight into it).
  Playlist create(String name) {
    final playlist = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
    );
    state = [...state, playlist];
    _persist();
    return playlist;
  }

  void rename(String id, String name) {
    state = [
      for (final p in state)
        if (p.id == id) p.copyWith(name: name.trim()) else p,
    ];
    _persist();
  }

  void delete(String id) {
    state = [
      for (final p in state)
        if (p.id != id) p,
    ];
    _persist();
  }

  /// Appends [song] to the playlist unless it is already there (playlists
  /// are sets in disguise — no duplicate tracks).
  void addSong(String id, Song song) {
    final key = song.songKey;
    state = [
      for (final p in state)
        if (p.id == id && !p.songKeys.contains(key))
          p.copyWith(songKeys: [...p.songKeys, key])
        else
          p,
    ];
    _persist();
  }

  void removeSong(String id, Song song) {
    final key = song.songKey;
    state = [
      for (final p in state)
        if (p.id == id)
          p.copyWith(
            songKeys: [
              for (final k in p.songKeys)
                if (k != key) k,
            ],
          )
        else
          p,
    ];
    _persist();
  }

  /// Reorders the playlist to [ordered] (the songs the UI shows, in their new
  /// order). Keys not shown — e.g. tracks missing from the current library —
  /// are kept, appended in their previous order.
  void reorderSongs(String id, List<Song> ordered) {
    final shown = [for (final song in ordered) song.songKey];
    final shownSet = shown.toSet();
    state = [
      for (final p in state)
        if (p.id == id)
          p.copyWith(
            songKeys: [
              ...shown,
              for (final key in p.songKeys)
                if (!shownSet.contains(key)) key,
            ],
          )
        else
          p,
    ];
    _persist();
  }

  void _persist() {
    _prefs.setString(
      _kPlaylists,
      jsonEncode([for (final p in state) p.toJson()]),
    );
  }
}

final playlistsProvider = NotifierProvider<PlaylistsNotifier, List<Playlist>>(
  PlaylistsNotifier.new,
);

/// The playlist currently opened in `PlaylistScreen`, by id. Set before
/// navigating to [AppScreen.playlist].
final selectedPlaylistIdProvider = StateProvider<String?>((ref) => null);

/// Looks up a single playlist by id. Null once it's been deleted.
final playlistByIdProvider = Provider.family<Playlist?, String>((ref, id) {
  final playlists = ref.watch(playlistsProvider);
  for (final p in playlists) {
    if (p.id == id) return p;
  }
  return null;
});

/// Resolves a playlist's [Song]s from the library in playlist order, skipping
/// keys no longer present (e.g. after a rescan). Rebuilds when the playlist or
/// the library changes.
final playlistSongsProvider = Provider.family<List<Song>, String>((ref, id) {
  final playlist = ref.watch(playlistByIdProvider(id));
  if (playlist == null) return const [];
  final library = ref.watch(libraryProvider.select((s) => s.songs));
  final byKey = <String, Song>{};
  for (final song in library) {
    byKey.putIfAbsent(song.songKey, () => song);
  }
  return [for (final key in playlist.songKeys) ?byKey[key]];
});
