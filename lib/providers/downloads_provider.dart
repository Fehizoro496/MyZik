import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/youtube_repository.dart';
import '../models.dart';
import 'library_provider.dart';
import 'shared_preferences_provider.dart';
import 'youtube_provider.dart';

const _kDownloads = 'downloads.tracks';

/// [Song.id] for a YouTube video, shared by the streamed and downloaded
/// versions so likes and playlists follow the track. Negative so it can never
/// collide with a MediaStore id.
int youtubeSongId(String videoId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in videoId.codeUnits) {
    hash = ((hash ^ codeUnit) * 0x01000193) & 0x7fffffff;
  }
  return -(hash + 1);
}

/// App-private folder holding downloaded audio and artwork. Private storage
/// needs no permission and keeps downloads out of other apps' libraries; they
/// are removed with the app.
final downloadsDirectoryProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationSupportDirectory();
  return Directory(
    '${base.path}${Platform.pathSeparator}downloads',
  ).create(recursive: true);
});

/// A YouTube track saved for offline playback. File names are stored relative
/// to [downloadsDirectoryProvider] since the app's data path may change.
class DownloadedTrack {
  DownloadedTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.duration,
    required this.audioFile,
    this.artworkFile,
    this.directory = '',
  });

  factory DownloadedTrack.fromJson(Map<String, dynamic> json) {
    return DownloadedTrack(
      videoId: json['videoId'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      duration: Duration(milliseconds: json['durationMs'] as int),
      audioFile: json['audioFile'] as String,
      artworkFile: json['artworkFile'] as String?,
    );
  }

  final String videoId;
  final String title;
  final String artist;
  final Duration duration;
  final String audioFile;
  final String? artworkFile;

  /// Absolute folder [audioFile] and [artworkFile] live in. Resolved at load
  /// time, never persisted.
  final String directory;

  String get audioPath => _path(audioFile);

  DownloadedTrack inDirectory(String directory) => DownloadedTrack(
    videoId: videoId,
    title: title,
    artist: artist,
    duration: duration,
    audioFile: audioFile,
    artworkFile: artworkFile,
    directory: directory,
  );

  /// Library entry for this download. Built once so list identity stays
  /// stable across library refreshes.
  late final Song song = Song(
    id: youtubeSongId(videoId),
    title: title,
    artist: artist,
    duration: duration,
    uri: Uri.file(audioPath).toString(),
    artworkUrl: artworkFile == null
        ? null
        : Uri.file(_path(artworkFile!)).toString(),
  );

  String _path(String file) => '$directory${Platform.pathSeparator}$file';

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'durationMs': duration.inMilliseconds,
    'audioFile': audioFile,
    'artworkFile': artworkFile,
  };
}

class DownloadsState {
  const DownloadsState({this.saved = const {}, this.progress = const {}});

  /// Completed downloads by video id, in download order.
  final Map<String, DownloadedTrack> saved;

  /// In-flight downloads by video id, from 0 to 1.
  final Map<String, double> progress;

  /// Library songs for [saved].
  List<Song> get songs => [for (final track in saved.values) track.song];

  DownloadedTrack? bySongId(int id) {
    for (final track in saved.values) {
      if (track.song.id == id) return track;
    }
    return null;
  }
}

/// Downloads YouTube audio into [downloadsDirectoryProvider] and keeps the
/// list of saved tracks in shared preferences. [libraryProvider] merges them
/// into the library so they play offline like any local file.
class DownloadsNotifier extends Notifier<DownloadsState> {
  /// Completes once saved downloads are read back from disk. Never throws.
  late Future<void> ready;

  @override
  DownloadsState build() {
    ready = Future.microtask(_restore).catchError((Object _) {});
    return const DownloadsState();
  }

