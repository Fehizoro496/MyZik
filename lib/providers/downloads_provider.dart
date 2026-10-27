import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/download_engine.dart';
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
    filePath: audioPath,
    youtubeVideoId: videoId,
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

/// A download that hasn't landed in the library yet.
class ActiveDownload {
  const ActiveDownload({
    required this.track,
    required this.phase,
    this.progress = 0,
  });

  final YouTubeTrack track;

  /// Never [DownloadPhase.complete] or [DownloadPhase.canceled]: those leave
  /// [DownloadsState.active].
  final DownloadPhase phase;

  /// 0 to 1.
  final double progress;

  bool get isFailed => phase == DownloadPhase.failed;

  ActiveDownload copyWith({DownloadPhase? phase, double? progress}) =>
      ActiveDownload(
        track: track,
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
      );
}

class DownloadsState {
  const DownloadsState({this.saved = const {}, this.active = const {}});

  /// Completed downloads by video id, in download order.
  final Map<String, DownloadedTrack> saved;

  /// Queued, running, interrupted and failed downloads by video id.
  final Map<String, ActiveDownload> active;

  /// Library songs for [saved].
  List<Song> get songs => [for (final track in saved.values) track.song];

  DownloadedTrack? bySongId(int id) {
    for (final track in saved.values) {
      if (track.song.id == id) return track;
    }
    return null;
  }

  DownloadsState copyWith({
    Map<String, DownloadedTrack>? saved,
    Map<String, ActiveDownload>? active,
  }) =>
      DownloadsState(saved: saved ?? this.saved, active: active ?? this.active);
}

final downloadEngineProvider = Provider<DownloadEngine>(
  (ref) => BackgroundDownloadEngine(),
);

/// Downloads YouTube audio into [downloadsDirectoryProvider] through the
/// [DownloadEngine], so transfers keep running in the background, survive the
/// app being closed and resume after a dropped connection. Saved tracks are
/// kept in shared preferences; [libraryProvider] merges them into the library
/// so they play offline like any local file.
class DownloadsNotifier extends Notifier<DownloadsState> {
  /// Completes once saved downloads are read back from disk. Never throws.
  late Future<void> ready;

  /// Completes once the engine is listened to and caught up. Never throws.
  late Future<void> engineReady;

  DownloadEngine get _engine => ref.read(downloadEngineProvider);

  @override
  DownloadsState build() {
    ready = Future.microtask(_restore).catchError((Object _) {});
    // Attached separately: the library only waits for [ready] and must not
    // hang on the native plugin. Saved downloads stay playable offline even
    // if the engine fails to start.
    engineReady = ready.then((_) => _attachEngine()).catchError((Object _) {});
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
    state = state.copyWith(saved: {...saved, ...state.saved});
  }

  /// Subscribes to the engine, then catches up on downloads that progressed
  /// or finished while the app was closed.
  Future<void> _attachEngine() async {
    final engine = _engine;
    final subscription = engine.events.listen(_onEvent);
    ref.onDispose(subscription.cancel);
    await engine.start();
    for (final event in await engine.pending()) {
      await _onEvent(event);
    }
  }

  Future<void> _onEvent(DownloadEvent event) async {
    final id = event.id;
    if (state.saved.containsKey(id)) {
      // Already in the library (e.g. replayed after a restart).
      if (event.phase == DownloadPhase.complete) await _engine.forget(id);
      return;
    }
    final current = state.active[id];
    final track = current?.track ?? _trackFromMeta(event.metaData);
    if (track == null) return;

    switch (event.phase) {
      case DownloadPhase.complete:
        await _finalize(id, track, event.metaData);
      case DownloadPhase.canceled:
        _setActive(id, null);
        await _engine.forget(id);
      case final DownloadPhase phase?:
        _setActive(
          id,
          (current ?? ActiveDownload(track: track, phase: phase)).copyWith(
            phase: phase,
            progress: event.progress,
          ),
        );
      case null:
        final progress = event.progress;
        if (progress == null) return;
        // Rebuild listeners at most once per percent.
        if (current != null &&
            current.phase == DownloadPhase.running &&
            (progress * 100).floor() == (current.progress * 100).floor()) {
          return;
        }
        _setActive(
          id,
          (current ??
                  ActiveDownload(track: track, phase: DownloadPhase.running))
              .copyWith(phase: DownloadPhase.running, progress: progress),
        );
    }
  }

