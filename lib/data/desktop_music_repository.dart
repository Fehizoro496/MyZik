import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'app_database.dart';
import 'music_repository.dart';

/// The library on a computer: the audio files under the folders the user
/// picked, with their tags. An index of every file (path, size, modification
/// time, tags) is kept on disk, so a rescan only reads the tags of new or
/// changed files.
class DesktopMusicRepository implements MusicRepository {
  DesktopMusicRepository({
    required SharedPreferences preferences,
    this.database,
    Future<Directory> Function()? indexDirectory,
  }) : _preferences = preferences,
       _indexDirectory = indexDirectory ?? getApplicationSupportDirectory;

  final SharedPreferences _preferences;
  final AppDatabase? database;
  final Future<Directory> Function() _indexDirectory;

  static const foldersPreference = 'library.folders.v1';

  /// Paths of the files behind the last [fetchSongs], by [Song.id], for
  /// [artworkFor].
  Map<int, String> _pathById = const {};

  /// The music folders, as picked by the user.
  List<String> get folders =>
      database != null && database!.hasSetting(foldersPreference)
      ? database!.getStringListSetting(foldersPreference)
      : _preferences.getStringList(foldersPreference) ?? const [];

  @override
  bool get isSupported => true;

  /// Files under the user's own folders need no permission.
  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<List<Song>> fetchSongs() async {
    final folders = this.folders;
    if (folders.isEmpty) {
      _pathById = const {};
      return const [];
    }
    final indexFile = database == null ? await _indexFile() : null;
    final cached = database == null
        ? await _readIndex(indexFile!)
        : _decodeIndex(database!.libraryIndex());
    final scan = await Isolate.run(() => scanLibrary(folders, cached));
    if (scan.changed) {
      if (database case final db?) {
        db.replaceLibraryIndex({
          for (final track in scan.tracks)
            track.path: jsonEncode(track.toJson()),
        });
      } else {
        await indexFile!.writeAsString(
          jsonEncode([for (final track in scan.tracks) track.toJson()]),
        );
      }
    }
    final songs = [for (final track in scan.tracks) track.toSong()];
    _pathById = {for (final song in songs) song.id: song.filePath!};
    return songs;
  }

  @override
  Future<Uint8List?> artworkFor(int id) async {
    final path = _pathById[id];
    if (path == null) return null;
    return Isolate.run(() => readArtwork(path));
  }

  Future<File> _indexFile() async {
    final dir = await _indexDirectory();
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}library_index.json');
  }

  static Future<Map<String, IndexedTrack>> _readIndex(File file) async {
    try {
      if (!file.existsSync()) return const {};
      final index = <String, IndexedTrack>{};
      for (final entry in jsonDecode(await file.readAsString()) as List) {
        final track = IndexedTrack.tryFromJson(entry);
        if (track != null) index[track.path] = track;
      }
      return index;
    } catch (_) {
      // Corrupt or outdated index: rebuild it from the files.
      return const {};
    }
  }

  static Map<String, IndexedTrack> _decodeIndex(Map<String, String> records) {
    final index = <String, IndexedTrack>{};
    for (final entry in records.entries) {
      final track = IndexedTrack.tryFromJson(jsonDecode(entry.value));
      if (track != null) index[entry.key] = track;
    }
    return index;
  }
}

/// One audio file of the library, as stored in the index.
class IndexedTrack {
  const IndexedTrack({
    required this.path,
    required this.size,
    required this.modifiedMs,
    required this.title,
    required this.artist,
    this.album,
    this.trackNumber,
    this.duration = Duration.zero,
  });

  final String path;
  final int size;
  final int modifiedMs;
  final String title;
  final String artist;
  final String? album;
  final int? trackNumber;
  final Duration duration;

  /// Whether this entry still describes the file as it is on disk.
  bool matches(int size, int modifiedMs) =>
      this.size == size && this.modifiedMs == modifiedMs;

  Song toSong() => Song(
    id: songIdForPath(path),
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    uri: Uri.file(path).toString(),
    filePath: path,
  );

  Map<String, dynamic> toJson() => {
    'path': path,
    'size': size,
    'modifiedMs': modifiedMs,
    'title': title,
    'artist': artist,
    'album': album,
    'track': trackNumber,
    'durationMs': duration.inMilliseconds,
  };