  Future<void> _restore() async {
    final raw = ref.read(sharedPreferencesProvider).getStringList(_kDownloads);
    if (raw == null || raw.isEmpty) return;
    final dir = (await ref.read(downloadsDirectoryProvider.future)).path;
    final saved = <String, DownloadedTrack>{};
    for (final entry in raw) {
      try {
        final track = DownloadedTrack.fromJson(
          jsonDecode(entry) as Map<String, dynamic>,
        ).inDirectory(dir);
        // Skip entries whose file was removed behind the app's back.
        if (File(track.audioPath).existsSync()) saved[track.videoId] = track;
      } catch (_) {
        // Ignore a corrupt entry rather than losing every download.
      }
    }
    state = DownloadsState(
      saved: {...saved, ...state.saved},
      progress: state.progress,
    );
  }

  /// Saves [track]'s audio and artwork. Throws when the download fails; no
  /// partial file is left behind.
  Future<void> download(YouTubeTrack track) async {
    final id = track.videoId;
    if (state.saved.containsKey(id) || state.progress.containsKey(id)) return;
    _setProgress(id, 0);

    File? part;
    try {
      final dir = await ref.read(downloadsDirectoryProvider.future);
      final audio = await ref.read(youtubeRepositoryProvider).openAudio(id);
      final audioFile = '$id.${audio.extension}';
      part = File('${dir.path}${Platform.pathSeparator}$audioFile.part');

      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in audio.bytes) {
          sink.add(chunk);
          received += chunk.length;
          if (audio.totalBytes > 0) {
            final value = (received / audio.totalBytes).clamp(0.0, 1.0);
            // Rebuild listeners at most once per percent.
            if ((value * 100).floor() >
                ((state.progress[id] ?? 0) * 100).floor()) {
              _setProgress(id, value);
            }
          }
        }
      } finally {
        await sink.close();
      }
      // Only a complete file gets the final name.
      await part.rename('${dir.path}${Platform.pathSeparator}$audioFile');

      final artworkFile = await _saveArtwork(dir, track);
      final saved = DownloadedTrack(
        videoId: id,
        title: track.title,
        artist: track.artist,
        duration: track.duration,
        audioFile: audioFile,
        artworkFile: artworkFile,
      ).inDirectory(dir.path);

      state = DownloadsState(
        saved: {...state.saved, id: saved},
        progress: {...state.progress}..remove(id),
      );
      _persist();
    } catch (_) {
      if (part != null && part.existsSync()) await part.delete();
      state = DownloadsState(
        saved: state.saved,
        progress: {...state.progress}..remove(id),
      );
      rethrow;
    }
  }

  /// Saves the (de-letterboxed) cover next to the audio so the player keeps
  /// its artwork offline. Artwork is optional: failures are ignored.
  Future<String?> _saveArtwork(Directory dir, YouTubeTrack track) async {
    try {
      final bytes = await ref.read(
        coverArtProvider((
          id: youtubeSongId(track.videoId),
          url: track.thumbnailUrl,
        )).future,
      );
      if (bytes == null) return null;
      final name = '${track.videoId}.cover';
      await File(
        '${dir.path}${Platform.pathSeparator}$name',
      ).writeAsBytes(bytes, flush: true);
      return name;
    } catch (_) {
      return null;
    }
  }

  /// Deletes a download's files and forgets it.
  Future<void> remove(String videoId) async {
    final track = state.saved[videoId];
    if (track == null) return;
    state = DownloadsState(
      saved: {...state.saved}..remove(videoId),
      progress: state.progress,
    );
    _persist();
    for (final file in [track.audioFile, track.artworkFile]) {
      if (file == null) continue;
      final f = File('${track.directory}${Platform.pathSeparator}$file');
      try {
        if (f.existsSync()) await f.delete();
      } catch (_) {
        // A file still open by the player is cleaned up on the next removal.
      }
    }
  }

  void _setProgress(String id, double value) {
    state = DownloadsState(
      saved: state.saved,
      progress: {...state.progress, id: value},
    );
  }

  void _persist() {
    ref.read(sharedPreferencesProvider).setStringList(_kDownloads, [
      for (final track in state.saved.values) jsonEncode(track.toJson()),
    ]);
  }
}

final downloadsProvider = NotifierProvider<DownloadsNotifier, DownloadsState>(
  DownloadsNotifier.new,
);