  /// Moves a completed download into [DownloadsState.saved].
  Future<void> _finalize(
    String id,
    YouTubeTrack track,
    String? metaData,
  ) async {
    final dir = await ref.read(downloadsDirectoryProvider.future);
    final audioFile = _decodeMeta(metaData)?['audioFile'] as String?;
    if (audioFile == null || !File(_join(dir, audioFile)).existsSync()) {
      _setActive(id, ActiveDownload(track: track, phase: DownloadPhase.failed));
      return;
    }
    final artworkName = _artworkName(id);
    final saved = DownloadedTrack(
      videoId: id,
      title: track.title,
      artist: track.artist,
      duration: track.duration,
      audioFile: audioFile,
      artworkFile: File(_join(dir, artworkName)).existsSync()
          ? artworkName
          : null,
    ).inDirectory(dir.path);
    state = DownloadsState(
      saved: {...state.saved, id: saved},
      active: {...state.active}..remove(id),
    );
    _persist();
    await _engine.forget(id);
  }

  /// Starts (or retries) downloading [track]. Throws when the download could
  /// not be started, leaving it in the failed state so it can be retried.
  Future<void> download(YouTubeTrack track) async {
    final id = track.videoId;
    final current = state.active[id];
    if (state.saved.containsKey(id) || (current != null && !current.isFailed)) {
      return;
    }
    _setActive(id, ActiveDownload(track: track, phase: DownloadPhase.queued));

    try {
      await _engine.ensureNotificationPermission();
      // The cover is small: fetch it now, while the app is in the foreground,
      // so a download finishing in the background needs nothing else.
      final dir = await ref.read(downloadsDirectoryProvider.future);
      await _saveArtwork(dir, track);
      // Resolved on every attempt: stream URLs expire after a few hours.
      final source = await ref
          .read(youtubeRepositoryProvider)
          .resolveAudioSource(id);
      final audioFile = '$id.${source.extension}';
      final enqueued = await _engine.enqueue(
        DownloadJob(
          id: id,
          url: source.url,
          filename: audioFile,
          displayName: track.title,
          metaData: jsonEncode({
            ..._trackToJson(track),
            'audioFile': audioFile,
          }),
          headers: const {'User-Agent': youtubeStreamUserAgent},
        ),
      );
      if (!enqueued) throw StateError('download could not be enqueued');
    } catch (_) {
      _setActive(id, ActiveDownload(track: track, phase: DownloadPhase.failed));
      rethrow;
    }
  }

  /// Stops an in-flight download, or dismisses a failed one.
  Future<void> cancel(String videoId) async {
    final current = state.active[videoId];
    if (current == null) return;
    _setActive(videoId, null);
    if (!current.isFailed) await _engine.cancel(videoId);
    await _engine.forget(videoId);
  }

  /// Saves the (de-letterboxed) cover next to the audio so the player keeps
  /// its artwork offline. Artwork is optional: failures are ignored.
  Future<void> _saveArtwork(Directory dir, YouTubeTrack track) async {
    try {
      final bytes = await ref.read(
        coverArtProvider((
          id: youtubeSongId(track.videoId),
          url: track.thumbnailUrl,
        )).future,
      );
      if (bytes == null) return;
      await File(
        _join(dir, _artworkName(track.videoId)),
      ).writeAsBytes(bytes, flush: true);
    } catch (_) {
      // Keep downloading without artwork.
    }
  }

  /// Deletes a download's files and forgets it.
  Future<void> remove(String videoId) async {
    final track = state.saved[videoId];
    if (track == null) return;
    state = state.copyWith(saved: {...state.saved}..remove(videoId));
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

  void _setActive(String id, ActiveDownload? download) {
    final active = {...state.active};
    if (download == null) {
      active.remove(id);
    } else {
      active[id] = download;
    }
    state = state.copyWith(active: active);
  }

  void _persist() {
    ref.read(sharedPreferencesProvider).setStringList(_kDownloads, [
      for (final track in state.saved.values) jsonEncode(track.toJson()),
    ]);
  }

  static String _artworkName(String videoId) => '$videoId.cover';

  static String _join(Directory dir, String file) =>
      '${dir.path}${Platform.pathSeparator}$file';

  static Map<String, dynamic> _trackToJson(YouTubeTrack track) => {
    'videoId': track.videoId,
    'title': track.title,
    'artist': track.artist,
    'durationMs': track.duration.inMilliseconds,
    'thumbnailUrl': track.thumbnailUrl,
  };

  static Map<String, dynamic>? _decodeMeta(String? metaData) {
    if (metaData == null || metaData.isEmpty) return null;
    try {
      return jsonDecode(metaData) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static YouTubeTrack? _trackFromMeta(String? metaData) {
    final json = _decodeMeta(metaData);
    if (json == null) return null;
    try {
      return YouTubeTrack(
        videoId: json['videoId'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        duration: Duration(milliseconds: json['durationMs'] as int),
        thumbnailUrl: json['thumbnailUrl'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

final downloadsProvider = NotifierProvider<DownloadsNotifier, DownloadsState>(
  DownloadsNotifier.new,
);
