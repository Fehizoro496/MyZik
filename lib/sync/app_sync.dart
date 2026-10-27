import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/desktop_music_repository.dart' show readArtwork;
import '../data/song_key.dart';
import '../providers/library_provider.dart';
import '../providers/liked_provider.dart';
import '../providers/lyrics_provider.dart';
import '../providers/playlists_provider.dart';
import '../providers/received_tracks_provider.dart';
import 'sync_engine.dart';
import 'sync_files.dart';
import 'sync_store.dart';

/// [SyncData] over the app's providers: likes, playlists and every song's
/// lyrics, with their timings.
class AppSyncData implements SyncData {
  AppSyncData(this._ref);

  final Ref _ref;

  @override
  Future<Map<String, bool>> existing() async => {
    for (final key in _ref.read(likedProvider)) SyncIds.forLike(key): false,
    for (final p in _ref.read(playlistsProvider))
      SyncIds.forPlaylist(p.id): false,
    for (final MapEntry(key: key, value: found)
        in (await _ref.read(lyricsRepositoryProvider).storedLyrics()).entries)
      SyncIds.forLyrics(key): found,
  };

  @override
  Future<Object?> read(String id) async {
    if (_after(id, SyncIds.like) case final key?) {
      return _ref.read(likedProvider).contains(key) ? const {} : null;
    }
    if (_after(id, SyncIds.playlist) case final playlistId?) {
      final playlist = _ref
          .read(playlistsProvider)
          .where((p) => p.id == playlistId)
          .firstOrNull;
      return playlist == null
          ? null
          : {'name': playlist.name, 'songKeys': playlist.songKeys};
    }
    if (_after(id, SyncIds.lyrics) case final key?) {
      return _ref.read(lyricsRepositoryProvider).readStoredLyrics(key);
    }
    return null;
  }

  @override
  Future<void> apply(String id, Object? value, {required bool deleted}) async {
    if (_after(id, SyncIds.like) case final key?) {
      _ref.read(likedProvider.notifier).setFromSync(key, liked: !deleted);
    } else if (_after(id, SyncIds.playlist) case final playlistId?) {
      final playlists = _ref.read(playlistsProvider.notifier);
      if (deleted || value is! Map) {
        playlists.removeFromSync(playlistId);
      } else {
        playlists.putFromSync(
          playlistId,
          name: value['name'] as String? ?? 'Playlist',
          songKeys: [
            for (final key in value['songKeys'] as List? ?? const [])
              if (key is String) key,
          ],
        );
      }
    } else if (_after(id, SyncIds.lyrics) case final key?) {
      final repository = _ref.read(lyricsRepositoryProvider);
      if (deleted || value is! Map) {
        await repository.deleteLyrics(key);
      } else {
        await repository.writeSyncedLyrics(
          key,
          Map<String, dynamic>.from(value),
        );
      }
      // Lyrics on screen are read again.
      _ref.invalidate(lyricsProvider);
    }
  }

  @override
  Future<List<String>> aliases(String id, Object? value) async {
    final key = _after(id, SyncIds.lyrics);
    final metadata = value is Map ? value['_songMetadata'] : null;
    if (key == null || metadata is! String) return const [];
    return {
      for (final song in _ref.read(libraryProvider).songs)
        if (song.songKey != key &&
            SongKey.sameRecording(song.metadataKey, metadata))
          SyncIds.forLyrics(song.songKey),
    }.toList();
  }

  static String? _after(String id, String prefix) =>
      id.startsWith(prefix) ? id.substring(prefix.length) : null;
}

/// [SyncFiles] over the library: every song with a file and a portable key
/// can be sent; files received go to [receivedTracksProvider].
class AppSyncFiles implements SyncFiles {
  AppSyncFiles(this._ref);

  final Ref _ref;

  @override
  Future<List<TrackFile>> localFiles() async {
    final seen = <String>{};
    return [
      for (final song in _ref.read(libraryProvider).songs)
        if (TrackFile.ofSong(song) case final file? when seen.add(file.songKey))
          file,
    ];
  }

  @override
  Future<List<int>?> coverOf(TrackFile track) async {
    final song = _ref
        .read(libraryProvider)
        .songs
        .where((s) => s.songKey == track.songKey)
        .firstOrNull;
    if (song == null) return null;
    // Downloads and received files keep their cover in a file of its own.
    final url = song.artworkUrl;
    if (url != null && url.startsWith('file:')) {
      try {
        return await File(Uri.parse(url).toFilePath()).readAsBytes();
      } catch (_) {
        return null;
      }
    }
    final path = song.filePath;
    if (path == null) return null;
    return Isolate.run(() => readArtwork(path));
  }

  @override
  Future<File> incomingFile(TrackFile track) async =>
      (await _ref.read(receivedTracksProvider.notifier).store).incomingFile(
        track,
      );

  @override
  Future<void> receive(TrackFile track, File file, {List<int>? cover}) =>
      _ref.read(receivedTracksProvider.notifier).add(track, file, cover: cover);
}
