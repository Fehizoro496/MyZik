import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/device_music_repository.dart';
import '../data/storage_access.dart';
import '../models.dart';
import '../sync/sync_files.dart';
import 'app_database_provider.dart';
import 'downloads_provider.dart';
import 'library_provider.dart';
import 'playback_provider.dart';
import 'received_tracks_provider.dart';

/// Deletes songs' audio files from this device: YouTube downloads and files
/// received from the other device from the app's folders, the rest from the
/// device's music (with [storageAccessProvider] on Android, from the music
/// folders on computers).
///
/// Deleted songs are remembered ([removedKeys]) so that syncing doesn't
/// bring their files back on its own; picking one by hand still does.
class SongDeletion {
  SongDeletion(this._ref);

  final Ref _ref;

  static const _removedKeysSetting = 'sync.removedSongKeys';

  /// Whether this device can delete [song]'s file.
  bool canDelete(Song song) {
    if (kIsWeb) return false;
    if (_download(song) != null || _received(song) != null) return true;
    if (Platform.isIOS) return false;
    return song.filePath != null;
  }

  /// Deletes [song]'s file. False when it couldn't be, or (on Android) the
  /// listener doesn't grant the permission to.
  Future<bool> delete(Song song) async {
    final playback = _ref.read(playbackProvider.notifier);
    if (_download(song) case final download?) {
      await playback.removeSong(song);
      await _ref.read(downloadsProvider.notifier).remove(download.videoId);
    } else if (_received(song) case final track?) {
      await playback.removeSong(song);
      await _ref.read(receivedTracksProvider.notifier).remove(track);
    } else {
      final path = song.filePath;
      if (path == null) return false;
      final android = !kIsWeb && Platform.isAndroid;
      if (android) {
        // Asked at first launch; asked again if it was declined.
        final access = _ref.read(storageAccessProvider);
        if (!await access.granted() && !await access.request()) return false;
      }
      // The player lets go of the file first: Windows can't delete it open.
      await playback.removeSong(song);
      try {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      } on FileSystemException {
        return false;
      }
      if (android) unawaited(DeviceMusicRepository.forgetFile(path));
      _ref.read(libraryProvider.notifier).removeSong(song);
    }
    await _remember(song.songKey);
    return true;
  }

  /// Keys of the songs deleted on this device.
  Set<String> get removedKeys => _ref
      .read(appDatabaseProvider)
      .getStringListSetting(_removedKeysSetting)
      .toSet();

  /// Forgets that [songKey] was deleted: its file is back on this device.
  Future<void> restored(String songKey) async {
    final keys = removedKeys;
    if (!keys.remove(songKey)) return;
    await _ref
        .read(appDatabaseProvider)
        .setStringListSetting(_removedKeysSetting, keys.toList());
  }

  Future<void> _remember(String songKey) async {
    if (songKey.startsWith('meta:')) return;
    final keys = removedKeys;
    if (!keys.add(songKey)) return;
    await _ref
        .read(appDatabaseProvider)
        .setStringListSetting(_removedKeysSetting, keys.toList());
  }

  DownloadedTrack? _download(Song song) =>
      _ref.read(downloadsProvider).bySongId(song.id);

  TrackFile? _received(Song song) {
    final path = song.filePath;
    if (path == null) return null;
    return _ref
        .read(receivedTracksProvider)
        .where((t) => t.path == path)
        .firstOrNull;
  }
}

final songDeletionProvider = Provider<SongDeletion>(SongDeletion.new);

final storageAccessProvider = Provider<StorageAccess>(
  (ref) => const StorageAccess(),
);
