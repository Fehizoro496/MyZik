import 'package:flutter/material.dart';

/// A single audio track. Source-agnostic on purpose: the device (on_audio_query)
/// and the future desktop repository both map their native rows into this, so
/// nothing plugin-specific leaks into the controller or the UI.
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration = Duration.zero,
    this.uri,
    this.filePath,
    this.artworkUrl,
    this.youtubeVideoId,
    this.contentKey,
  });

  /// Stable identifier from the source (e.g. MediaStore id) — used for artwork
  /// lookups and equality.
  final int id;
  final String title;
  final String artist;
  final String? album;
  final Duration duration;

  /// Playable location (content:// uri or file path). Used by the audio engine
  /// in the playback pass; may be null for sample data.
  final String? uri;

  /// The audio file on this device, readable with `dart:io` (unlike a
  /// content:// [uri]). Null for streamed tracks, which have no file.
  final String? filePath;

  /// Remote artwork for streamed tracks. Local tracks keep this null and use
  /// their embedded MediaStore artwork instead.
  final String? artworkUrl;

  /// Stable YouTube identity, present for both streams and downloaded tracks.
  final String? youtubeVideoId;

  /// `fp:` fingerprint of the audio file, set once the library has computed
  /// (or recalled) it. See [songKey].
  final String? contentKey;

  /// Identity of the recording across devices, under which likes, playlists
  /// and lyrics are stored: `yt:<videoId>` for YouTube tracks, the file's
  /// [contentKey] for local files, else `meta:` plus [metadataKey].
  String get songKey {
    final videoId = youtubeVideoId?.trim();
    if (videoId != null && videoId.isNotEmpty) return 'yt:$videoId';
    return contentKey ?? 'meta:$metadataKey';
  }

  /// Normalized `artist|title|seconds`, to recognise the same recording when
  /// files differ (another encoding, another device).
  String get metadataKey {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return '${normalize(artist)}|${normalize(title)}|${duration.inSeconds}';
  }

  /// This song with its file fingerprint set to [contentKey].
  Song withContentKey(String? contentKey) => Song(
    id: id,
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    uri: uri,
    filePath: filePath,
    artworkUrl: artworkUrl,
    youtubeVideoId: youtubeVideoId,
    contentKey: contentKey,
  );

  /// Key for [coverArtProvider]/[coverAccentProvider]: the remote artwork URL
  /// when there is one, otherwise the MediaStore id.
  CoverKey get coverKey => (id: id, url: artworkUrl);

  /// Deterministic gradient placeholder for the album art, keyed off [id] so a
  /// given track always gets the same colors until real artwork is wired in.
  List<Color> get artGradient =>
      AppArt.gradients[id.abs() % AppArt.gradients.length];

  String get durationLabel {
    final s = duration.inSeconds;
    final m = s ~/ 60;
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }
}

/// Identifies a song's cover regardless of where it comes from. A record so
/// Riverpod families get value equality (two [Song] instances for the same
/// stream share the cached cover).
typedef CoverKey = ({int id, String? url});

/// Album-art gradient palette used as a placeholder before real cover artwork
/// is loaded.
class AppArt {
  const AppArt._();

  static const List<List<Color>> gradients = [
    [Color(0xFF6F5CFF), Color(0xFF3B6FE0)],
    [Color(0xFFFF6F91), Color(0xFF8A4FFF)],
    [Color(0xFF4FD0FF), Color(0xFF4F6FFF)],
    [Color(0xFFFFB86F), Color(0xFFFF6F91)],
    [Color(0xFF3BE0C0), Color(0xFF3B8FE0)],
    [Color(0xFFB86FFF), Color(0xFF6F5CFF)],
    [Color(0xFFE0C03B), Color(0xFFE0703B)],
  ];
}

/// Whether a [MusicCollection] groups an album or an artist — drives the
/// cover shape (rounded square vs. circle) and the labels in the detail view.
enum CollectionKind { album, artist }

/// A group of tracks derived from the flat library: all the songs of one album
/// or one artist. Built on the fly by [albumsFrom] / [artistsFrom] since the
/// library has no first-class album/artist entities.
class MusicCollection {
  const MusicCollection({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.songs,
  });

  final CollectionKind kind;

  /// Album name or artist name.
  final String title;

  /// Album's artist (or "Various artists") for albums; the track count for
  /// artists.
  final String subtitle;

  final List<Song> songs;

  /// Representative track used for the cover artwork.
  Song get cover => songs.first;

  bool get isArtist => kind == CollectionKind.artist;
}

/// Groups [songs] by album, sorted alphabetically. Tracks with no album tag
/// fall under a single "Unknown album" bucket.
List<MusicCollection> albumsFrom(List<Song> songs) {
  final byAlbum = <String, List<Song>>{};
  for (final s in songs) {
    byAlbum.putIfAbsent(s.album ?? 'Unknown album', () => <Song>[]).add(s);
  }
  final albums = [
    for (final e in byAlbum.entries)
      MusicCollection(
        kind: CollectionKind.album,
        title: e.key,
        subtitle: _albumArtist(e.value),
        songs: e.value,
      ),
  ];
  albums.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return albums;
}

/// Groups [songs] by artist, sorted alphabetically.
List<MusicCollection> artistsFrom(List<Song> songs) {
  final byArtist = <String, List<Song>>{};
  for (final s in songs) {
    byArtist.putIfAbsent(s.artist, () => <Song>[]).add(s);
  }
  final artists = [
    for (final e in byArtist.entries)
      MusicCollection(
        kind: CollectionKind.artist,
        title: e.key,
        subtitle: _songCountLabel(e.value.length),
        songs: e.value,
      ),
  ];
  artists.sort(
    (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  );
  return artists;
}

String _albumArtist(List<Song> songs) {
  final artists = songs.map((s) => s.artist).toSet();
  return artists.length == 1 ? artists.first : 'Various artists';
}

String _songCountLabel(int count) => '$count ${count == 1 ? 'song' : 'songs'}';

/// A user-created playlist: an ordered list of [Song.songKey]s under a name.
/// Stores keys (not full [Song]s), so a playlist survives a library rescan
/// and means the same tracks on every device.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.songKeys = const [],
    this.songIds = const [],
  });

  final String id;
  final String name;
  final List<String> songKeys;

  /// Device-local [Song.id]s saved before portable keys and not yet matched
  /// to a key (their track isn't in the library). Migrated by
  /// `SongKeyMigration` once it shows up; never shown.
  final List<int> songIds;

  bool contains(Song song) => songKeys.contains(song.songKey);

  Playlist copyWith({
    String? name,
    List<String>? songKeys,
    List<int>? songIds,
  }) => Playlist(
    id: id,
    name: name ?? this.name,
    songKeys: songKeys ?? this.songKeys,
    songIds: songIds ?? this.songIds,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songKeys': songKeys,
    if (songIds.isNotEmpty) 'songIds': songIds,
  };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as String,
    name: json['name'] as String,
    songKeys: [
      for (final key in (json['songKeys'] as List? ?? const [])) key as String,
    ],
    songIds: [
      for (final v in (json['songIds'] as List? ?? const []))
        (v as num).toInt(),
    ],
  );
}
