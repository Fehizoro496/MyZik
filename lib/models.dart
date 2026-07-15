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

/// A user-created playlist: an ordered list of [Song.id]s under a name. Stores
/// ids (not full [Song]s) like liked songs, so a playlist survives a library
/// rescan and never duplicates track data.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.songIds = const [],
  });

  final String id;
  final String name;
  final List<int> songIds;

  Playlist copyWith({String? name, List<int>? songIds}) => Playlist(
    id: id,
    name: name ?? this.name,
    songIds: songIds ?? this.songIds,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'songIds': songIds};

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as String,
    name: json['name'] as String,
    songIds: [
      for (final v in (json['songIds'] as List? ?? const []))
        (v as num).toInt(),
    ],
  );
}
