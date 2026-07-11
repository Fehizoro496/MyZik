import 'package:flutter/material.dart';

/// A filter/category chip.
class Category {
  const Category(this.label);
  final String label;
}

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

/// Static UI filter chips (not backed by the library).
class MusicCategories {
  const MusicCategories._();

  static const List<Category> home = [
    Category('All'),
    Category('New Release'),
    Category('Trending'),
    Category('Top Charts'),
  ];

  static const List<Category> myMusic = [
    Category('All'),
    Category('Playlists'),
    Category('Liked Songs'),
    Category('Downloaded'),
  ];

  static const List<Category> saved = [
    Category('Playlists'),
    Category('Songs'),
    Category('Albums'),
    Category('Artists'),
  ];
}