  static IndexedTrack? tryFromJson(Object? json) {
    if (json is! Map) return null;
    try {
      return IndexedTrack(
        path: json['path'] as String,
        size: json['size'] as int,
        modifiedMs: json['modifiedMs'] as int,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String?,
        trackNumber: json['track'] as int?,
        duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      );
    } catch (_) {
      return null;
    }
  }
}

/// [Song.id] for a file: a hash of its path, so it stays the same across
/// rescans and launches (likes and playlists use [Song.songKey] anyway).
int songIdForPath(String path) {
  var hash = 0x811c9dc5;
  for (final codeUnit in path.toLowerCase().codeUnits) {
    hash = ((hash ^ codeUnit) * 0x01000193) & 0x7fffffff;
  }
  return hash + 1;
}

/// Audio files the library picks up, by lower-case extension.
const libraryExtensions = {
  '.mp3',
  '.flac',
  '.m4a',
  '.mp4',
  '.aac',
  '.ogg',
  '.opus',
  '.wav',
  '.aif',
  '.aiff',
};

/// The outcome of [scanLibrary]: every audio file found, and whether the
/// index needs saving (files added, changed or gone).
class LibraryScan {
  const LibraryScan(this.tracks, {required this.changed});

  final List<IndexedTrack> tracks;
  final bool changed;
}

/// Lists the audio files under [folders] (recursively, each file once even
/// when folders overlap) and describes them, reusing [cached] entries whose
/// file is unchanged and reading the tags of the others. Folders or files
/// that can't be read are skipped. Sorted by artist, album, track number and
/// title. Synchronous and self-contained: meant for [Isolate.run].
LibraryScan scanLibrary(
  List<String> folders,
  Map<String, IndexedTrack> cached,
) {
  final files = <String, File>{};
  final pending = [for (final folder in folders) Directory(folder)];
  final visited = <String>{};
  while (pending.isNotEmpty) {
    final dir = pending.removeLast();
    if (!visited.add(_normalized(dir.path))) continue;
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      continue; // Missing folder or no access.
    }
    for (final entry in entries) {
      if (entry is Directory) {
        pending.add(entry);
      } else if (entry is File && _isAudio(entry.path)) {
        files.putIfAbsent(_normalized(entry.path), () => entry);
      }
    }
  }

  var changed = files.length != cached.length;
  final tracks = <IndexedTrack>[];
  for (final file in files.values) {
    final FileStat stat;
    try {
      stat = file.statSync();
    } catch (_) {
      continue;
    }
    final modifiedMs = stat.modified.millisecondsSinceEpoch;
    final known = cached[file.path];
    if (known != null && known.matches(stat.size, modifiedMs)) {
      tracks.add(known);
      continue;
    }
    changed = true;
    tracks.add(_readTrack(file, stat.size, modifiedMs));
  }

  String sortKey(String? value) => (value ?? '').toLowerCase();
  tracks.sort((a, b) {
    for (final order in [
      sortKey(a.artist).compareTo(sortKey(b.artist)),
      sortKey(a.album).compareTo(sortKey(b.album)),
      (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0),
      sortKey(a.title).compareTo(sortKey(b.title)),
    ]) {
      if (order != 0) return order;
    }
    return a.path.compareTo(b.path);
  });
  return LibraryScan(tracks, changed: changed);
}

/// The embedded cover of the file at [path], or null when it has none.
Uint8List? readArtwork(String path) {
  try {
    final pictures = readMetadata(File(path), getImage: true).pictures;
    return pictures.isEmpty ? null : pictures.first.bytes;
  } catch (_) {
    return null;
  }
}

IndexedTrack _readTrack(File file, int size, int modifiedMs) {
  String? clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  AudioMetadata? tags;
  try {
    tags = readMetadata(file, getImage: false);
  } catch (_) {
    // Untagged or unsupported: fall back to the file name.
  }
  return IndexedTrack(
    path: file.path,
    size: size,
    modifiedMs: modifiedMs,
    title: clean(tags?.title) ?? _fileTitle(file.path),
    artist: clean(tags?.artist) ?? clean(tags?.albumArtist) ?? 'Unknown artist',
    album: clean(tags?.album),
    trackNumber: tags?.trackNumber,
    duration: tags?.duration ?? Duration.zero,
  );
}

bool _isAudio(String path) {
  final dot = path.lastIndexOf('.');
  return dot >= 0 &&
      libraryExtensions.contains(path.substring(dot).toLowerCase());
}

String _fileTitle(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// Windows paths are case-insensitive: compare them in lower case.
String _normalized(String path) =>
    Platform.isWindows ? path.toLowerCase() : path;
