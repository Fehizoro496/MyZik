import 'dart:typed_data';

import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../models.dart';
import 'music_repository.dart';

/// Reads the on-device audio library via MediaStore (Android) / the media
/// library (iOS) using on_audio_query. This is the only file that imports the
/// plugin, so the rest of the app has no dependency on it.
class DeviceMusicRepository implements MusicRepository {
  final OnAudioQuery _query = OnAudioQuery();

  @override
  bool get isSupported => true;

  @override
  Future<bool> ensurePermission() async {
    var granted = await _query.permissionsStatus();
    if (!granted) {
      granted = await _query.permissionsRequest();
    }
    return granted;
  }

  @override
  Future<List<Song>> fetchSongs() async {
    final models = await _query.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    // Exclude ringtones / alarms / notifications rather than requiring
    // isMusic == true: on many devices IS_MUSIC is 0 for legitimate tracks
    // (depending on the folder), which would wrongly hide them.
    return models
        .where(
          (m) =>
              (m.duration ?? 0) > 0 &&
              m.isRingtone != true &&
              m.isAlarm != true &&
              m.isNotification != true,
        )
        .map(_toSong)
        .toList();
  }

  @override
  Future<Uint8List?> artworkFor(int id) {
    return _query.queryArtwork(
      id,
      ArtworkType.AUDIO,
      format: ArtworkFormat.JPEG,
      size: 400,
    );
  }

  Song _toSong(SongModel m) => Song(
    id: m.id,
    title: m.title,
    artist: (m.artist == null || m.artist == '<unknown>')
        ? 'Unknown artist'
        : m.artist!,
    album: m.album,
    duration: Duration(milliseconds: m.duration ?? 0),
    uri: m.uri,
  );
}
