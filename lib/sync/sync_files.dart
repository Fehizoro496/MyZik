import 'dart:convert';
import 'dart:io';

import '../data/desktop_music_repository.dart' show songIdForPath;
import '../models.dart';

/// An audio file one device offers another: the track's identity and tags,
/// and where it is on the device that has it ([path], never sent).
class TrackFile {
  const TrackFile({
    required this.songKey,
    required this.title,
    required this.artist,
    required this.size,
    required this.extension,
    this.album,
    this.duration = Duration.zero,
    this.path,
    this.coverPath,
  });

  /// [Song.songKey]: `yt:` for YouTube downloads, `fp:` for other files.
  final String songKey;
  final String title;
  final String artist;
  final String? album;
  final Duration duration;
  final int size;

  /// Lower-case, with the dot (".mp3").
  final String extension;
  final String? path;

  /// The track's cover image on this device, for received files (never
  /// sent: covers travel on their own, see [SyncFiles.coverOf]).
  final String? coverPath;

  /// A track downloaded from YouTube (the "downloads only" transfer mode).
  bool get isDownload => songKey.startsWith('yt:');

  TrackFile at(String path, {String? coverPath}) => TrackFile(
    songKey: songKey,
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    size: size,
    extension: extension,
    path: path,
    coverPath: coverPath,
  );

  /// The library song for this file once it is on this device.
  Song toSong() {
    final file = path!;
    return Song(
      id: songIdForPath(file),
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      uri: Uri.file(file).toString(),
      filePath: file,
      youtubeVideoId: isDownload ? songKey.substring(3) : null,
      contentKey: songKey.startsWith('fp:') ? songKey : null,
      artworkUrl: coverPath == null ? null : Uri.file(coverPath!).toString(),
    );
  }

  /// The file behind [song], when it has one this device can send.
  static TrackFile? ofSong(Song song) {
    final path = song.filePath;
    final key = song.songKey;
    if (path == null || key.startsWith('meta:')) return null;
    final file = File(path);
    final int size;
    try {
      size = file.lengthSync();
    } catch (_) {
      return null;
    }
    final dot = path.lastIndexOf('.');
    return TrackFile(
      songKey: key,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
      size: size,
      extension: dot < 0 ? '' : path.substring(dot).toLowerCase(),
      path: path,
    );
  }

  Map<String, dynamic> toJson({bool withPath = false}) => {
    'key': songKey,
    'title': title,
    'artist': artist,
    if (album != null) 'album': album,
    'durationMs': duration.inMilliseconds,
    'size': size,
    'ext': extension,
    if (withPath && path != null) 'path': path,
    if (withPath && coverPath != null) 'cover': coverPath,
  };

  static TrackFile? tryFromJson(Object? json) {
    if (json is! Map) return null;
    try {
      final extension = json['ext'] as String? ?? '';
      // Extensions become file names: keep them short and plain.
      if (!RegExp(r'^(\.[a-z0-9]{1,5})?$').hasMatch(extension)) return null;
      return TrackFile(
        songKey: json['key'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String?,
        duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
        size: json['size'] as int,
        extension: extension,
        path: json['path'] as String?,
        coverPath: json['cover'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// The audio files of this device, for transfers between devices.
abstract class SyncFiles {
  /// Every file this device can send.
  Future<List<TrackFile>> localFiles();

  /// The cover image of [track] (one of [localFiles]), or null when it has
  /// none.
  Future<List<int>?> coverOf(TrackFile track);

  /// Where the bytes of [track] are written while it is received; reused to
  /// resume an interrupted transfer.
  Future<File> incomingFile(TrackFile track);

  /// Adds the complete [file] of [track] to this device's library, with its
  /// [cover] image when the other device had one.
  Future<void> receive(TrackFile track, File file, {List<int>? cover});
}

/// Files received from another device, kept in [directory] with an index of
/// their identity and tags: their key stays the one they had on the sending
/// device (a YouTube download stays `yt:`), so likes, playlists and lyrics
/// follow them.
class ReceivedTracksStore {
  ReceivedTracksStore(this.directory);

  final Directory directory;

  File get _index =>
      File('${directory.path}${Platform.pathSeparator}index.json');

  /// The received files still on disk.
  Future<List<TrackFile>> load() async {
    try {
      if (!_index.existsSync()) return const [];
      final entries = jsonDecode(await _index.readAsString()) as List;
      return [
        for (final entry in entries)
          if (TrackFile.tryFromJson(entry) case final track?
              when track.path != null && File(track.path!).existsSync())
            track.coverPath == null || File(track.coverPath!).existsSync()
                ? track
                : track.at(track.path!),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The partial file for [track], named after its key.
  File incomingFile(TrackFile track) => File(
    '${directory.path}${Platform.pathSeparator}'
    '${_safeName(track.songKey)}${track.extension}.part',
  );

  /// Moves the complete [file] in place, saves its [cover] next to it and
  /// indexes it. Returns the stored track.
  Future<TrackFile> add(TrackFile track, File file, {List<int>? cover}) async {
    await directory.create(recursive: true);
    final base =
        '${directory.path}${Platform.pathSeparator}'
        '${_safeName(track.songKey)}';
    final target = File('$base${track.extension}');
    if (target.existsSync()) await target.delete();
    await file.rename(target.path);
    final coverFile = File('$base.cover');
    if (cover != null && cover.isNotEmpty) {
      await coverFile.writeAsBytes(cover);
    } else if (coverFile.existsSync()) {
      await coverFile.delete();
    }
    final stored = track.at(
      target.path,
      coverPath: cover != null && cover.isNotEmpty ? coverFile.path : null,
    );
    final tracks = [
      for (final t in await load())
        if (t.songKey != track.songKey) t,
      stored,
    ];
    await _index.writeAsString(
      jsonEncode([for (final t in tracks) t.toJson(withPath: true)]),
    );
    return stored;
  }

  static String _safeName(String key) =>
      key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
}
