import 'package:flutter/material.dart';

/// A filter/category chip.
class Category {
  const Category(this.label);
  final String label;
}

/// A playlist / song entry shown in list rows and cards.
class Track {
  const Track({
    required this.title,
    required this.artist,
    required this.count,
    required this.gradient,
  });

  final String title;
  final String artist;
  final int count;

  /// Two-color gradient used as the album-art placeholder.
  final List<Color> gradient;
}

/// Static content backing the three screens. In a real app this would come
/// from a repository / API; here it reproduces the design's sample data.
class MusicData {
  const MusicData._();

  static const List<Category> homeCategories = [
    Category('All'),
    Category('New Release'),
    Category('Trending'),
    Category('Top Charts'),
  ];

  static const List<Category> musicCategories = [
    Category('All'),
    Category('Playlists'),
    Category('Liked Songs'),
    Category('Downloaded'),
  ];

  static const List<Category> savedCategories = [
    Category('Playlists'),
    Category('Songs'),
    Category('Albums'),
    Category('Artists'),
  ];

  static const List<List<Color>> _artGradients = [
    [Color(0xFF6F5CFF), Color(0xFF3B6FE0)],
    [Color(0xFFFF6F91), Color(0xFF8A4FFF)],
    [Color(0xFF4FD0FF), Color(0xFF4F6FFF)],
    [Color(0xFFFFB86F), Color(0xFFFF6F91)],
    [Color(0xFF3BE0C0), Color(0xFF3B8FE0)],
    [Color(0xFFB86FFF), Color(0xFF6F5CFF)],
    [Color(0xFFE0C03B), Color(0xFFE0703B)],
  ];

  static List<Color> art(int i) => _artGradients[i % _artGradients.length];

  static final List<Track> topPlaylists = [
    Track(
      title: 'Starlit Reverie',
      artist: 'Budiarti',
      count: 8,
      gradient: art(0),
    ),
    Track(
      title: 'Midnight Confessions',
      artist: 'Alexiao',
      count: 24,
      gradient: art(1),
    ),
    Track(
      title: 'Lost in the Echo',
      artist: 'Alexiao',
      count: 24,
      gradient: art(2),
    ),
  ];

  static final List<Track> songs = [
    Track(
      title: 'Starlit Reverie',
      artist: 'Budiarti',
      count: 8,
      gradient: art(0),
    ),
    Track(
      title: 'Midnight Confessions',
      artist: 'Alexiao',
      count: 24,
      gradient: art(1),
    ),
    Track(
      title: 'Lost in the Echo',
      artist: 'Alexiao',
      count: 24,
      gradient: art(2),
    ),
    Track(
      title: 'Letters I Never Sent',
      artist: 'Alexiao',
      count: 24,
      gradient: art(3),
    ),
    Track(
      title: 'Breaking the Silence',
      artist: 'Alexiao',
      count: 24,
      gradient: art(4),
    ),
    Track(
      title: 'Tears on the Vinyl',
      artist: 'Alexiao',
      count: 24,
      gradient: art(5),
    ),
    Track(
      title: 'Lonely Nights',
      artist: 'Alexiao',
      count: 24,
      gradient: art(6),
    ),
  ];
}
